# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""
Faithful port of Ly's src/animations/ColorMix.zig to a PNG renderer.

Ly draws this into a TTY cell grid, and both sources of its look come from that:

  * cell resolution -- one plasma sample per character cell, not per pixel
  * a 12-entry palette of four block glyphs (U+2588/2593/2592/2591 = 100/75/50/25%
    foreground coverage) across three colour pairs (c1/c2, c2/c3, c3/c1)

So each cell resolves to exactly one of 12 flat colours. That quantisation is the
"pixelated lava" banding -- a smooth per-pixel gradient does NOT look like this.

Colours default to /etc/ly/config.ini's colormix_col1/2/3. Note col3 there is
0x20000000, which is termbox's TB_HI_BLACK attribute bit over #000000, i.e. true
black -- not a 12.5%-alpha black.
"""

import argparse
import math

import numpy as np
from PIL import Image

# U+2588 full, U+2593 dark, U+2592 medium, U+2591 light shade.
# Ordered exactly as ColorMix.zig lists them within each colour pair.
GLYPH_COVERAGE = (1.00, 0.75, 0.50, 0.25)
TIME_SCALE = 0.01  # ColorMix.zig:17


def hex_rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i : i + 2], 16) for i in (0, 2, 4))


def build_palette(c1, c2, c3):
    """12 flat RGB colours: glyph coverage blended over each (fg, bg) pair."""
    out = []
    for fg, bg in ((c1, c2), (c2, c3), (c3, c1)):
        for cov in GLYPH_COVERAGE:
            out.append([fg[i] * cov + bg[i] * (1.0 - cov) for i in range(3)])
    return np.array(out, dtype=np.float64)


def render(cols, rows, frames, cos_mod, sin_mod, palette, pattern_rows=None):
    """Vectorised transcription of ColorMix.zig:87-119.

    pattern_rows decouples the pattern's spatial scale from the canvas size. Ly
    normalises uv by its own grid height, so rendering a 2x canvas the naive way
    would show the same composition at 2x magnification -- bigger blobs, wrong
    look. Pinning pattern_rows to the on-screen grid height instead keeps every
    feature at Ly's true size and simply reveals *more* of the pattern, which is
    what a pannable oversized texture needs.
    """
    time = frames * TIME_SCALE
    ref = pattern_rows or rows

    x = np.arange(cols, dtype=np.float64)[None, :]
    y = np.arange(rows, dtype=np.float64)[:, None]

    # uv.x divides by (height*2) but uv.y by height -- that asymmetry is what
    # compensates for the 1:2 aspect of a terminal cell. Keep it.
    uvx = np.broadcast_to((x * 2 - cols) / (ref * 2), (rows, cols)).copy()
    uvy = np.broadcast_to((y * 2 - rows) / ref, (rows, cols)).copy()

    # uv2 starts as a splat of (uv.x + uv.y) into BOTH components.
    uv2x = uvx + uvy
    uv2y = uv2x.copy()

    for _ in range(3):
        length = np.sqrt(uvx * uvx + uvy * uvy)
        # uv2 updates from the PRE-update uv ...
        uv2x += uvx + length
        uv2y += uvy + length
        # ... and uv then updates from the POST-update uv2. Order matters.
        nx = uvx + 0.5 * np.cos(cos_mod + uv2y * 0.2 + time * 0.1)
        ny = uvy + 0.5 * np.sin(sin_mod + uv2x - time * 0.1)
        uvx, uvy = nx, ny
        # Scalar splat subtracted from both components, using the new uv.
        s = 1.0 * np.cos(uvx + uvy) - np.sin(uvx * 0.7 - uvy)
        uvx -= s
        uvy -= s

    idx = np.floor(np.sqrt(uvx * uvx + uvy * uvy) * 5.0).astype(np.int64) % len(palette)
    return palette[idx]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--width", type=int, default=2400)
    p.add_argument("--height", type=int, default=1600)
    p.add_argument("--cell-w", type=int, default=8, help="TTY font cell width")
    p.add_argument("--cell-h", type=int, default=16, help="TTY font cell height")
    p.add_argument("--col1", default="3B6BFF")
    p.add_argument("--col2", default="102A66")
    p.add_argument("--col3", default="000000")
    p.add_argument("--frames", type=float, default=0.0)
    p.add_argument(
        "--pattern-rows",
        type=int,
        default=None,
        help="grid rows to scale the pattern by (default: the canvas rows). Set "
        "to the ON-SCREEN row count when rendering an oversized pan texture.",
    )
    # Ly randomises these per launch (ColorMix.zig:52-53). Fixed here so a render
    # is reproducible; change --seed to reroll the composition.
    p.add_argument("--seed", type=int, default=7)
    args = p.parse_args()

    cols = args.width // args.cell_w
    rows = args.height // args.cell_h

    rng = np.random.default_rng(args.seed)
    cos_mod = float(rng.random() * math.pi * 2.0)
    sin_mod = float(rng.random() * math.pi * 2.0)

    palette = build_palette(
        hex_rgb(args.col1), hex_rgb(args.col2), hex_rgb(args.col3)
    )
    cells = render(
        cols, rows, args.frames, cos_mod, sin_mod, palette, args.pattern_rows
    )

    # Nearest-neighbour block upscale -- np.repeat, never a resampling filter.
    # Any smoothing here destroys the exact thing we are reproducing.
    img = np.repeat(np.repeat(cells, args.cell_h, axis=0), args.cell_w, axis=1)
    img = np.clip(np.rint(img), 0, 255).astype(np.uint8)

    Image.fromarray(img, "RGB").save(args.out)
    print(f"{args.out}  {img.shape[1]}x{img.shape[0]}  grid {cols}x{rows}")


if __name__ == "__main__":
    main()
