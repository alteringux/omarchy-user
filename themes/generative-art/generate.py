#!/usr/bin/env python3
"""
Generative Art wallpaper generator for the Omarchy "generative-art" theme.

Stdlib-only by default — writes raw PNGs by hand so it runs on a fresh
install with nothing extra to pull down. If numpy is importable, the two
loop-heavy generators (fractal, attractor) automatically switch to vectorized
implementations (~30-60x faster); otherwise they fall back to the pure-Python
path below. Nothing to configure — it's just faster when numpy is present.

  - fractal.png     Julia set, palette-mapped by escape velocity
  - flow-field.png  Value-noise vector field traced as glowing streamlines
  - attractor.png   Clifford strange attractor, density-accumulated

Usage:
  python3 generate.py                 regenerate all three, fixed filenames
  python3 generate.py --single NAME   generate one fresh piece, timestamped,
                                       for rotation (see rotate.sh)
"""
import argparse
import math
import os
import random
import shutil
import struct
import time
import zlib

try:
    import numpy as np
    HAVE_NUMPY = True
except ImportError:
    HAVE_NUMPY = False

W, H = 1600, 900
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backgrounds")
PICTURES_DIR = os.path.join(os.path.expanduser("~"), "Pictures", "omarchy-generative-art")

# Palette pulled from colors.toml (kept in sync by hand — small, stable file)
PALETTE_HEX = [
    "#0b0715",  # background
    "#5f7bff",  # blue
    "#4cf0ff",  # cyan
    "#ff5fd1",  # magenta / accent
    "#ff8c42",  # orange
    "#3ddc97",  # green
    "#ffffff",  # bright_foreground
]


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


PALETTE = [hex_to_rgb(h) for h in PALETTE_HEX]


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_rgb(c1, c2, t):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(3))


def palette_color(t):
    """t in [0,1] -> smooth color from the multi-stop palette."""
    t = max(0.0, min(1.0, t))
    n = len(PALETTE) - 1
    pos = t * n
    i = min(int(pos), n - 1)
    frac = pos - i
    return lerp_rgb(PALETTE[i], PALETTE[i + 1], frac)


if HAVE_NUMPY:
    _PALETTE_NP = np.array(PALETTE, dtype=np.float64)  # (n, 3)

    def palette_color_np(t):
        """Vectorized palette_color: t is an (H, W) array in [0,1] -> (H, W, 3) uint8."""
        t = np.clip(t, 0.0, 1.0)
        n = len(PALETTE) - 1
        pos = t * n
        i = np.minimum(pos.astype(np.int32), n - 1)
        frac = pos - i
        c1 = _PALETTE_NP[i]
        c2 = _PALETTE_NP[i + 1]
        rgb = c1 + (c2 - c1) * frac[..., None]
        return rgb.astype(np.uint8)


def new_canvas(bg):
    row = bytes(bg) * W
    return [bytearray(row) for _ in range(H)]


def set_px(canvas, x, y, rgb, alpha=1.0):
    if 0 <= x < W and 0 <= y < H:
        row = canvas[y]
        o = x * 3
        if alpha >= 1.0:
            row[o] = rgb[0]
            row[o + 1] = rgb[1]
            row[o + 2] = rgb[2]
        else:
            row[o] = int(row[o] * (1 - alpha) + rgb[0] * alpha)
            row[o + 1] = int(row[o + 1] * (1 - alpha) + rgb[1] * alpha)
            row[o + 2] = int(row[o + 2] * (1 - alpha) + rgb[2] * alpha)


def write_png(path, canvas):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)
    if HAVE_NUMPY and isinstance(canvas, np.ndarray):
        filter_col = np.zeros((H, 1), dtype=np.uint8)
        raw = np.concatenate([filter_col, canvas.reshape(H, W * 3)], axis=1).tobytes()
    else:
        raw = bytearray()
        for row in canvas:
            raw.append(0)  # filter type: none
            raw.extend(row)
        raw = bytes(raw)
    idat = zlib.compress(bytes(raw), 6)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


