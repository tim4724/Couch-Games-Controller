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

## Checklist for a new game

1. Read `cgv` + `cgName`; when `cgv=1`: skip name entry, don't persist the name,
   suppress own back/leave affordances.
2. Implement `window.CouchGames.setName(name)`: apply locally + broadcast.
3. Call `window.CouchGamesHost.gameEnded(reason)` at the terminal-session-end
   chokepoint when available, else fall back to normal web behavior.
4. Keep interactive UI inside the safe zone (§5).
5. *(Optional)* Declare `theme-color` / `cg-accent-color` metas (§4).
6. Declare the game in `games-manifest.json` (hosts, controllerBaseUrl, room-code
   format). No other launcher changes needed.

Keep all contract code in the game's own bundle — game origins typically ship
`script-src 'self'`, and the launcher only injects the guarded `setName` call and a
self-contained meta observer (both via `evaluateJavascript`, which is exempt from the
page's CSP).

## Versioning

`cgv` is bumped only for breaking changes. Games should treat an unknown higher
version as "shell present, behave per the highest version you know".
