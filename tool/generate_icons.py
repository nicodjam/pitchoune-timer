"""Generates the Pitchoune Timer launcher icons (a friendly stopwatch).

Usage (from the project root):
    pip install pillow playwright && playwright install chromium
    python3 tool/generate_icons.py

Edit the SVG drawing in art() and background(), then run the script again:
it rewrites assets/icon/ and every Android and iOS launcher icon.
"""

import math

INK = "#2B2350"

def art():
    # Everything is drawn in a 1024x1024 box, centered around (512, 580).
    # A friendly stopwatch: two big round eyes, a wide smile and pink cheeks.
    ticks = "".join(
        f'<circle cx="{512 + 170*math.sin(i*math.pi/6):.1f}" cy="{600 - 170*math.cos(i*math.pi/6):.1f}" '
        f'r="11" fill="{INK}" fill-opacity="0.25"/>'
        for i in range(12)
    )
    eye = lambda x: f"""
    <circle cx="{x}" cy="575" r="48" fill="#FFFFFF" stroke="{INK}" stroke-width="14"/>
    <circle cx="{x + 6}" cy="580" r="27" fill="{INK}"/>
    <circle cx="{x + 16}" cy="568" r="9" fill="#FFFFFF"/>"""
    return f"""
  <!-- top crown of the stopwatch -->
  <rect x="487" y="318" width="50" height="40" rx="8" fill="#FFA62B" stroke="{INK}" stroke-width="20"/>
  <rect x="452" y="282" width="120" height="46" rx="16" fill="#FFA62B" stroke="{INK}" stroke-width="20"/>
  <!-- side buttons of the stopwatch -->
  <g transform="rotate(62 512 600)">
    <rect x="477" y="306" width="70" height="70" rx="14" fill="#FFA62B" stroke="{INK}" stroke-width="20"/>
  </g>
  <g transform="rotate(-62 512 600)">
    <rect x="477" y="306" width="70" height="70" rx="14" fill="#FFA62B" stroke="{INK}" stroke-width="20"/>
  </g>
  <!-- stopwatch body -->
  <circle cx="512" cy="600" r="250" fill="#FFA62B" stroke="{INK}" stroke-width="24"/>
  <circle cx="512" cy="600" r="200" fill="#FFFFFF"/>
  {ticks}
  <!-- cheeks -->
  <circle cx="395" cy="655" r="34" fill="#FF7EB3" fill-opacity="0.5"/>
  <circle cx="629" cy="655" r="34" fill="#FF7EB3" fill-opacity="0.5"/>
  <!-- eyebrows, raised: a happy look -->
  <path d="M 395 505 Q 432 488 468 503" fill="none" stroke="{INK}" stroke-width="13" stroke-linecap="round"/>
  <path d="M 556 503 Q 592 488 629 505" fill="none" stroke="{INK}" stroke-width="13" stroke-linecap="round"/>
  {eye(432)}
  {eye(592)}
  <!-- wide smile with a tongue -->
  <path d="M 440 665 Q 512 760 584 665 Q 512 690 440 665 Z" fill="{INK}"/>
  <path d="M 478 705 Q 512 690 546 705 Q 530 732 512 733 Q 494 732 478 705 Z" fill="#FF7E9A"/>
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
    t = f"translate({512 - 512*scale:.1f} {512 - 580*scale:.1f}) scale({scale})"
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
    full_svg, fg_svg = svg(True, 1.25), svg(False, 1.0)
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