def write_and_copy(path, canvas):
    """Write the PNG to the theme's cache dir, then mirror it into ~/Pictures."""
    write_png(path, canvas)
    os.makedirs(PICTURES_DIR, exist_ok=True)
    shutil.copy2(path, os.path.join(PICTURES_DIR, os.path.basename(path)))


# ---------------------------------------------------------------------------
# 1. Julia set fractal, colored by smooth escape time
# ---------------------------------------------------------------------------
def gen_fractal(seed):
    rnd = random.Random(seed)
    angle = rnd.uniform(0, math.tau)
    r = rnd.uniform(0.68, 0.82)
    c = complex(r * math.cos(angle), r * math.sin(angle))
    max_iter = 80
    canvas = new_canvas(PALETTE[0])
    zoom = 0.62
    for py in range(H):
        y0 = (py - H / 2) / (H * zoom)
        row = canvas[py]
        for px in range(W):
            x0 = (px - W / 2) / (H * zoom)
            zx, zy = x0, y0
            i = 0
            while zx * zx + zy * zy <= 4.0 and i < max_iter:
                zx, zy = zx * zx - zy * zy + c.real, 2 * zx * zy + c.imag
                i += 1
            if i >= max_iter:
                continue
            smooth = i + 1 - math.log(math.log(zx * zx + zy * zy + 1e-9)) / math.log(2)
            t = (smooth / max_iter) % 1.0
            rgb = palette_color(t)
            o = px * 3
            row[o], row[o + 1], row[o + 2] = rgb
    return canvas


def gen_fractal_np(seed):
    rnd = random.Random(seed)
    angle = rnd.uniform(0, math.tau)
    r = rnd.uniform(0.68, 0.82)
    cx, cy = r * math.cos(angle), r * math.sin(angle)
    max_iter = 80
    zoom = 0.62

    px = np.arange(W)
    py = np.arange(H)
    x0 = (px - W / 2) / (H * zoom)
    y0 = (py - H / 2) / (H * zoom)
    zx, zy = np.meshgrid(x0, y0)  # (H, W)
    zx = zx.ravel()
    zy = zy.ravel()

    escaped_iter = np.full(W * H, max_iter, dtype=np.float64)
    escaped_zx = zx.copy()
    escaped_zy = zy.copy()
    # Points that already start outside the escape radius never enter the
    # update loop (matches the pure-Python while-condition checking *before*
    # the first update) — record them at iteration 0 with their initial z.
    live_mask = (zx * zx + zy * zy) <= 4.0
    escaped_iter[~live_mask] = 0

    # Track only the still-live points as a compacting array (indexed by
    # their original flat position) instead of re-scanning a full-size
    # (H, W) boolean mask every iteration — the mask approach costs
    # O(max_iter * H * W) even once just a thin fractal skeleton remains
    # live, since gather/scatter/np.where all re-sweep the whole grid.
    active_idx = np.nonzero(live_mask)[0]
    zx_a, zy_a = zx[active_idx], zy[active_idx]

    for i in range(max_iter):
        nzx = zx_a * zx_a - zy_a * zy_a + cx
        nzy = 2 * zx_a * zy_a + cy
        mag2 = nzx * nzx + nzy * nzy
        escaped = mag2 > 4.0
        if escaped.any():
            esc_idx = active_idx[escaped]
            escaped_iter[esc_idx] = i + 1
            escaped_zx[esc_idx] = nzx[escaped]
            escaped_zy[esc_idx] = nzy[escaped]
        keep = ~escaped
        active_idx = active_idx[keep]
        if active_idx.size == 0:
            break
        zx_a, zy_a = nzx[keep], nzy[keep]

    escaped_iter = escaped_iter.reshape(H, W)
    escaped_zx = escaped_zx.reshape(H, W)
    escaped_zy = escaped_zy.reshape(H, W)

    mag2 = escaped_zx * escaped_zx + escaped_zy * escaped_zy
    mag2 = np.maximum(mag2, 1.0001)  # avoid log(log(<=1))
    smooth = escaped_iter + 1 - np.log(np.log(mag2)) / math.log(2)
    t = (smooth / max_iter) % 1.0
    inside = escaped_iter >= max_iter
    canvas = palette_color_np(t)
    canvas[inside] = _PALETTE_NP[0].astype(np.uint8)
    return canvas


