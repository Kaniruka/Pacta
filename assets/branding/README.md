# Pacta app icon

`pacta-foreground.svg` is the editable, transparent, pure-vector portrait redrawn
from the user-provided `chibi-app-icon.png` on 2026-11-04. It deliberately simplifies
the original shading and hair while retaining the cat ears, cowlick, bone clips,
bow, tilted face and original character colors. It contains no embedded bitmap.

Regenerate native assets from the repository root:

```powershell
python -m venv .scratch/icon-tools
.scratch/icon-tools/Scripts/python -m pip install pillow==13.0.0 resvg-py==0.5.0
.scratch/icon-tools/Scripts/python scripts/generate_app_icons.py
```

Commit the SVG, generated Android XML/PNG, Windows ICO and `pacta-icon.png`
together. The script only accepts filled paths, so the Android VectorDrawable
and raster exports share identical geometry. No Flutter runtime dependency is
required. `pacta-icon.png` is a preview/export, not an in-app UI asset.

## Platform behavior

- Android 26+: adaptive icon with a full-bleed background and independent color
  vector foreground. The portrait fills the tile from the lower left, matching
  the user's requested composition. It intentionally extends beyond the safe
  circle; launcher masks may crop hair and clothing. The same composition is
  mapped to the nominal 72dp visible area of the 108dp adaptive layer.
- Android 31+: background uses `system_accent1_100` in light mode and
  `system_accent1_700` in dark mode. These are wallpaper/system theme colors,
  not Flutter's in-app theme. Launcher refresh/caching behavior varies.
- Earlier Android: light/dark fallback colors are the existing Flutter seed
  `0xff385a52`'s Material 3 `primaryContainer` (`#A0F2DF` / `#005145`).
  Pre-adaptive launchers use the static light PNGs.
- Windows: static light default-theme tile in 16, 20, 24, 32, 40, 48, 64, 128
  and 256px ICO sizes, shared by the window, executable and existing tray code.
- No monochrome layer is supplied: the selected design preserves character
  colors. A launcher may independently recolor icons when users enable its
  themed/automatic icon mode; an app cannot promise to override that setting.
- Display names are `Pacta`. Package IDs, Dart package name, executable filename
  and internal identifiers remain unchanged to preserve installation identity.

Android behavior reference: [Adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive).
Design review follows `apple-design`'s `app-icons.md` sections “Layer design”,
“Icon shape” and “Design”: separate the background, simplify small details,
and maintain a consistent portrait across platforms. The user's explicit
lower-left alignment and acceptance of lost edge details override the generic
recommendation to center the full portrait inside the safe zone.
Apple-only rendering effects are not applied to Android or Windows.

## Validation (2026-11-04)

- `flutter analyze`: passed; `flutter test`: 329 passed (no Dart changes).
- `flutter build windows --debug`: passed with the final lower-left icon.
- Final lower-left PNG visually inspected; independent Standards and Spec
  reviews reported no findings after the composition correction.
- Android build-tools 36.1.0 `aapt2 compile` and `link` passed for the final
  resources using a minimal validation manifest and Android 36 platform jar.
  Full `flutter build apk --debug` encountered a Maven TLS/download failure
  resolving `com.google.protobuf:protobuf-java:3.17.2`; APK build is unverified.
- No Android device/AVD was available. Windows desktop visual verification
  was stopped by the user; no real launcher/window visual pass is claimed.
