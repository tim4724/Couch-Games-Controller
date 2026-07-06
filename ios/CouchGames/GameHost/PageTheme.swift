import SwiftUI
import Foundation

/// Optional theming hints from the controller page's `<head>` (CONTRACT.md §4):
/// `theme-color` tints the launcher's top chrome, `cg-accent-color` tints launcher
/// accents shown over the game. Purely cosmetic — absent or unparseable metas fall
/// back to the stock dark chrome.
struct PageTheme: Equatable {
    var bar: Color? = nil
    var accent: Color? = nil
}

/// Bridge input is untrusted page data: strict shape, hard length cap, fallback on anything odd.
func parsePageTheme(_ json: String?) -> PageTheme {
    guard let json, json.utf16.count <= 256 else { return PageTheme() }
    guard let data = json.data(using: .utf8),
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return PageTheme() }
    return PageTheme(
        bar: parseCssRgb(object["bar"] as? String),
        accent: parseCssRgb(object["accent"] as? String)
    )
}

// Computed styles serialize sRGB colors as rgb(r, g, b) / rgba(r, g, b, a).
// Wide-gamut serializations (color(display-p3 …), lab(…)) deliberately fail.
private let cssRgbRegex = try! NSRegularExpression(
    pattern: "^rgba?\\((\\d{1,3}), (\\d{1,3}), (\\d{1,3})(?:, [0-9.]+)?\\)$"
)

/// The ENTIRE trimmed string must match the computed-style rgb()/rgba() format
/// (single space after commas). Components > 255 → nil. Alpha is deliberately
/// dropped: the chrome behind the status bar must be opaque.
func parseCssRgb(_ value: String?) -> Color? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
    guard let match = cssRgbRegex.firstMatch(in: trimmed, options: [], range: fullRange),
          match.range == fullRange
    else { return nil }

    func component(_ index: Int) -> Int? {
        guard let range = Range(match.range(at: index), in: trimmed) else { return nil }
        return Int(trimmed[range])
    }

    guard let r = component(1), let g = component(2), let b = component(3),
          r <= 255, g <= 255, b <= 255
    else { return nil }
    return Color(.sRGB, red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0, opacity: 1.0)
}

/// Maps the untrusted, web-supplied session-end reason to player-facing copy.
/// Unknown values must be tolerated, never crash/ignore.
func gameEndMessage(_ reason: String?) -> String {
    switch reason {
    case "room_not_found": return String(localized: "Room not found")
    case "game_full": return String(localized: "Room is full")
    case "replaced": return String(localized: "You joined from another device")
    default: return String(localized: "The party ended")
    }
}

enum GameHostJS {
    /// Document-start user script (all frames): defines
    /// `window.CouchGamesHost.{gameEnded,themeChanged}` posting `{type, value}` to
    /// `window.webkit.messageHandlers.cgHost`. Idempotent — the shim must exist on
    /// every page load/navigation, but never redefine an already-installed bridge.
    static let bridgeShim = """
    (function () {
      if (window.CouchGamesHost) { return; }
      function post(type, value) {
        try {
          window.webkit.messageHandlers.cgHost.postMessage({
            type: type,
            value: value == null ? null : String(value)
          });
        } catch (e) {}
      }
      window.CouchGamesHost = {
        gameEnded: function (reason) { post('gameEnded', reason); },
        themeChanged: function (json) { post('themeChanged', json); }
      };
    })();
    """

