"""Generates the seamless PBR textures in assets/textures (albedo + normal map).

Run: python3 tools/gen_textures.py   (needs numpy and Pillow)
Everything here is original procedural art, so it's free to use with no license strings.
"""
import os
import numpy as np
from PIL import Image

N = 512
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
rng = np.random.default_rng(302)


def noise(scale, octaves=4, persistence=0.5, size=N):
    """Seamless fractal noise via FFT-filtered white noise. scale = feature size in pixels."""
    out = np.zeros((size, size))
    amp, total = 1.0, 0.0
    fx = np.fft.fftfreq(size)[:, None]
    fy = np.fft.fftfreq(size)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    for o in range(octaves):
        s = scale / (2 ** o)
        if s < 1:
            break
        white = rng.standard_normal((size, size))
        filt = np.exp(-(f * s) ** 2 * 6.0)
        layer = np.real(np.fft.ifft2(np.fft.fft2(white) * filt))
        layer = (layer - layer.mean()) / (layer.std() + 1e-9)
        out += layer * amp
        total += amp
        amp *= persistence
    out /= total
    return (out - out.min()) / (out.max() - out.min())


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = np.ones_like(h)
    n = np.stack([-dx, dy, nz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def save(name, rgb, height, strength):
    rgb = np.clip(rgb, 0, 1)
    Image.fromarray((rgb * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_albedo.png"), optimize=True)
    Image.fromarray(normal_from_height(height, strength)).save(os.path.join(OUT, name + "_normal.png"), optimize=True)
    print("wrote", name)


def colorize(t, c0, c1):
    c0, c1 = np.array(c0), np.array(c1)
    return c0 + (c1 - c0) * t[..., None]


def grid_coords(rows, cols, offset_rows=True):
    y, x = np.mgrid[0:N, 0:N].astype(float)
    row = np.floor(y / (N / rows))
    xs = x + (row % 2) * (N / cols / 2) * offset_rows
    col = np.floor((xs % N) / (N / cols))
    fy = (y % (N / rows)) / (N / rows)
    fx = (xs % (N / cols)) / (N / cols)
    return row, col, fx, fy


def per_cell_random(row, col, seed):
    r = np.random.default_rng(seed)
    table = r.random((256, 256))
    return table[row.astype(int) % 256, col.astype(int) % 256]


os.makedirs(OUT, exist_ok=True)

# Asphalt: dark, grainy, a few stains
fine = noise(2, 2)
mid = noise(40, 3)
speck = (rng.random((N, N)) > 0.985).astype(float)
t = 0.55 * fine + 0.35 * mid + 0.3 * speck
save("asphalt", colorize(t, (0.10, 0.10, 0.11), (0.30, 0.30, 0.31)), fine * 0.7 + speck * 0.5, 3.0)

# Concrete: light grey with slab joints (4 slabs across the tile)
n1 = noise(60, 4)
n2 = noise(3, 2)
y, x = np.mgrid[0:N, 0:N]
joint = ((x % (N // 4)) < 3) | ((y % (N // 4)) < 3)
t = 0.6 * n1 + 0.4 * n2
rgb = colorize(t, (0.52, 0.52, 0.5), (0.72, 0.71, 0.68))
rgb[joint] *= 0.6
h = n2 * 0.3 - joint * 1.0
save("concrete", rgb, h, 4.0)

# Grass
blades = noise(1.5, 2)
patches = noise(90, 3)
t = 0.5 * blades + 0.5 * patches
rgb = colorize(t, (0.16, 0.30, 0.10), (0.36, 0.52, 0.20))
rgb[..., 0] += (noise(150, 2) - 0.5) * 0.12
save("grass", rgb, blades, 4.0)

# Brick: 24 rows x 8 bricks, mortar lines, per-brick color
row, col, fx, fy = grid_coords(24, 8)
mortar = (fx < 0.04) | (fy < 0.12)
pc = per_cell_random(row, col, 7)
grain = noise(3, 2)
base = np.stack([0.50 + pc * 0.18, 0.22 + pc * 0.08, 0.16 + pc * 0.05], -1)
rgb = base * (0.85 + 0.3 * grain[..., None])
rgb[mortar] = np.array([0.62, 0.6, 0.56]) * (0.9 + 0.2 * grain[mortar][..., None])
h = np.where(mortar, 0.0, 1.0) + grain * 0.15
save("brick", rgb, h, 3.0)

# Siding: white lap boards (tinted per house in the engine)
y = np.mgrid[0:N, 0:N][0].astype(float)
board = (y % (N / 10)) / (N / 10)
wood = noise(8, 2) * 0.5 + noise(80, 2) * 0.5
shade = 0.75 + 0.25 * board
shade[board < 0.06] = 0.45
t = shade * (0.93 + 0.07 * wood)
save("siding", np.repeat(t[..., None], 3, -1) * 0.95, board + wood * 0.05, 5.0)

# Shingles: staggered tabs, grey (tinted)
row, col, fx, fy = grid_coords(12, 10)
pc = per_cell_random(row, col, 11)
grit = noise(1.5, 2)
t = (0.35 + 0.35 * pc) * (0.8 + 0.25 * fy) * (0.85 + 0.3 * grit)
gap = (fx < 0.03) | (fy > 0.95)
t[gap] *= 0.4
save("shingles", np.repeat(t[..., None], 3, -1), fy * 0.6 + grit * 0.2 - gap * 0.5, 4.0)

# Stucco: bright, subtle (tinted per building)
n = noise(4, 3) * 0.6 + noise(50, 3) * 0.4
t = 0.82 + 0.18 * n
save("stucco", np.repeat(t[..., None], 3, -1), n, 2.0)

# Floor tile: 4x4 tiles with grout
row, col, fx, fy = grid_coords(4, 4, offset_rows=False)
grout = (fx < 0.015) | (fy < 0.015)
pc = per_cell_random(row, col, 3)
n = noise(30, 3)
t = 0.82 + 0.06 * pc + 0.08 * n
t[grout] = 0.45
save("tile", np.repeat(t[..., None], 3, -1), np.where(grout, 0.0, 1.0), 3.0)

# Wood planks
row, col, fx, fy = grid_coords(8, 2)
pc = per_cell_random(row, col, 5)
y, x = np.mgrid[0:N, 0:N].astype(float)
streak = noise(6, 2)
streak = np.roll(streak, 0)
grain = (np.sin(x / 9.0 + streak * 6.0) * 0.5 + 0.5)
t = 0.55 + 0.25 * pc + 0.15 * grain
gap = fy < 0.04
rgb = colorize(t, (0.30, 0.18, 0.09), (0.65, 0.45, 0.26))
rgb[gap] *= 0.4
save("wood", rgb, grain * 0.3 - gap * 1.0, 3.0)

# Gravel roof (flat commercial roofs)
n = noise(1.2, 2) * 0.7 + noise(20, 2) * 0.3
save("gravel", colorize(n, (0.30, 0.30, 0.30), (0.55, 0.54, 0.52)), n, 4.0)

# Leaves (tinted per tree)
clumps = noise(6, 3)
cells = noise(2, 1)
t = np.clip(clumps * 1.2 - 0.1, 0, 1) * 0.7 + cells * 0.3
save("leaves", np.repeat((0.35 + 0.65 * t)[..., None], 3, -1), clumps, 6.0)

# Bark
y, x = np.mgrid[0:N, 0:N].astype(float)
ridges = noise(10, 3)
ridges = np.sin(x / N * 2 * np.pi * 12 + ridges * 8.0) * 0.5 + 0.5
save("bark", colorize(ridges * 0.7 + noise(3, 2) * 0.3, (0.18, 0.12, 0.08), (0.42, 0.32, 0.22)), ridges, 5.0)