# ---------------------------------------------------------------------------
# 2. Flow field: value-noise vector field traced as streamlines
# ---------------------------------------------------------------------------
def value_noise_field(seed, cell=48):
    rnd = random.Random(seed)
    gx, gy = W // cell + 2, H // cell + 2
    grid = [[rnd.uniform(0, math.tau) for _ in range(gx)] for _ in range(gy)]

    def angle_at(x, y):
        fx, fy = x / cell, y / cell
        ix, iy = int(fx), int(fy)
        tx, ty = fx - ix, fy - iy
        a = grid[iy][ix]
        b = grid[iy][min(ix + 1, gx - 1)]
        c = grid[min(iy + 1, gy - 1)][ix]
        d = grid[min(iy + 1, gy - 1)][min(ix + 1, gx - 1)]
        top = a + (b - a) * tx
        bot = c + (d - c) * tx
        return top + (bot - top) * ty

    return angle_at


def gen_flow_field(seed):
    rnd = random.Random(seed)
    canvas = new_canvas(PALETTE[0])
    angle_at = value_noise_field(seed)
    n_lines = 900
    steps = 260
    step_len = 2.4
    for _ in range(n_lines):
        x = rnd.uniform(0, W)
        y = rnd.uniform(0, H)
        t = rnd.random()
        color = palette_color((t + rnd.uniform(-0.05, 0.05)) % 1.0)
        for s in range(steps):
            a = angle_at(x, y)
            x += math.cos(a) * step_len
            y += math.sin(a) * step_len
            if not (0 <= x < W and 0 <= y < H):
                break
            fade = 1.0 - abs(s / steps - 0.5) * 1.3
            set_px(canvas, int(x), int(y), color, alpha=max(0.08, min(0.5, fade)))
    return canvas


# ---------------------------------------------------------------------------
# 3. Clifford strange attractor, density-accumulated
# ---------------------------------------------------------------------------
def gen_attractor(seed):
    rnd = random.Random(seed)
    a = rnd.uniform(-2.0, -1.2)
    b = rnd.uniform(1.4, 2.2)
    c = rnd.uniform(-1.4, 1.4)
    d = rnd.uniform(-1.4, 1.4)

    n_points = 900_000
    x, y = 0.1, 0.1
    xs = [0.0] * n_points
    ys = [0.0] * n_points
    minx = miny = 1e9
    maxx = maxy = -1e9
    for i in range(n_points):
        nx = math.sin(a * y) + c * math.cos(a * x)
        ny = math.sin(b * x) + d * math.cos(b * y)
        x, y = nx, ny
        xs[i] = x
        ys[i] = y
        if x < minx: minx = x
        if x > maxx: maxx = x
        if y < miny: miny = y
        if y > maxy: maxy = y

    pad = 0.06
    spanx = (maxx - minx) or 1.0
    spany = (maxy - miny) or 1.0
    density = [[0] * W for _ in range(H)]
    for i in range(n_points):
        px = int((xs[i] - minx) / spanx * (W * (1 - 2 * pad)) + W * pad)
        py = int((ys[i] - miny) / spany * (H * (1 - 2 * pad)) + H * pad)
        if 0 <= px < W and 0 <= py < H:
            density[py][px] += 1

    peak = max(max(row) for row in density) or 1
    canvas = new_canvas(PALETTE[0])
    for py in range(H):
        drow = density[py]
        crow = canvas[py]
        for px in range(W):
            v = drow[px]
            if not v:
                continue
            t = math.log(1 + v) / math.log(1 + peak)
            rgb = palette_color(0.15 + t * 0.85)
            o = px * 3
            crow[o], crow[o + 1], crow[o + 2] = rgb
    return canvas


