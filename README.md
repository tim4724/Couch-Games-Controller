# Couch Games Controller

Native Android **controller** app for the Couch Games party-game suite. The
TV/computer is the display; phones are the controllers: scan the room code the
display shows and your phone becomes the gamepad.

The launcher (home screen) is native Jetpack Compose / Material 3. Each game's
controller is a **remote web page** loaded in a hardened top-level WebView under
launcher-owned chrome — games ship controller changes without an app update.

[CONTRACT.md](CONTRACT.md) is the launcher⇄game contract: join-URL identity
params, live rename, session end, theming hints, and the safe zone.

## Build & run

Standard Android Gradle project — open in Android Studio, or:

```sh
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties   # once per checkout
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

QR scanning runs inside Play Services (`GmsBarcodeScanning`, no CAMERA
permission), so the scan flow needs a device or emulator with Play Services.

## Where things live

- `app/src/main/assets/games-manifest.json` — the games list; drives the home
  screen, scan/typed-code resolution, and relay probing. Cover art sits next to
  it in `assets/artwork/` (referenced by manifest paths).
- `app/src/main/res/raw/` — bundled gameplay-loop videos. These are `res/raw`
  rather than assets because `VideoView` needs an `android.resource://` URI.
- `app/src/main/java/com/couchgames/controller/` — `data/` (manifest model,
  join resolution, relay probe, prefs), `ui/main/` (home), `ui/game/` (WebView
  game host), `theme/`.
