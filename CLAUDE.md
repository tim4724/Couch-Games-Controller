# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Two native **launcher** apps (Android/Kotlin+Compose, iOS/Swift+SwiftUI) that are the shell
for the Couch Games party-game suite. Each game's controller is a remote web page loaded in a
hardened top-level web view under launcher chrome. Read `README.md` for layout and
`CONTRACT.md` for the launcher⇄game interface — don't restate them here.

## Build & run

```sh
# Android
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties   # once per checkout
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk

# iOS (Xcode project is generated, not committed)
cd ios
xcodegen generate    # brew install xcodegen, once
open CouchGames.xcodeproj
```

Android: minSdk 24 / target 36, namespace `com.couchgames.controller`. iOS: 17+, no
third-party dependencies. There is no automated test suite.

## The two apps are functional parity ports

Android `data/` ↔ iOS `Data/`, `ui/main/` ↔ `UI/Main/`, `ui/game/` (WebView host) ↔
`GameHost/` (WKWebView host), `theme/` ↔ `Theme/`. A behavior change on one platform almost
always needs the mirrored change on the other. Both implement `CONTRACT.md` identically.

## Things that must stay in sync (and their checks)

- **Manifest + artwork**: `android/app/src/main/assets/games-manifest.json` +
  `assets/artwork/` are the source of truth; `ios/CouchGames/Resources/` holds byte-identical
  copies. Update both when either changes. The manifest is purely structural — no translated
  text; per-game display copy lives in string resources under `game_<id>_*` keys.
- **Localization** (11 HexStacker locales): Android `res/values[-XX]/strings.xml`, iOS
  `CouchGames/Resources/*.xcstrings`. After any string change run:
  ```sh
  python3 tools/check_l10n_sync.py
  ```
  It enforces locale coverage on both platforms, identical shared translations, and identical
  manifest copies. Platform-only strings must be declared in the script's `ANDROID_ONLY` /
  `IOS_ONLY` lists — an undeclared one-sided string fails the check.

## The CONTRACT is a compatibility boundary

`CONTRACT.md` is versioned via `cgv`; the same deployed controller must keep working in a
plain browser, so all shell behavior is gated on `cgv=1`. Relay-declared join targets
(`url`/`origin`) are UNTRUSTED and re-validated against the manifest host allow-list before
loading. Changing contract semantics means bumping `cgv` and updating both apps.
