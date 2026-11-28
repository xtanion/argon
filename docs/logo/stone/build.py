import math, os, random, runpy, sys
HERE = os.path.dirname(os.path.abspath(__file__))
g = runpy.run_path(os.path.join(HERE, "..", "loop-a-pro", "build.py"))
OUT = HERE
random.seed(int(os.environ.get("SEED", "7")))

CX, CY, RX, RY = 512.0, 515.0, 335.0, 305.0
RINGS = [(0.0, 1), (0.42, 6), (0.78, 10), (1.0, 14)]
LIGHT = (-0.45, -0.65, 0.62)
ln = math.sqrt(sum(v * v for v in LIGHT))
LIGHT = tuple(v / ln for v in LIGHT)

def blob(a):
    return 1 + 0.06 * math.sin(3 * a + 0.7) + 0.035 * math.sin(5 * a + 2.1)

rings = []
for k, (t, n) in enumerate(RINGS):
    off = random.random() * 2 * math.pi
    pts = []
    for i in range(n):
        a = off + 2 * math.pi * i / n + (random.uniform(-0.18, 0.18) * 2 * math.pi / n if t > 0 else 0)
        rr = t * blob(a) * (1 + (random.uniform(-0.05, 0.05) if 0 < t < 1 else 0))
        x, y = CX + RX * rr * math.cos(a), CY + RY * rr * math.sin(a)
        d = min(rr, 1)
        z = 300 * math.sqrt(max(0.0, 1 - d ** 2.2)) + (random.uniform(-14, 14) if t < 1 else 0)
        pts.append((x, y, z, a % (2 * math.pi)))
    pts.sort(key=lambda p: p[3])
    rings.append(pts)

tris = []
for k in range(len(rings) - 1):
    inner, outer = rings[k], rings[k + 1]
    if len(inner) == 1:
        c0 = inner[0]
        for i in range(len(outer)):
            tris.append((c0, outer[i], outer[(i + 1) % len(outer)]))
        continue
    i = j = 0
    ni, no = len(inner), len(outer)
    while i < ni or j < no:
        ai = inner[i % ni][3] + (2 * math.pi if i >= ni else 0) + (2 * math.pi if i % ni < i else 0) * 0
        a_next_in = inner[(i + 1) % ni][3] + (2 * math.pi if i + 1 >= ni else 0)
        a_next_out = outer[(j + 1) % no][3] + (2 * math.pi if j + 1 >= no else 0)
        if j < no and (i >= ni or a_next_out <= a_next_in):
            tris.append((inner[i % ni], outer[j % no], outer[(j + 1) % no]))
            j += 1
        else:
            tris.append((inner[i % ni], outer[j % no], inner[(i + 1) % ni]))
            i += 1

def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))

def shade(base, t):
    (a, b, c) = t
    u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    nl = math.sqrt(sum(x * x for x in n)) or 1
    n = tuple(x / nl for x in n)
    if n[2] < 0: n = tuple(-x for x in n)
    lum = 0.32 + 0.9 * max(0.0, sum(n[i] * LIGHT[i] for i in range(3)))
    col = tuple(max(0, min(255, int(ch * lum))) for ch in hexc(base))
    return "#%02X%02X%02X" % col

def stone(base):
    out = []
    for t in tris:
        col = shade(base, t)
        pts = " ".join(f"{p[0]:.1f},{p[1]:.1f}" for p in t)
        out.append(f'<polygon points="{pts}" fill="{col}" stroke="{col}" stroke-width="1.2" stroke-linejoin="round"/>')
    return "\n    ".join(out)

def shadow():
    return (f'<ellipse cx="{CX + 14}" cy="{CY + RY * 0.98}" rx="{RX * 0.86}" ry="{RY * 0.16}" fill="#000" opacity="0.18"/>'
            f'<ellipse cx="{CX + 8}" cy="{CY + RY * 0.96}" rx="{RX * 0.7}" ry="{RY * 0.1}" fill="#000" opacity="0.18"/>')

def inlay(main, accent, groove):
    size = 430
    x0, y0 = CX - size / 2, CY - size / 2 - 8
    def layer(m, a, dx, dy):
        return f'''<svg x="{x0 + dx:.1f}" y="{y0 + dy:.1f}" width="{size}" height="{size}" viewBox="0 0 1000 1000">
    {g["glyph"](m, a)}
    </svg>'''
    return (layer(groove, groove, -5, -6) + "\n    " + layer("#FFFFFF", "#FFFFFF", 4, 5).replace("<path", '<path opacity="0.35"')
            + "\n    " + layer(main, accent, 0, 0))

def icon(stone_color, main, accent, tile=None):
    back = f'<rect x="100" y="100" width="824" height="824" rx="185.4" fill="{tile}"/>' if tile else ""
    groove = shade(stone_color, ((0, 0, 0), (1, 0, -3), (0, 1, -3)))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  {back}
  <g>
    {shadow()}
    {stone(stone_color)}
    {inlay(main, accent, groove)}
  </g>
</svg>
'''

V = {
    "granite":  ("#8E929B", "#5C32F7", "#FC482A"),
    "slate":    ("#5E6675", "#1549F8", "#FF7E5F"),
    "sandstone":("#C9A27E", "#4D62D6", "#F6C377"),
    "basalt":   ("#3A3D45", "#7B5CFF", "#FF6A4D"),
    "jade":     ("#5F9C84", "#204D62", "#F4F0E0"),
}
for name, (st, m, a) in V.items():
    open(f"{OUT}/{name}.svg", "w").write(icon(st, m, a))
    open(f"{OUT}/{name}-tile-light.svg", "w").write(icon(st, m, a, "#F2F1EE"))
    open(f"{OUT}/{name}-tile-dark.svg", "w").write(icon(st, m, a, "#0B0B10"))
print(len(tris), "facets")
