"""Makes the test drawings for "PDF to drawing": PDFs printed the way AutoCAD's DWG To PDF prints.

  python3 tool/make_pdf_drawings.py test/fixtures/pdf

cad-plot.pdf: an A3 sheet at 1:200 (1 m on the ground = 5 mm on paper), drawn like a CAD plot:
  - a polyline as one path; line types as separate dashes (AutoCAD draws the dashes itself)
  - arcs and circles as Bezier curves
  - a solid hatch as a filled shape, a pattern hatch (ANSI31) as loose parallel lines
  - dimensions as extension lines, a dimension line, two filled arrows and the value
  - text as real text (Helvetica)
cad-plot.json: what the drawing holds, which the tests check against.
"""
import json
import math
import os
import sys

from reportlab.lib.pagesizes import A3, landscape
from reportlab.pdfgen import canvas

MM = 72 / 25.4
SCALE = 200  # 1:200: 1 m on the ground = 5 mm on paper


def paper(m):
    """model metres -> points"""
    return m * 1000 / SCALE * MM


def make(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "cad-plot.pdf")
    c = canvas.Canvas(path, pagesize=landscape(A3), pageCompression=1)
    c.setTitle("Test plot")
    ox, oy = 60 * MM, 100 * MM  # where model (0,0) is on the page

    def P(x, y):
        return ox + paper(x), oy + paper(y)

    expect = {"scale": SCALE, "polylines": [], "circles": [], "arcs": [], "texts": [], "hatches": [], "dimensions": [], "linetypes": {}}

    def pen(rgb, width_mm):
        c.setStrokeColorRGB(*rgb)
        c.setLineWidth(width_mm * MM)
        c.setLineCap(1)
        c.setLineJoin(1)

    # ---- building: a closed polyline, white/black, 0.5 mm
    pen((0, 0, 0), 0.5)
    pts = [(0, 0), (20, 0), (20, 12), (12, 12), (12, 8), (0, 8)]
    p = c.beginPath()
    p.moveTo(*P(*pts[0]))
    for q in pts[1:]:
        p.lineTo(*P(*q))
    p.close()
    c.drawPath(p, stroke=1, fill=0)
    expect["polylines"].append({"layer_color": "black", "closed": True, "vertices": len(pts)})

    # ---- road edges: red, 0.35 mm, a straight then an arc (one polyline each in CAD, plotted as one path)
    pen((1, 0, 0), 0.35)
    for off in (-4, 4):
        p = c.beginPath()
        p.moveTo(*P(-5, -10 + off))
        p.lineTo(*P(30, -10 + off))
        c.drawPath(p, stroke=1, fill=0)
    # a curve of the road: arc radius 15 m, centre (30, 5), from -90 to 0 degrees (reportlab arc -> Beziers)
    cx, cy, r = 30, 5, 15
    x0, y0 = P(cx - r, cy - r)
    x1, y1 = P(cx + r, cy + r)
    p = c.beginPath()
    p.arc(x0, y0, x1, y1, startAng=-90, extent=90)
    c.drawPath(p, stroke=1, fill=0)
    expect["arcs"].append({"center": [cx, cy], "radius": r, "start": -90, "end": 0})
    expect["polylines"] += [{"layer_color": "red"}, {"layer_color": "red"}]

    # ---- centre line: CENTER line type (long 12, gap 2, short 2, gap 2 mm), yellow-ish, drawn as dashes
    pen((0.8, 0.6, 0), 0.25)
    pattern = [12, -2, 2, -2]
    x = -5.0
    total_mm = (30 - -5) * 1000 / SCALE
    p = c.beginPath()
    pos = 0.0
    k = 0
    while pos < total_mm - 1e-9:
        d = pattern[k % 4]
        L = min(abs(d), total_mm - pos)
        if d > 0:
            p.moveTo(*P(-5 + pos * SCALE / 1000, -10))
            p.lineTo(*P(-5 + (pos + L) * SCALE / 1000, -10))
        pos += L
        k += 1
    c.drawPath(p, stroke=1, fill=0)
    expect["linetypes"]["center"] = "CENTER"

    # ---- plot boundary: DASHED (6, gap 3 mm), magenta, drawn as dashes along a closed rectangle
    pen((1, 0, 1), 0.25)
    rect = [(-8, -18), (45, -18), (45, 25), (-8, 25), (-8, -18)]
    p = c.beginPath()
    for (ax, ay), (bx, by) in zip(rect, rect[1:]):
        seg = math.hypot(bx - ax, by - ay) * 1000 / SCALE
        ux, uy = (bx - ax) / (seg * SCALE / 1000), (by - ay) / (seg * SCALE / 1000)
        pos = 0.0
        on = True
        while pos < seg - 1e-9:
            L = min(6 if on else 3, seg - pos)
            if on:
                sx, sy = ax + ux * pos * SCALE / 1000, ay + uy * pos * SCALE / 1000
                ex, ey = ax + ux * (pos + L) * SCALE / 1000, ay + uy * (pos + L) * SCALE / 1000
                p.moveTo(*P(sx, sy))
                p.lineTo(*P(ex, ey))
            pos += L
            on = not on
    c.drawPath(p, stroke=1, fill=0)
    expect["linetypes"]["boundary"] = "DASHED"

    # ---- trees: circles r 1.5 m, green
    pen((0, 0.6, 0), 0.25)
    trees = [(25, 15), (30, 20), (35, 15)]
    for tx, ty in trees:
        cx_, cy_ = P(tx, ty)
        c.circle(cx_, cy_, paper(1.5), stroke=1, fill=0)
        expect["circles"].append({"center": [tx, ty], "radius": 1.5})

    # ---- solid hatch: a concrete pad, grey fill (no outline)
    c.setFillColorRGB(0.75, 0.75, 0.75)
    pad = [(2, 1), (10, 1), (10, 6), (2, 6)]
    p = c.beginPath()
    p.moveTo(*P(*pad[0]))
    for q in pad[1:]:
        p.lineTo(*P(*q))
    p.close()
    c.drawPath(p, stroke=0, fill=1)
    expect["hatches"].append({"pattern": "SOLID", "area": 8 * 5})

    # ---- pattern hatch: ANSI31 (45 degrees, 3.175 mm apart on paper) inside a garden, with its outline
    pen((0, 0.6, 0), 0.25)
    g = [(22, 2), (38, 2), (38, 10), (22, 10)]
    p = c.beginPath()
    p.moveTo(*P(*g[0]))
    for q in g[1:]:
        p.lineTo(*P(*q))
    p.close()
    c.drawPath(p, stroke=1, fill=0)
    expect["polylines"].append({"layer_color": "green", "closed": True, "vertices": 4})
    pen((0, 0.6, 0), 0.18)
    spacing = 3.175 * SCALE / 1000  # metres
    step = spacing * math.sqrt(2)  # along x for 45 degree lines
    p = c.beginPath()
    k0 = math.floor((22 - 10) / step) - 1
    k = k0
    n_lines = 0
    while True:
        # line x - y = b
        b = k * step
        k += 1
        # clip to the rectangle
        xs = []
        for X in (22, 38):
            Y = X - b
            if 2 <= Y <= 10:
                xs.append((X, Y))
        for Y in (2, 10):
            X = Y + b
            if 22 <= X <= 38:
                xs.append((X, Y))
        xs = sorted(set((round(a, 9), round(bb, 9)) for a, bb in xs))
        if b > 38 - 2:
            break
        if len(xs) >= 2:
            p.moveTo(*P(*xs[0]))
            p.lineTo(*P(*xs[-1]))
            n_lines += 1
    c.drawPath(p, stroke=1, fill=0)
    expect["hatches"].append({"pattern": "ANSI31", "angle": 45, "lines": n_lines})

    # ---- a dimension along the building's bottom: 20.00, 4 m below it
    pen((0, 0.7, 0.7), 0.18)
    y_dim = -2.0
    p = c.beginPath()
    for X in (0, 20):
        p.moveTo(*P(X, -0.2))
        p.lineTo(*P(X, y_dim - 0.6))
    p.moveTo(*P(0, y_dim))
    p.lineTo(*P(20, y_dim))
    c.drawPath(p, stroke=1, fill=0)
    c.setFillColorRGB(0, 0.7, 0.7)
    a = 2.5 * SCALE / 1000  # arrow length (2.5 mm on paper)
    hw = a / 6
    for X, s in ((0, 1), (20, -1)):
        p = c.beginPath()
        p.moveTo(*P(X, y_dim))
        p.lineTo(*P(X + s * a, y_dim + hw))
        p.lineTo(*P(X + s * a, y_dim - hw))
        p.close()
        c.drawPath(p, stroke=0, fill=1)
    c.setFont("Helvetica", 2.5 * MM / 0.716)
    c.drawCentredString(*P(10, y_dim + 0.1), "20.00")
    expect["dimensions"].append({"from": [0, 0], "to": [20, 0], "value": "20.00"})

    # ---- text
    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica-Bold", 3.5 * MM / 0.716)
    c.drawString(*P(4, 9.5), "BUILDING")
    expect["texts"].append({"text": "BUILDING", "height_mm": 3.5, "angle": 0})
    c.setFillColorRGB(1, 0, 0)
    c.setFont("Helvetica", 2.5 * MM / 0.716)
    c.drawString(*P(0, -7.5), "ROAD")
    expect["texts"].append({"text": "ROAD", "height_mm": 2.5, "angle": 0})
    c.saveState()
    x_, y_ = P(15, 18)
    c.translate(x_, y_)
    c.rotate(30)
    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica", 1.8 * MM / 0.716)
    c.drawString(0, 0, "+101.250")
    c.restoreState()
    expect["texts"].append({"text": "+101.250", "height_mm": 1.8, "angle": 30})

    c.showPage()
    c.save()
    with open(os.path.join(out_dir, "cad-plot.json"), "w") as f:
        json.dump(expect, f, indent=1)
    print(path)


if __name__ == "__main__":
    make(sys.argv[1] if len(sys.argv) > 1 else "test/fixtures/pdf")
