#!/usr/bin/env python3
"""Generate the Quiet Cast iOS app icon (1024x1024).

Cold Ember: canvas #0d0e10, ink #d9d5c8, ember #b08a5e (single warm accent).
Mark: a large Cormorant Garamond Q in ink — the masthead letterform — with a
small ember point glowing in its counter: the quiet signal source.
"""
import random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
CANVAS = (0x0D, 0x0E, 0x10)
EMBER = (0xB0, 0x8A, 0x5E)
INK = (0xD9, 0xD5, 0xC8)
FONT = "/Users/roblark/Projects/quietcast/front-end-astro/ios/QuietCast/Resources/Fonts/CormorantGaramond-Medium.ttf"

img = Image.new("RGB", (S, S), CANVAS)

# Subtle vertical lift toward the top so the canvas isn't dead flat.
top = Image.new("L", (1, S))
for y in range(S):
    top.putpixel((0, y), int(16 * (1 - y / S)))
lift = top.resize((S, S))
img = Image.composite(Image.new("RGB", (S, S), (0x15, 0x16, 0x19)), img, lift)
img = img.convert("RGBA")

# The Q, optically centered (tail hangs low, so nudge up slightly).
font = ImageFont.truetype(FONT, 760)
qx, qy = S // 2, int(S * 0.46)
text_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
td = ImageDraw.Draw(text_layer)
td.text((qx, qy), "Q", font=font, fill=INK + (255,), anchor="mm")
img = Image.alpha_composite(img, text_layer)

# Ember point in the Q's counter, with a soft glow.
bbox = td.textbbox((qx, qy), "Q", font=font, anchor="mm")
ccx = (bbox[0] + bbox[2]) // 2
ccy = (bbox[1] + bbox[3]) // 2 - 40  # counter sits above the tail
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([ccx - 120, ccy - 120, ccx + 120, ccy + 120], fill=EMBER + (60,))
glow = glow.filter(ImageFilter.GaussianBlur(70))
img = Image.alpha_composite(img, glow)
draw = ImageDraw.Draw(img, "RGBA")
r = 34
draw.ellipse([ccx - r, ccy - r, ccx + r, ccy + r], fill=EMBER + (255,))

# Grain: low-alpha monochrome noise, like the web canvas.
rng = random.Random(7)
grain = Image.new("L", (S, S))
grain.putdata([rng.randint(0, 255) for _ in range(S * S)])
grain_rgba = Image.merge("RGBA", (grain, grain, grain, grain.point(lambda v: 9)))
img = Image.alpha_composite(img, grain_rgba)

out = img.convert("RGB")
out.save("/Users/roblark/Projects/quietcast/front-end-astro/ios/QuietCast/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png")
print("icon written")