    /// The theme-meta observer, evaluated after each page load. Pushes the metas'
    /// state through `CouchGamesHost.themeChanged` immediately and on every change —
    /// head mutations via MutationObserver, plus scheme flips (a `media` attribute
    /// can start/stop matching). Pushes are deduped. Idempotent: re-running on a
    /// document that already has the observer just re-pushes.
    static let watchPageTheme = """
    (function () {
      if (window.__cgThemePush) { window.__cgThemePush(); return; }
      var last = null;
      function read(name) {
        var metas = document.querySelectorAll('meta[name="' + name + '"]');
        if (!metas.length) return null;
        var chosen = null;
        for (var i = 0; i < metas.length; i++) {
          var m = metas[i].getAttribute('media');
          if (!m || (window.matchMedia && window.matchMedia(m).matches)) { chosen = metas[i]; break; }
        }
        if (!chosen) chosen = metas[0];
        var content = chosen.getAttribute('content');
        if (!content) return null;
        if (!(window.CSS && CSS.supports && CSS.supports('color', content))) return null;
        var probe = document.createElement('div');
        probe.style.color = content;
        document.documentElement.appendChild(probe);
        var rgb = getComputedStyle(probe).color;
        probe.remove();
        return rgb || null;
      }
      function push() {
        var t = JSON.stringify({ bar: read('theme-color'), accent: read('cg-accent-color') });
        if (t === last) return;
        last = t;
        if (window.CouchGamesHost && window.CouchGamesHost.themeChanged) window.CouchGamesHost.themeChanged(t);
      }
      window.__cgThemePush = push;
      if (document.head) new MutationObserver(push).observe(document.head,
        { childList: true, subtree: true, attributes: true, attributeFilter: ['content', 'media', 'name'] });
      if (window.matchMedia) {
        var mq = window.matchMedia('(prefers-color-scheme: dark)');
        if (mq.addEventListener) mq.addEventListener('change', push); else if (mq.addListener) mq.addListener(push);
      }
      push();
    })();
    """

    /// Push the current name into the running controller (CONTRACT.md §2). Guarded,
    /// so a game that hasn't implemented setName is a harmless no-op. nil when the
    /// name is blank — a blank name is never injected.
    static func nameInjection(name: String) -> String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode([name]),
              let array = String(data: data, encoding: .utf8)
        else { return nil }
        let quoted = String(array.dropFirst().dropLast())  // "[\"…\"]" → "\"…\""
        return "window.CouchGames && typeof window.CouchGames.setName === 'function' && window.CouchGames.setName(\(quoted));"
    }

    /// Resolve the page's best icon URL (absolute). Prefers apple-touch-icon (usually
    /// 180px, so it stays crisp on the rejoin card) over a rel~=icon, and falls back
    /// to the conventional /favicon.ico. Returns null when the page declares nothing
    /// and there's no default — the native side then keeps the play glyph.
    ///
    /// SVG icons are skipped: UIImage(data:) can't decode them, so an SVG href would
    /// fetch fine and then fail to become an image, leaving the glyph. Pages commonly
    /// list <link rel="icon" href="/favicon.svg"> BEFORE a raster fallback (HexStacker
    /// does), so we scan past the SVG to the first raster link rather than take the
    /// first match.
    static let faviconHref = """
    (function () {
      function isSvg(l) {
        var t = (l.getAttribute('type') || '').toLowerCase();
        var h = (l.href || '').toLowerCase().split(/[?#]/)[0];
        return t.indexOf('svg') >= 0 || h.slice(-4) === '.svg';
      }
      function pick(sel) {
        var links = document.querySelectorAll(sel);
        for (var i = 0; i < links.length; i++) {
          if (links[i].href && !isSvg(links[i])) return links[i].href;
        }
        return null;
      }
      return pick('link[rel~="apple-touch-icon"]')
        || pick('link[rel~="icon"]')
        || (location.origin ? location.origin + '/favicon.ico' : null);
    })();
    """

    /// Publish the safe zone to the page as CSS vars on <html> (CONTRACT.md §5), in CSS px.
    static func safeZonePush(_ zone: SafeZone) -> String {
        "(function () { var s = document.documentElement.style;"
            + " s.setProperty('--cg-safe-top', '\(zone.top)px');"
            + " s.setProperty('--cg-safe-left', '\(zone.left)px');"
            + " s.setProperty('--cg-safe-right', '\(zone.right)px');"
            + " s.setProperty('--cg-safe-bottom', '\(zone.bottom)px'); })();"
    }
}
