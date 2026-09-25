# Android build — not yet exported

No APK is bundled here. The `Android` export preset in `export_presets.cfg`
is wired up (`./builds/android/TheUnknown.apk`, `com.theunknown.game`,
arm64-v8a), but building it needs the Android export templates + SDK +
signing key, which are not part of this repo.

To produce it (on a machine with the Godot Android setup):

```sh
godot --headless --path . --export-release "Android" ./builds/android/TheUnknown.apk
```

Heads-up: the game is keyboard/mouse-first (WASD, click-to-look, `L`/`M`/Space
shortcuts). It will install and render on a phone, but it is not genuinely
playable until touch controls are added.
