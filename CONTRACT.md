# Couch Games Controller Contract — v1

The interface between the **Couch Games launcher** (native Android app hosting a game's
web controller in a WebView) and a **game's controller page**. A game that implements
these touchpoints plugs into the launcher with zero launcher-side changes — new games
only declare themselves in `games-manifest.json`.

The launcher owns *identity* (player name) and *session chrome* (joining, leaving);
the game owns everything else (colors, avatars, gameplay, match flow).

## 1. Launcher → game, at load: URL parameters

The launcher appends two query parameters to the join URL, preserving any existing
`?claim=` and `#instance`:

```
https://<game-host>/<ROOMCODE>?cgv=1&cgName=<name>[#<instance>]
```

| Param    | Meaning |
|----------|---------|
| `cgv=1`  | Contract version; presence means "running inside the Couch Games shell". Gate ALL shell behavior on it — the same deployed controller must keep working in a plain browser. |
| `cgName` | The player's name. Guaranteed non-blank and ≤ 16 characters; sanitize defensively anyway. |

When `cgv=1` is present, the game must:

- **Skip the name screen.** Use `cgName` and never offer a path back to name entry —
  the launcher is the identity authority.
- **Not persist the injected name** into its own storage. It arrives fresh on every
  launch/rename; persisting it would leak into the standalone-browser experience.
- **Neutralize its own back/leave handling.** The shell swallows system back and shows
  its own LEAVE bar; in-game back affordances would fight it (modals relying on
  `history.back()` need a direct close instead).

Colors, avatars, sound, and match flow stay entirely game-owned.

## 2. Launcher → game, live rename: `window.CouchGames.setName(name)`

The game *implements*, the launcher *calls* — when the player renames in the in-game
bar, and again on every page load (belt-and-suspenders with `cgName`).

```js
window.CouchGames = {
  setName(name) {
    // Apply live: update local UI AND broadcast to the display,
    // exactly like an in-game rename would.
  },
};
```

The launcher's call is guarded, so a game that hasn't implemented it is a harmless
no-op — the URL param still prefills the name on the next load.

## 3. Game → launcher, session end: `window.CouchGamesHost.gameEnded(reason)`

The launcher *implements* (via `addJavascriptInterface`), the game *calls* — **only on
terminal session end**: the room closed, the display disconnected for good, the join
was rejected. Match-over / "Play again" screens are game flow and stay in-game.

```js
if (window.CouchGamesHost?.gameEnded) {
  window.CouchGamesHost.gameEnded(reason);
} else {
  // plain-browser fallback: whatever the game normally does
}
```

The launcher tears down the WebView and returns home showing a message. The call is
fire-once (extras ignored) and the game must **not** also navigate itself.

| `reason`         | Message shown |
|------------------|---------------|
| `game_ended`     | "The party ended" |
| `room_not_found` | "Room not found" |
| `game_full`      | "Room is full" |
| `replaced`       | "You joined from another device" |
| *anything else*  | "The party ended" (unknown values tolerated) |

## 4. Game → launcher, optional theming hints: `<head>` metas

The launcher reads two metas and tints its own floating chrome to match — at load and
live (an injected observer watches them, so mutating a meta's `content` retints
mid-session). Pure cosmetics; harmlessly ignored in a plain browser.

```html
<meta name="theme-color" content="#0b1020">      <!-- web standard -->
<meta name="cg-accent-color" content="#ffcc00">  <!-- Couch Games custom -->
```

| Meta | Launcher effect |
|------|-----------------|
| `theme-color`     | Tints the top chrome (the scrim behind the status bar + LEAVE bar). Text/icons flip black/white by luminance. |
| `cg-accent-color` | Colors launcher accents shown over the game: name chip, joining spinner, rename sheet controls. |

Any sRGB CSS color; alpha is ignored (the chrome is opaque); absent or unparseable
values fall back to the launcher's dark graphite. `media` attributes are honored
(first matching meta wins) and re-evaluated on system scheme flips. Metas must live
in `<head>`.

## 5. Launcher → game, layout: edge-to-edge hosting and the safe zone

The page spans the **full physical screen**; the launcher chrome floats on top.
Visuals may (and should) bleed behind the chrome — **interactive UI must stay out
from under it**. The safe zone is published two ways:

1. **Standard CSS**: with `viewport-fit=cover`, the launcher mirrors its chrome (top)
   and the display cutout/gutter (other edges) into `env(safe-area-inset-*)` as a
   synthetic display cutout — the standard machinery works as it would for a notch.