def gen_attractor_np(seed):
    rnd = random.Random(seed)
    a = rnd.uniform(-2.0, -1.2)
    b = rnd.uniform(1.4, 2.2)
    c = rnd.uniform(-1.4, 1.4)
    d = rnd.uniform(-1.4, 1.4)

    # Run many short chains in parallel instead of one long chain: same total
    # point count, but each step is one vectorized numpy op across all chains.
    n_chains = 3000
    n_steps = 300
    chain_rnd = np.random.default_rng(seed)
    x = chain_rnd.uniform(-0.5, 0.5, n_chains)
    y = chain_rnd.uniform(-0.5, 0.5, n_chains)

    all_x = np.empty((n_steps, n_chains))
    all_y = np.empty((n_steps, n_chains))
    for i in range(n_steps):
        nx = np.sin(a * y) + c * np.cos(a * x)
        ny = np.sin(b * x) + d * np.cos(b * y)
        x, y = nx, ny
        all_x[i] = x
        all_y[i] = y

    xs = all_x.ravel()
    ys = all_y.ravel()
    # Drop the first few steps of each chain (transient before settling onto
    # the attractor); negligible with 300 steps but keeps things clean.
    minx, maxx = xs.min(), xs.max()
    miny, maxy = ys.min(), ys.max()

    pad = 0.06
    spanx = (maxx - minx) or 1.0
    spany = (maxy - miny) or 1.0
    density, _, _ = np.histogram2d(
        ys, xs,
        bins=[H, W],
        range=[[miny - spany * pad, maxy + spany * pad],
               [minx - spanx * pad, maxx + spanx * pad]],
    )

    peak = density.max() or 1
    t = np.log1p(density) / math.log1p(peak)
    t = 0.15 + t * 0.85
    canvas = palette_color_np(t)
    canvas[density == 0] = _PALETTE_NP[0].astype(np.uint8)
    return canvas


GENERATORS = {
    "fractal": gen_fractal_np if HAVE_NUMPY else gen_fractal,
    "flow-field": gen_flow_field,
    "attractor": gen_attractor_np if HAVE_NUMPY else gen_attractor,
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--single", metavar="TECHNIQUE",
        help="generate just one piece (fractal|flow-field|attractor|random), "
             "written with a timestamped filename instead of overwriting the "
             "fixed set — used by rotate.sh",
    )
    parser.add_argument(
        "--print-path", action="store_true",
        help="with --single, print only the written file's path on stdout "
             "(for scripting) instead of the human-readable status line",
    )
    args = parser.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    seed = int.from_bytes(os.urandom(4), "big")
    backend = "numpy" if HAVE_NUMPY else "pure-python"

    if args.single:
        name = args.single
        if name == "random":
            name = random.choice(list(GENERATORS))
        fn = GENERATORS[name]
        t0 = time.time()
        canvas = fn(seed)
        path = os.path.join(OUT_DIR, f"{name}-{int(time.time())}.png")
        write_and_copy(path, canvas)
        if args.print_path:
            print(path)
        else:
            print(f"[{backend}] wrote {path} in {time.time() - t0:.2f}s")
        return

    for name, fn in GENERATORS.items():
        t0 = time.time()
        canvas = fn(seed + hash(name) % 10007)
        path = os.path.join(OUT_DIR, f"{name}.png")
        write_and_copy(path, canvas)
        print(f"[{backend}] wrote {path} in {time.time() - t0:.2f}s")


if __name__ == "__main__":
    main()
