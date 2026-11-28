import math, os
OUT = "/Users/xtanion/stone/docs/logo/loop-a-pro"
env = lambda k, d: float(os.environ.get(k, d))
W, GAP = env("W", 94), env("GAP", 18)
LEAN = math.radians(env("LEAN", 14))
S, c, s = math.tan(LEAN), math.cos(LEAN), math.sin(LEAN)
R, r = env("R", 135), env("HOOK", 90)
BASE = 880.0
T = (500.0, 250.0)
nl, nr = (-c, -s), (c, -s)
TL = (T[0] + R * nl[0], T[1] + R * nl[1])
TR = (T[0] + R * nr[0], T[1] + R * nr[1])
left_x = lambda y: TL[0] - S * (y - TL[1])
right_x = lambda y: TR[0] + S * (y - TR[1])
By = BASE - r
ty = By + r * nr[1]
Bx = right_x(ty) - r * nr[0]
HR = (Bx + r * nr[0], By + r * nr[1])
HL = (Bx - r * nr[0], By - r * nr[1])
inner_x = lambda y: HL[0] - S * (HL[1] - y)
Ra = R * env("ARCH", 1)
Cy = env("CY", 615)
Cx = left_x(Cy + Ra * nl[1]) - Ra * nl[0]
AL = (Cx + Ra * nl[0], Cy + Ra * nl[1])
# first point clockwise from the top where the arch meets the inner leg centreline
best = None
for i in range(0, 1800):
    a = math.radians(-90 + i * 0.1)
    x, y = Cx + Ra * math.cos(a), Cy + Ra * math.sin(a)
    if x >= inner_x(y):
        best = (a, x, y); break
A_END, EX, EY = best
OVER = env("OVER", 0.75) * W
dlen = math.hypot(S, 1)
END = (inner_x(EY - OVER / dlen * 1), EY - OVER / dlen)
f = lambda v: f"{v:.1f}"
P = lambda p: f"{f(p[0])} {f(p[1])}"
LEFT_START_Y = Cy
MAIN = (f"M {f(left_x(LEFT_START_Y))} {f(LEFT_START_Y)} L {P(TL)} A {R} {R} 0 0 1 {P(TR)} L {P(HR)} "
        f"A {r} {r} 0 0 1 {f(Bx)} {f(BASE)} A {r} {r} 0 0 1 {P(HL)} L {P(END)}")
INNER = f"M {P(HL)} L {P(END)}"
large = 1 if (A_END - math.atan2(nl[1], nl[0]) % (2 * math.pi)) % (2 * math.pi) > math.pi else 0
ACCENT = f"M {f(left_x(BASE))} {f(BASE)} L {P(AL)} A {f(Ra)} {f(Ra)} 0 0 1 {f(EX)} {f(EY)}"
minx, maxx = left_x(BASE) - W / 2, Bx + r + W / 2
miny, maxy = T[1] - R - W / 2, BASE + W / 2
cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
scale = 840 / max(maxx - minx, maxy - miny)
def glyph(main, accent):
    return f'''<defs>
    <mask id="under-main" maskUnits="userSpaceOnUse" x="-500" y="-500" width="2000" height="2000">
      <rect x="-500" y="-500" width="2000" height="2000" fill="#fff"/>
      <path d="{ACCENT}" fill="none" stroke="#000" stroke-width="{W + 2 * GAP}" stroke-linejoin="round"/>
      <rect x="{f(Cx)}" y="-500" width="2000" height="2000" fill="#fff"/>
    </mask>
    <mask id="under-accent" maskUnits="userSpaceOnUse" x="-500" y="-500" width="2000" height="2000">
      <rect x="-500" y="-500" width="2000" height="2000" fill="#fff"/>
      <path d="{INNER}" fill="none" stroke="#000" stroke-width="{W + 2 * GAP}" stroke-linecap="round"/>
    </mask>
  </defs>
  <g transform="translate(500 500) scale({scale:.4f}) translate({f(-cx)} {f(-cy)})" fill="none" stroke-width="{W}" stroke-linecap="round" stroke-linejoin="round">
    <path d="{MAIN}" stroke="{main}" mask="url(#under-main)"/>
    <path d="{ACCENT}" stroke="{accent}" mask="url(#under-accent)"/>
  </g>'''
def mark(main, accent):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">\n  {glyph(main, accent)}\n</svg>\n'
def icon(main, accent, tile):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect x="100" y="100" width="824" height="824" rx="185.4" fill="{tile}"/>
  <svg x="212" y="212" width="600" height="600" viewBox="0 0 1000 1000">
  {glyph(main, accent)}
  </svg>
</svg>
'''
V = {
    "original": ("#5C32F7", "#FC482A"),
    "stone":    ("#1549F8", "#FF7E5F"),
    "daybreak": ("#1A78F0", "#DECD93"),
    "dusk":     ("#4D62D6", "#F6C377"),
    "sunset":   ("#F4914E", "#A9C3F0"),
    "tide":     ("#204D62", "#94C7A7"),
}
for n, (a, b) in V.items():
    open(f"{OUT}/{n}-mark.svg", "w").write(mark(a, b))
    open(f"{OUT}/{n}-icon-light.svg", "w").write(icon(a, b, "#FFFFFF"))
    open(f"{OUT}/{n}-icon-dark.svg", "w").write(icon(a, b, "#010008"))
open(f"{OUT}/mono-black-mark.svg", "w").write(mark("#000000", "#000000"))
open(f"{OUT}/mono-white-mark.svg", "w").write(mark("#FFFFFF", "#FFFFFF"))
print("arch end angle", round(math.degrees(A_END), 1), "C", f(Cx), f(Cy), "end", P(END), "bbox", f(minx), f(maxx), f(miny), f(maxy))
