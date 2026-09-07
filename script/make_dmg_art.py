from pathlib import Path
import subprocess

import numpy as np
from PIL import Image

out = Path(".build/dmg-art")
out.mkdir(parents=True, exist_ok=True)
width, height = 1600, 880
x, y = np.meshgrid(np.linspace(0, 1, width), np.linspace(0, 1, height))
art = np.ones((height, width, 3)) * 255

# Keep Soiawork's restrained aurora language in Seal Note's blush-pink palette.
for color, center, ribbon_width, strength in [
    ((240, 190, 207), 0.02 + 0.12 * np.sin(x * 6.8), 0.13, 0.50),
    ((250, 222, 232), 0.13 + 0.15 * np.cos(x * 5 + 1), 0.17, 0.82),
    ((255, 239, 245), 0.90 + 0.10 * np.sin(x * 7), 0.20, 0.82),
]:
    blend = np.exp(-((y - center) / ribbon_width) ** 2) * strength
    art = art * (1 - blend[..., None]) + np.array(color) * blend[..., None]

image = Image.fromarray(np.uint8(np.clip(art, 0, 255))).convert("RGB")
image.save(out / "background.png")
subprocess.run(["swift", "script/render_dmg_text.swift", str(out)], check=True)
image = Image.open(out / "background.png").resize(
    (1600, 880), Image.Resampling.LANCZOS
)
image.save(out / "background.png")
image.resize((800, 440), Image.Resampling.LANCZOS).save(out / "background-1x.png")
print(out)
