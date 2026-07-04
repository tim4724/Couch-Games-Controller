# Couch Games Controller

Native **controller** apps for the Couch Games party-game suite. The
TV/computer is the display; phones are the controllers: scan the room code the
display shows and your phone becomes the gamepad.

The launcher (home screen) is fully native per platform. Each game's
controller is a **remote web page** loaded in a hardened top-level web view
under launcher-owned chrome — games ship controller changes without an app
update.

[CONTRACT.md](CONTRACT.md) is the launcher⇄game contract: join-URL identity
params, live rename, session end, theming hints, and the safe zone. Both apps
implement it identically.

## Layout

- `android/` — Jetpack Compose / Material 3 app (Kotlin)
- `ios/` — SwiftUI app (Swift, project generated with XcodeGen; see
  [ios/README.md](ios/README.md))

## Android: build & run

Standard Gradle project — open `android/` in Android Studio, or:

```sh
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties   # once per checkout
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

QR scanning runs inside Play Services (`GmsBarcodeScanning`, no CAMERA
permission), so the scan flow needs a device or emulator with Play Services.

## iOS: build & run

```sh
cd ios
xcodegen generate    # brew install xcodegen, once
open CouchGames.xcodeproj
```

QR scanning uses AVFoundation (camera permission) and degrades to manual
room-code entry in the simulator.

## Where things live

- `android/app/src/main/assets/games-manifest.json` — the games list; drives
  the home screen, scan/typed-code resolution, and relay probing. Cover art
  sits next to it in `assets/artwork/`. The iOS app bundles copies under
  `ios/CouchGames/Resources/` — keep them in sync when the manifest changes.
- `android/app/src/main/res/raw/` — bundled gameplay-loop videos (`res/raw`
  because `VideoView` needs an `android.resource://` URI).
- `android/app/src/main/java/com/couchgames/controller/` — `data/` (manifest
  model, join resolution, relay probe, prefs), `ui/main/` (home), `ui/game/`
  (WebView game host), `theme/`.
- `ios/CouchGames/` — `Data/` (same responsibilities as Android `data/`),
  `UI/Main/`, `GameHost/` (WKWebView game host), `Theme/`.