2. **Launcher vars** (authoritative): `--cg-safe-top/-left/-right/-bottom` on
   `document.documentElement` — CSS px, live-updated, re-set on every navigation.
   These don't depend on WebView's cutout plumbing, so they also cover cases where
   it bails (e.g. split-screen).

The horizontal insets align with the chrome's *content*, not just the cutout: the
right inset reaches the name chip's edge and the left mirrors that gutter onto the
close icon — so a top row anchored to the safe zone lines up with the launcher's
controls. Expect a small non-zero value even with no notch.

Recommended pattern — correct in the shell AND in a plain browser:

```css
#hud {
  padding-top: max(var(--cg-safe-top, 0px), env(safe-area-inset-top, 0px));
}
```

## 6. Game display → relay, at room create: controller-URL template

So a player who **types a room code** (rather than scanning the display's QR) lands
on the right game, the game's display registers a *controller-URL template* with the
shared relay when it creates the room. This is the discovery counterpart to §1: the QR
carries the full URL, a typed code carries nothing, so the relay has to know where the
code lives.

The template rides the relay's `create` message:

```
Client → relay:  create { clientId, maxClients, url? }
```

- `url` is an absolute **https** template of the join-URL shape, with `{room}` and
  `{instance}` placeholders — e.g. `https://play.example.com/{room}#{instance}`. It must
  match the URL a scanned QR would produce (room code as the first path segment; instance
  in the fragment, kept out of request logs).
- The relay accepts only absolute-https templates and **rejects the whole create** on an
  invalid one, so plain-http origins (local dev, E2E) register none — pass no `url`.
- Registering a `url` is optional. A display that registers none but is served from a
  Couch-Games-owned origin can still be found via that `origin` (below).

The launcher resolves a typed code through `GET {relayBase}/room/{code}`:

```
200 → { url?, origin? }   404 → not found
```

- `url` — the relay's stored template with `{room}`/`{instance}` **already substituted**
  for this room (the launcher never sees raw placeholders).
- `origin` — the room's declared origin, a fallback when no `url` template was registered;
  the launcher resolves the bare code against it (`<origin>/<code>`).
- **Both are host-declared and UNTRUSTED.** The launcher re-validates the host against the
  `games-manifest.json` allow-list before loading — a relay entry can't redirect a code to
  an arbitrary origin.

Registering a `url` is what makes typed-code join deterministic; without it a code only
resolves when the game is the sole live game or is disambiguated by `origin`.

## 7. Launcher → game, app lifecycle: synthetic `pagehide` on background

When the player leaves the launcher app (home, app switch, lock) the shell
dispatches a synthetic persisted `pagehide` on `window` — the same event a
browser fires when it freezes a page into the back/forward cache:

```js
window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true }));
```

A controller should close its relay socket in its `pagehide` handler so the
display sees the player leave *immediately*. Without this, disconnect timing is
platform luck: Android drops the socket whenever the OS freezes the cached app
process (OEM-dependent, can take a while), and iOS never drops it — WKWebView's
out-of-process network stack keeps the socket alive and answering pings for as
long as the app stays suspended, leaving a zombie player on the display.

There is no synthetic counterpart on return: the engine fires the standard
`visibilitychange` → `visible`, and the controller should reconnect there. Both
events are ordinary web behavior, so the same code is correct in a plain
browser (where `pagehide` fires on navigation/bfcache instead). Additive in v1:
a game without a `pagehide` handler simply keeps today's behavior.

## Checklist for a new game

1. Read `cgv` + `cgName`; when `cgv=1`: skip name entry, don't persist the name,
   suppress own back/leave affordances.
2. Implement `window.CouchGames.setName(name)`: apply locally + broadcast.
3. Call `window.CouchGamesHost.gameEnded(reason)` at the terminal-session-end
   chokepoint when available, else fall back to normal web behavior.
4. Keep interactive UI inside the safe zone (§5).
5. Close the relay socket on `pagehide`; reconnect on `visibilitychange` →
   `visible` (§7).
6. *(Optional)* Declare `theme-color` / `cg-accent-color` metas (§4).
7. Register the controller-URL template on room create so typed codes resolve (§6).
8. Declare the game in `games-manifest.json` (hosts, controllerBaseUrl, room-code
   format). No other launcher changes needed.

Keep all contract code in the game's own bundle — game origins typically ship
`script-src 'self'`, and the launcher only injects the guarded `setName` call and a
self-contained meta observer (both via `evaluateJavascript`, which is exempt from the
page's CSP).

## Versioning

`cgv` is bumped only for breaking changes. Games should treat an unknown higher
version as "shell present, behave per the highest version you know".
