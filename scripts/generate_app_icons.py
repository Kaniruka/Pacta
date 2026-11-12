"""Generate native icons from the editable SVG; pip install pillow resvg-py."""

from io import BytesIO
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image
import resvg_py


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/pacta-foreground.svg"
RES = ROOT / "android/app/src/main/res"
# ColorScheme.fromSeed(0xff385a52).primaryContainer, matching lib/main.dart.
LIGHT = "#A0F2DF"
DARK = "#005145"
# Fill the tile from the lower left; cropping hair/clothing is intentional.
PORTRAIT_SCALE = 1.06
PORTRAIT_X = -64
PORTRAIT_Y = 1024 - 978 * PORTRAIT_SCALE


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def main():
    svg = ET.parse(SOURCE).getroot()
    paths = list(svg)
    if any(p.tag != "{http://www.w3.org/2000/svg}path" for p in paths):
        raise ValueError("The source must contain only filled paths")
    if any(set(p.attrib) != {"fill", "d"} for p in paths):
        raise ValueError("Paths must use explicit fill and d attributes only")

    # Map the same composition into Android's nominal 72dp visible area.
    # The launcher applies its own mask; edge details may be cropped by design.
    unit = 72 / 1024
    vector = ['<vector xmlns:android="http://schemas.android.com/apk/res/android"',
              '    android:width="108dp" android:height="108dp"',
              '    android:viewportWidth="108" android:viewportHeight="108">',
              f'    <group android:scaleX="{PORTRAIT_SCALE * unit}" android:scaleY="{PORTRAIT_SCALE * unit}"',
              f'        android:translateX="{18 + PORTRAIT_X * unit}" android:translateY="{18 + PORTRAIT_Y * unit}">']
    for path in paths:
        vector.append(f'        <path android:fillColor="{path.attrib["fill"]}" '
                      f'android:pathData="{path.attrib["d"]}" />')
    vector += ['    </group>', '</vector>', '']
    write(RES / "drawable/pacta_launcher_foreground.xml", "\n".join(vector))
    write(RES / "mipmap-anydpi-v26/ic_launcher.xml", '''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/pacta_launcher_background" />
    <foreground android:drawable="@drawable/pacta_launcher_foreground" />
</adaptive-icon>
''')
    for qualifier, color in [("values", LIGHT), ("values-night", DARK),
                             ("values-v31", "@android:color/system_accent1_100"),
                             ("values-night-v31", "@android:color/system_accent1_700")]:
        write(RES / qualifier / "launcher_colors.xml",
              f'<resources>\n    <color name="pacta_launcher_background">{color}</color>\n</resources>\n')

    # Legacy/Windows surfaces have no adaptive mask: use a rounded tile.
    body = "".join(ET.tostring(p, encoding="unicode") for p in paths)
    tile = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<rect width="1024" height="1024" rx="224" fill="{LIGHT}"/>
<defs><clipPath id="tile"><rect width="1024" height="1024" rx="224"/></clipPath></defs>
<g clip-path="url(#tile)"><g transform="translate({PORTRAIT_X} {PORTRAIT_Y}) scale({PORTRAIT_SCALE})">{body}</g></g></svg>'''
    rendered = Image.open(BytesIO(resvg_py.svg_to_bytes(svg_string=tile))).convert("RGBA")
    for density, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                          ("xxhdpi", 144), ("xxxhdpi", 192)]:
        rendered.resize((size, size), Image.Resampling.LANCZOS).save(
            RES / f"mipmap-{density}/ic_launcher.png")
    rendered.save(ROOT / "windows/runner/resources/app_icon.ico", format="ICO",
                  sizes=[(n, n) for n in (16, 20, 24, 32, 40, 48, 64, 128, 256)])
    rendered.save(ROOT / "assets/branding/pacta-icon.png")


if __name__ == "__main__":
    main()
