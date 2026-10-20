"""Generates the Pitchoune Timer launcher icons (a pirate stopwatch).

Usage (from the project root):
    pip install pillow playwright && playwright install chromium
    python3 tool/generate_icons.py

Edit the SVG drawing in art() and background(), then run the script again:
it rewrites assets/icon/ and every Android and iOS launcher icon.
"""

INK = "#2B2350"

def art():
    # Everything is drawn in a 1024x1024 box, centered around (512, 530).
    return f"""
  <!-- side button of the stopwatch -->
  <g transform="rotate(62 512 600)">
    <rect x="477" y="306" width="70" height="70" rx="14" fill="#FFA62B" stroke="{INK}" stroke-width="20"/>
  </g>
  <g transform="rotate(-62 512 600)">
    <rect x="477" y="306" width="70" height="70" rx="14" fill="#FFA62B" stroke="{INK}" stroke-width="20"/>
  </g>
  <!-- stopwatch body -->
  <circle cx="512" cy="600" r="250" fill="#FFA62B" stroke="{INK}" stroke-width="24"/>
  <circle cx="512" cy="600" r="200" fill="#FFFFFF"/>
  <!-- dial ticks -->
  {''.join(f'<circle cx="{512 + 170*__import__("math").sin(i*3.14159/6):.1f}" cy="{600 - 170*__import__("math").cos(i*3.14159/6):.1f}" r="11" fill="{INK}" fill-opacity="0.3"/>' for i in range(12))}
  <!-- face, clipped to the dial -->
  <clipPath id="dial"><circle cx="512" cy="600" r="200"/></clipPath>
  <g clip-path="url(#dial)">
    <!-- eye patch strap -->
    <path d="M 300 470 L 740 655" stroke="{INK}" stroke-width="18" stroke-linecap="round"/>
  </g>
  <!-- cheeks -->
  <circle cx="400" cy="660" r="30" fill="#FF7EB3" fill-opacity="0.45"/>
  <circle cx="630" cy="670" r="30" fill="#FF7EB3" fill-opacity="0.45"/>
  <!-- open eye -->
  <circle cx="430" cy="565" r="46" fill="#FFFFFF" stroke="{INK}" stroke-width="14"/>
  <circle cx="440" cy="558" r="22" fill="{INK}"/>
  <circle cx="447" cy="550" r="7" fill="#FFFFFF"/>
  <!-- eye patch -->
  <ellipse cx="590" cy="585" rx="56" ry="46" fill="{INK}" transform="rotate(22 590 585)"/>
  <!-- grin with a gold tooth -->
  <path d="M 432 668 Q 515 770 604 668 Q 515 700 432 668 Z" fill="{INK}"/>
  <rect x="528" y="684" width="24" height="22" rx="4" fill="#FFC94D"/>
  <!-- tricorn hat -->
  <path d="M 222 415 C 290 250 420 195 512 212 C 604 195 734 250 802 415
           C 706 372 606 362 512 372 C 418 362 318 372 222 415 Z" fill="{INK}"/>
  <path d="M 222 415 C 318 372 418 362 512 372 C 606 362 706 372 802 415"
        fill="none" stroke="#FFC94D" stroke-width="18" stroke-linecap="round"/>
  <!-- skull and crossbones -->
  <g fill="#FFFFFF">
    <g transform="rotate(35 512 300)">
      <rect x="452" y="290" width="120" height="20" rx="10"/>
      <circle cx="452" cy="292" r="12"/><circle cx="452" cy="308" r="12"/>
      <circle cx="572" cy="292" r="12"/><circle cx="572" cy="308" r="12"/>
    </g>
    <g transform="rotate(-35 512 300)">
      <rect x="452" y="290" width="120" height="20" rx="10"/>
      <circle cx="452" cy="292" r="12"/><circle cx="452" cy="308" r="12"/>
      <circle cx="572" cy="292" r="12"/><circle cx="572" cy="308" r="12"/>
    </g>
    <circle cx="512" cy="282" r="36"/>
    <rect x="490" y="296" width="44" height="26" rx="8"/>
  </g>
  <circle cx="499" cy="280" r="9" fill="{INK}"/>
  <circle cx="525" cy="280" r="9" fill="{INK}"/>
"""

def background():
    return """
  <defs>
    <radialGradient id="bg" cx="50%" cy="40%" r="75%">
      <stop offset="0" stop-color="#8D72FF"/>
      <stop offset="1" stop-color="#4E30D6"/>
    </radialGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <circle cx="150" cy="830" r="70" fill="#FFFFFF" fill-opacity="0.10"/>
  <circle cx="880" cy="170" r="50" fill="#FFFFFF" fill-opacity="0.10"/>
  <circle cx="870" cy="880" r="34" fill="#FFFFFF" fill-opacity="0.10"/>
  <circle cx="170" cy="190" r="26" fill="#FFFFFF" fill-opacity="0.10"/>
"""

def svg(with_background: bool, scale: float) -> str:
    bg = background() if with_background else ""
    t = f"translate({512 - 512*scale:.1f} {512 - 530*scale:.1f}) scale({scale})"
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{bg}<g transform="{t}">{art()}</g></svg>'


# ---------------------------------------------------------------------------
# Rendering (headless Chromium through Playwright) and platform icon export
# ---------------------------------------------------------------------------

import asyncio
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "assets", "icon")


async def _render(pairs):
    from playwright.async_api import async_playwright
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={"width": 1024, "height": 1024})
        for svg_text, png_path, transparent in pairs:
            await page.set_content(f"<html><body style='margin:0;background:transparent'>{svg_text}</body></html>")
            await page.locator("svg").screenshot(path=png_path, omit_background=transparent)
        await browser.close()


def main():
    full_svg, fg_svg = svg(True, 0.92), svg(False, 0.72)
    open(os.path.join(ICON_DIR, "icon.svg"), "w").write(full_svg)
    open(os.path.join(ICON_DIR, "icon_foreground.svg"), "w").write(fg_svg)
    full_png = os.path.join(ICON_DIR, "icon.png")
    fg_png = os.path.join(ICON_DIR, "icon_foreground.png")
    asyncio.run(_render([(full_svg, full_png, False), (fg_svg, fg_png, True)]))

    full = Image.open(full_png).convert("RGB")
    fg = Image.open(fg_png).convert("RGBA")

    # Android: legacy icon (48 dp) + adaptive foreground (108 dp) per density
    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        full.resize((size, size), Image.LANCZOS).save(f"{res}/mipmap-{density}/ic_launcher.png", optimize=True)
        fg_size = size * 108 // 48
        fg.resize((fg_size, fg_size), Image.LANCZOS).save(f"{res}/mipmap-{density}/ic_launcher_foreground.png", optimize=True)

    # iOS: every size listed in Contents.json, RGB only (Apple rejects alpha)
    ios = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for img in json.load(open(os.path.join(ios, "Contents.json")))["images"]:
        px = round(float(img["size"].split("x")[0]) * int(img["scale"][0]))
        full.resize((px, px), Image.LANCZOS).save(os.path.join(ios, img["filename"]), optimize=True)
    print("Icons generated.")


if __name__ == "__main__":
    main()
