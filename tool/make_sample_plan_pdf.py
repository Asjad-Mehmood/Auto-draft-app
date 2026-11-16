"""Writes a detailed sample PDF drawing for "PDF to drawing", printed the way AutoCAD's
DWG To PDF prints (with "include layer information" on for page 1):

  python3 tool/make_sample_plan_pdf.py assets/samples/sample-site-plan.pdf

Page 1, A2 at 1:250, with the PDF's own layers (optional content groups):
  plot boundary (PHANTOM), road edges with a curve and junction fillets, road centre lines (CENTER),
  two buildings (one L-shaped) with ANSI31 hatch, paving (solid hatch), lawn (ANSI37), parking
  bays, trees (circles), manholes, a drain (DASHED) with its flow arrow, contours, spot levels,
  grid crosses with coordinates, nine dimensions (horizontal, vertical, aligned), labels, a north
  arrow, a scale bar, the border and the title block.
Page 2, A3 at 1:50, without layers (one per colour and line type): a road cross section with
  its pavement layers hatched, side drains, kerbs, the centre line and dimensions.

Every line is drawn the way a CAD plot draws it: dashes as separate pieces, arcs as Bezier curves,
pattern hatches as loose lines, dimensions as lines, filled arrows and text. Plain Python: no
libraries needed.
"""
import math
import sys
import zlib

PT = 72 / 25.4  # points per mm


class Page:
    def __init__(self, w_mm, h_mm, scale, origin_mm):
        self.w, self.h = w_mm * PT, h_mm * PT
        self.scale = scale
        self.ox, self.oy = origin_mm
        self.ops = []
        self.layer = None

    # model metres -> page points
    def P(self, x, y):
        return ((self.ox + x * 1000 / self.scale) * PT, (self.oy + y * 1000 / self.scale) * PT)

    def mm(self, v):  # paper mm -> points
        return v * PT

    def on(self, layer):
        if self.layer is not None:
            self.ops.append("EMC")
        self.layer = layer
        if layer is not None:
            self.ops.append(f"/OC /{layer} BDC")

    def end(self):
        self.on(None)

    def pen(self, rgb, width_mm):
        r, g, b = rgb
        self.ops.append(f"{r:.3f} {g:.3f} {b:.3f} RG {width_mm * PT:.3f} w 1 J 1 j")

    def brush(self, rgb):
        r, g, b = rgb
        self.ops.append(f"{r:.3f} {g:.3f} {b:.3f} rg")

    # ---------------------------------------------------------------- geometry
    def _seg_points(self, pts, pattern_mm=None, closed=False):
        """the pieces to stroke: the whole line, or its dashes (paper mm pattern)"""
        pts = list(pts) + ([pts[0]] if closed else [])
        if not pattern_mm:
            return [pts]
        out = []
        for a, b in zip(pts, pts[1:]):
            L = math.hypot(b[0] - a[0], b[1] - a[1]) * 1000 / self.scale  # paper mm
            if L == 0:
                continue
            ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
            pos, k = 0.0, 0
            while pos < L - 1e-9:
                d = pattern_mm[k % len(pattern_mm)]
                n = min(abs(d), L - pos)
                if d >= 0:
                    s = (a[0] + ux * pos, a[1] + uy * pos)
                    e = (a[0] + ux * (pos + max(n, 0.0)), a[1] + uy * (pos + max(n, 0.0)))
                    out.append([s, e])
                pos += abs(d) if d != 0 else 0
                if d == 0:
                    pos += 0  # a dot has no length
                k += 1
                if d == 0 and k % len(pattern_mm) != 0:
                    continue
        return out

    def polyline(self, pts, closed=False, pattern_mm=None):
        pieces = self._seg_points(pts, pattern_mm, closed)
        path = []
        for piece in pieces:
            x, y = self.P(*piece[0])
            path.append(f"{x:.3f} {y:.3f} m")
            for q in piece[1:]:
                x, y = self.P(*q)
                path.append(f"{x:.3f} {y:.3f} l")
            if closed and not pattern_mm:
                path.append("h")
        self.ops.append(" ".join(path) + " S")

    def _arc_bez(self, cx, cy, r, a0, a1):
        """Bezier pieces (model) of the arc a0 -> a1 degrees, anticlockwise if a1 > a0"""
        out = []
        n = max(1, int(math.ceil(abs(a1 - a0) / 90)))
        step = (a1 - a0) / n
        for i in range(n):
            t0 = math.radians(a0 + i * step)
            t1 = math.radians(a0 + (i + 1) * step)
            k = 4 / 3 * math.tan((t1 - t0) / 4)
            p0 = (cx + r * math.cos(t0), cy + r * math.sin(t0))
            p3 = (cx + r * math.cos(t1), cy + r * math.sin(t1))
            p1 = (p0[0] - k * r * math.sin(t0), p0[1] + k * r * math.cos(t0))
            p2 = (p3[0] + k * r * math.sin(t1), p3[1] - k * r * math.cos(t1))
            out.append((p0, p1, p2, p3))
        return out

    def arc(self, cx, cy, r, a0, a1, pattern_mm=None):
        if pattern_mm:
            # dashed: each dash its own little arc, as a plot draws it
            L = abs(math.radians(a1 - a0)) * r * 1000 / self.scale
            pos, k, sgn = 0.0, 0, 1 if a1 > a0 else -1
            path = []
            while pos < L - 1e-9:
                d = pattern_mm[k % len(pattern_mm)]
                n = min(abs(d), L - pos)
                if d > 0:
                    s = a0 + sgn * math.degrees(pos / (r * 1000 / self.scale))
                    e = a0 + sgn * math.degrees((pos + n) / (r * 1000 / self.scale))
                    for i, (p0, p1, p2, p3) in enumerate(self._arc_bez(cx, cy, r, s, e)):
                        if i == 0:
                            path.append("%.3f %.3f m" % self.P(*p0))
                        path.append("%.3f %.3f %.3f %.3f %.3f %.3f c" % (*self.P(*p1), *self.P(*p2), *self.P(*p3)))
                pos += abs(d)
                k += 1
            self.ops.append(" ".join(path) + " S")
            return
        path = []
        for i, (p0, p1, p2, p3) in enumerate(self._arc_bez(cx, cy, r, a0, a1)):
            if i == 0:
                path.append("%.3f %.3f m" % self.P(*p0))
            path.append("%.3f %.3f %.3f %.3f %.3f %.3f c" % (*self.P(*p1), *self.P(*p2), *self.P(*p3)))
        self.ops.append(" ".join(path) + " S")

    def circle(self, cx, cy, r):
        path = []
        for i, (p0, p1, p2, p3) in enumerate(self._arc_bez(cx, cy, r, 0, 360)):
            if i == 0:
                path.append("%.3f %.3f m" % self.P(*p0))
            path.append("%.3f %.3f %.3f %.3f %.3f %.3f c" % (*self.P(*p1), *self.P(*p2), *self.P(*p3)))
        self.ops.append(" ".join(path) + " h S")

    def fill(self, pts):
        path = ["%.3f %.3f m" % self.P(*pts[0])] + ["%.3f %.3f l" % self.P(*q) for q in pts[1:]]
        self.ops.append(" ".join(path) + " h f")

    def hatch(self, poly, angle_deg, spacing_mm):
        """loose parallel lines clipped to the polygon (paper spacing), as a plot draws a pattern"""
        sp = spacing_mm * self.scale / 1000
        a = math.radians(angle_deg)
        ux, uy = math.cos(a), math.sin(a)
        nx, ny = -uy, ux
        offs = [nx * x + ny * y for x, y in poly]
        lo, hi = min(offs), max(offs)
        o = math.floor(lo / sp) * sp + sp * 0.5
        path = []
        while o < hi:
            ts = []
            for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
                d0, d1 = nx * x0 + ny * y0 - o, nx * x1 + ny * y1 - o
                if (d0 < 0) != (d1 < 0):
                    t = d0 / (d0 - d1)
                    px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
                    ts.append(ux * px + uy * py)
            ts.sort()
            for i in range(0, len(ts) - 1, 2):
                s = (ux * ts[i] + nx * o, uy * ts[i] + ny * o)
                e = (ux * ts[i + 1] + nx * o, uy * ts[i + 1] + ny * o)
                path.append("%.3f %.3f m %.3f %.3f l" % (*self.P(*s), *self.P(*e)))
            o += sp
        if path:
            self.ops.append(" ".join(path) + " S")

    def text(self, x, y, h_mm, s, angle=0, bold=False, align="left", rgb=(0, 0, 0)):
        """capital height h_mm on paper; Helvetica's capitals are 0.718 of its size"""
        size = h_mm / 0.718 * PT
        width = len(s) * 0.55 * size  # near enough to centre a label
        px, py = self.P(x, y)
        a = math.radians(angle)
        dx = {"left": 0, "center": -width / 2, "right": -width}[align]
        px += dx * math.cos(a)
        py += dx * math.sin(a)
        c, sn = math.cos(a), math.sin(a)
        r, g, b = rgb
        f = "F2" if bold else "F1"
        esc = s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
        self.ops.append(
            f"BT {r:.3f} {g:.3f} {b:.3f} rg /{f} {size:.3f} Tf {c:.5f} {sn:.5f} {-sn:.5f} {c:.5f} {px:.3f} {py:.3f} Tm ({esc}) Tj ET"
        )

    def dimension(self, p1, p2, offset, rgb, text=None, text_mm=2.5):
        """aligned dimension of p1 -> p2, its line offset (model m) to the left of p1->p2"""
        (x1, y1), (x2, y2) = p1, p2
        L = math.hypot(x2 - x1, y2 - y1)
        ux, uy = (x2 - x1) / L, (y2 - y1) / L
        nx, ny = -uy, ux
        a = (x1 + nx * offset, y1 + ny * offset)
        b = (x2 + nx * offset, y2 + ny * offset)
        gap = 0.8 * self.scale / 1000
        ext = 1.5 * self.scale / 1000
        sgn = 1 if offset > 0 else -1
        self.pen(rgb, 0.18)
        path = []
        for (px, py), (qx, qy) in ((p1, a), (p2, b)):
            s = (px + nx * gap * sgn, py + ny * gap * sgn)
            e = (qx + nx * ext * sgn, qy + ny * ext * sgn)
            path.append("%.3f %.3f m %.3f %.3f l" % (*self.P(*s), *self.P(*e)))
        path.append("%.3f %.3f m %.3f %.3f l" % (*self.P(*a), *self.P(*b)))
        self.ops.append(" ".join(path) + " S")
        self.brush(rgb)
        al = 2.5 * self.scale / 1000
        hw = al / 6
        for (tx, ty), s in ((a, 1), (b, -1)):
            tri = [(tx, ty), (tx + s * ux * al + nx * hw, ty + s * uy * al + ny * hw), (tx + s * ux * al - nx * hw, ty + s * uy * al - ny * hw)]
            self.fill(tri)
        ang = math.degrees(math.atan2(uy, ux))
        if ang > 90.01 or ang < -89.99:
            ang -= 180 if ang > 0 else -180
        mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        up = 0.8 * self.scale / 1000
        rad = math.radians(ang)
        tx, ty = mx - math.sin(rad) * up, my + math.cos(rad) * up
        self.text(tx, ty, text_mm, text or f"{L:.2f}", angle=ang, align="center", rgb=rgb)


# ---------------------------------------------------------------------------------------------
# Page 1: the site plan
# ---------------------------------------------------------------------------------------------

BLACK, RED, GREEN, BLUE, CYAN, MAGENTA = (0, 0, 0), (1, 0, 0), (0, 0.6, 0), (0, 0, 1), (0, 0.65, 0.65), (0.85, 0, 0.85)
GREY, BROWN, ORANGE = (0.5, 0.5, 0.5), (0.6, 0.35, 0.1), (0.95, 0.5, 0)
DASHED, CENTER, PHANTOM, HIDDEN = [12.7 * 0.5, -6.35 * 0.5], [31.75 * 0.4, -6.35 * 0.4, 6.35 * 0.4, -6.35 * 0.4], [31.75 * 0.4, -6.35 * 0.4, 6.35 * 0.4, -6.35 * 0.4, 6.35 * 0.4, -6.35 * 0.4], [6.35 * 0.5, -3.175 * 0.5]

LAYERS = [
    "C-PROP-BNDY", "C-ROAD-EDGE", "C-ROAD-CNTR", "A-BLDG", "A-BLDG-PATT", "C-PAVE", "L-LAWN", "C-PARK",
    "L-TREE", "C-UTIL-MH", "C-UTIL-DRAIN", "C-TOPO-CONT", "C-TOPO-LEVL", "G-GRID", "G-ANNO-DIMS", "G-ANNO-TEXT", "G-TTLB",
]


def site_plan():
    pg = Page(594, 420, 250, (52, 110))  # A2 at 1:250; model (0,0) 52 mm from the left, 110 mm up
    L = {n: f"L{i}" for i, n in enumerate(LAYERS)}

    # ---- border and title block (paper mm, drawn as if 1:1 via a model of scale/1000)
    pg.on(L["G-TTLB"])
    pg.pen(BLACK, 0.7)
    s = 250 / 1000
    def pm(x, y):  # paper mm -> model m
        return ((x - 52) * s, (y - 110) * s)
    pg.polyline([pm(10, 10), pm(584, 10), pm(584, 410), pm(10, 410)], closed=True)
    # the title block: a column down the right
    pg.pen(BLACK, 0.35)
    pg.polyline([pm(494, 10), pm(494, 410)])
    for yy in (30, 50, 70, 100, 130):
        pg.polyline([pm(494, yy), pm(584, yy)])
    pg.polyline([pm(539, 10), pm(539, 50)])
    pg.text(*pm(498, 112), 5, "SITE PLAN", bold=True)
    pg.text(*pm(498, 104), 2.2, "PLOT 42, MODEL TOWN")
    pg.text(*pm(498, 84), 2.5, "AL-NOOR SURVEYS (SAMPLE)")
    pg.text(*pm(498, 76), 2.0, "SAMPLE DRAWING FOR TESTING", rgb=GREY)
    pg.text(*pm(498, 58), 2.5, "SCALE 1:250 (A2)")
    pg.text(*pm(498, 38), 2.2, "SHEET 1 OF 2")
    pg.text(*pm(543, 38), 2.2, "REV A")
    pg.text(*pm(498, 18), 2.2, "DRAWN: AUTO DRAFTING")
    pg.text(*pm(543, 18), 2.2, "DWG SP-042-01")

    # ---- grid crosses every 20 m with their coordinates
    pg.on(L["G-GRID"])
    pg.pen(GREY, 0.18)
    for gx in range(0, 101, 20):
        for gy in range(0, 61, 20):
            pg.polyline([(gx - 1, gy), (gx + 1, gy)])
            pg.polyline([(gx, gy - 1), (gx, gy + 1)])
        pg.text(gx, -4.6, 1.8, f"E {436200 + gx}", align="center", rgb=GREY)
    for gy in range(0, 61, 20):
        pg.text(-3.2, gy, 1.8, f"N {3487400 + gy}", angle=90, align="center", rgb=GREY)

    # ---- the road along the bottom, curving up the right, with a side road and junction fillets
    pg.on(L["C-ROAD-EDGE"])
    pg.pen(BLACK, 0.35)
    pg.polyline([(-6, 2), (30, 2)])
    pg.arc(30, 8, 6, 270, 360)  # fillet into the side road (left kerb)
    pg.polyline([(36, 8), (36, 14)])
    pg.polyline([(46, 14), (46, 8)])
    pg.arc(52, 8, 6, 180, 270)  # fillet (right kerb)
    pg.polyline([(52, 2), (80, 2)])
    pg.arc(80, 22, 20, 270, 360)  # the main road's curve
    pg.polyline([(-6, -6), (80, -6)])
    pg.arc(80, 22, 28, 270, 360)
    pg.polyline([(100, 22), (100, 50)])
    pg.polyline([(108, 22), (108, 50)])
    pg.on(L["C-ROAD-CNTR"])
    pg.pen(RED, 0.18)
    pg.polyline([(-6, -2), (80, -2)], pattern_mm=CENTER)
    pg.arc(80, 22, 24, 270, 360, pattern_mm=CENTER)
    pg.polyline([(104, 22), (104, 50)], pattern_mm=CENTER)
    pg.polyline([(41, 2), (41, 14)], pattern_mm=CENTER)

    # ---- plot boundary (PHANTOM)
    pg.on(L["C-PROP-BNDY"])
    pg.pen(MAGENTA, 0.35)
    bnd = [(4, 14), (90, 14), (90, 58), (4, 58)]
    pg.polyline(bnd, closed=True, pattern_mm=PHANTOM)

    # ---- buildings
    bldg1 = [(10, 30), (34, 30), (34, 39), (31, 42), (22, 42), (22, 52), (10, 52)]  # L-shaped, one corner cut
    bldg2 = [(56, 34), (78, 34), (78, 50), (56, 50)]
    pg.on(L["A-BLDG"])
    pg.pen(BLACK, 0.5)
    pg.polyline(bldg1, closed=True)
    pg.polyline(bldg2, closed=True)
    pg.on(L["A-BLDG-PATT"])
    pg.pen(GREY, 0.13)
    pg.hatch(bldg1, 45, 3.175)
    pg.hatch(bldg2, 45, 3.175)

    # ---- paving (solid) and lawn (ANSI37 cross hatch) with its edge
    pg.on(L["C-PAVE"])
    pg.brush((0.82, 0.82, 0.82))
    pg.fill([(36, 14), (46, 14), (46, 30), (36, 30)])
    pg.fill([(36, 30), (52, 30), (52, 22), (88, 22), (88, 30), (52, 30), (52, 31.5), (36, 31.5)])
    pg.on(L["L-LAWN"])
    lawn = [(12, 18), (30, 18), (30, 26), (12, 26)]
    pg.pen(GREEN, 0.25)
    pg.polyline(lawn, closed=True)
    pg.pen(GREEN, 0.13)
    pg.hatch(lawn, 45, 3.175)
    pg.hatch(lawn, 135, 3.175)

    # ---- parking bays (2.5 m wide, 5 m deep)
    pg.on(L["C-PARK"])
    pg.pen(BLACK, 0.25)
    for i in range(9):
        x = 54 + i * 2.5
        pg.polyline([(x, 17), (x, 22)])
    pg.polyline([(54, 17), (74, 17)])

    # ---- trees: canopy circle and trunk
    pg.on(L["L-TREE"])
    pg.pen(GREEN, 0.25)
    for tx, ty, r in ((6, 20, 1.6), (6, 30, 1.6), (6, 40, 1.6), (40, 52, 2.2), (46, 45, 1.8), (84, 54, 2.0), (86, 40, 1.6)):
        pg.circle(tx, ty, r)
        pg.circle(tx, ty, 0.25)

    # ---- manholes and the drain between them (DASHED), with a flow arrow
    pg.on(L["C-UTIL-MH"])
    pg.pen(BLUE, 0.25)
    mhs = [(20, -4), (50, -4), (78, -4)]
    for x, y in mhs:
        pg.circle(x, y, 0.6)
        pg.polyline([(x - 0.6, y - 0.6), (x + 0.6, y - 0.6), (x + 0.6, y + 0.6), (x - 0.6, y + 0.6)], closed=True)
        pg.text(x + 1, y + 0.9, 1.8, "MH", rgb=BLUE)
    pg.on(L["C-UTIL-DRAIN"])
    pg.pen(BLUE, 0.25)
    pg.polyline([(20.6, -4), (49.4, -4)], pattern_mm=DASHED)
    pg.polyline([(50.6, -4), (77.4, -4)], pattern_mm=DASHED)
    pg.brush(BLUE)
    pg.fill([(35, -4), (33.6, -3.6), (33.6, -4.4)])
    pg.text(30, -5.6, 1.8, "300 DIA DRAIN 1:150", rgb=BLUE)

    # ---- contours (every 0.25 m), gently curving across the plot
    pg.on(L["C-TOPO-CONT"])
    for k in range(6):
        pg.pen(BROWN, 0.35 if k % 4 == 0 else 0.18)
        pts = [(x, 16 + k * 7 + 2.5 * math.sin(x / 14 + k * 0.6)) for x in [6 + i * 3 for i in range(28)]]
        # broken where it would cross a building or the paving
        def inside(p):
            return (8 < p[0] < 36 and 28 < p[1] < 54) or (54 < p[0] < 80 and 32 < p[1] < 52) or (35 < p[0] < 89 and 13 < p[1] < 32)
        runs, run = [], []
        for p in pts:
            if inside(p):
                if len(run) > 1:
                    runs.append(run)
                run = []
            else:
                run.append(p)
        if len(run) > 1:
            runs.append(run)
        for r in runs:
            pg.polyline(r)
        if runs:
            last = runs[-1][-1]
            pg.text(last[0] + 0.6, last[1], 1.8, f"{100.0 + k * 0.25:.2f}", rgb=BROWN)

    # ---- spot levels
    pg.on(L["C-TOPO-LEVL"])
    pg.pen(BLACK, 0.18)
    for x, y, z in ((8, 16, 100.125), (88, 16, 100.340), (88, 56, 101.420), (8, 56, 101.050), (41, 20, 100.380), (66, 26, 100.615)):
        pg.polyline([(x - 0.4, y - 0.4), (x + 0.4, y + 0.4)])
        pg.polyline([(x - 0.4, y + 0.4), (x + 0.4, y - 0.4)])
        pg.text(x + 0.6, y + 0.5, 1.8, f"+{z:.3f}")

    # ---- dimensions
    pg.on(L["G-ANNO-DIMS"])
    pg.dimension((10, 30), (34, 30), -2.5, CYAN)  # 24.00
    pg.dimension((10, 52), (10, 30), -2.0, CYAN)  # 22.00 (vertical)
    pg.dimension((31, 42), (34, 39), -1.5, CYAN, text=None)  # aligned: the cut corner, 4.24
    pg.dimension((56, 50), (78, 50), 2.5, CYAN)  # 22.00
    pg.dimension((78, 50), (78, 34), 2.5, CYAN)  # 16.00
    pg.dimension((4, 58), (90, 58), 3.0, CYAN)  # frontage 86.00
    pg.dimension((90, 58), (90, 14), 3.5, CYAN)  # depth 44.00
    pg.dimension((54, 17), (74, 17), -2.0, CYAN)  # parking 20.00
    pg.dimension((36, 14), (46, 14), -1.5, CYAN)  # driveway 10.00

    # ---- labels
    pg.on(L["G-ANNO-TEXT"])
    pg.text(12, 46, 3.5, "HOUSE", bold=True)
    pg.text(12, 43.5, 2.0, "FFL +101.250")
    pg.text(58, 44, 3.5, "GARAGE", bold=True)
    pg.text(58, 41.5, 2.0, "FFL +100.950")
    pg.text(14, 21.5, 2.5, "LAWN", rgb=GREEN)
    pg.text(56, 23, 2.5, "PARKING (8 BAYS)")
    pg.text(30, -1.2, 3.0, "MAIN ROAD (20 m R.O.W.)", bold=True)
    pg.text(102, 30, 3.0, "LINK ROAD", angle=90, bold=True)
    pg.text(37.2, 18, 2.0, "DRIVEWAY", angle=90)
    pg.text(60, 59.5, 2.0, "PLOT BOUNDARY", rgb=MAGENTA)

    # ---- north arrow and scale bar (paper sizes)
    pg.on(L["G-TTLB"])
    pg.pen(BLACK, 0.25)
    nx, ny = pm(539, 360)
    pg.brush(BLACK)
    pg.fill([(nx, ny + 4), (nx - 1.6, ny - 2), (nx, ny - 0.8)])
    pg.polyline([(nx, ny + 4), (nx + 1.6, ny - 2), (nx, ny - 0.8)])
    pg.text(nx, ny + 5, 4, "N", bold=True, align="center")
    bx, by = pm(504, 300)
    # 16 m in four blocks of 4 m (64 mm on paper)
    for i in range(4):
        x0 = bx + i * 4
        if i % 2 == 0:
            pg.fill([(x0, by), (x0 + 4, by), (x0 + 4, by + 0.8), (x0, by + 0.8)])
    pg.polyline([(bx, by), (bx + 16, by), (bx + 16, by + 0.8), (bx, by + 0.8)], closed=True)
    for i, lab in enumerate(("0", "8", "16 m")):
        pg.text(bx + i * 8, by + 1.4, 1.8, lab, align="center")
    pg.text(bx, by - 2.4, 2.0, "SCALE 1:250")
    pg.end()
    return pg, LAYERS


# ---------------------------------------------------------------------------------------------
# Page 2: a road cross section at 1:50, no layers
# ---------------------------------------------------------------------------------------------

def cross_section():
    pg = Page(420, 297, 50, (210, 150))  # A3; model metres, 1 m = 20 mm; the centre line mid-sheet
    s = 50 / 1000
    def pm(x, y):
        return ((x - 210) * s, (y - 150) * s)
    pg.pen(BLACK, 0.7)
    pg.polyline([pm(10, 10), pm(410, 10), pm(410, 287), pm(10, 287)], closed=True)
    pg.text(*pm(20, 270), 5, "TYPICAL ROAD CROSS SECTION", bold=True)
    pg.text(*pm(20, 262), 2.5, "SCALE 1:50 (A3)  SHEET 2 OF 2")

    # surface: 7.3 m carriageway with 2.5 % crossfall each way, kerbs, footpaths, drains
    half = 3.65
    top = lambda x: -0.025 * abs(x)  # noqa: E731
    pg.pen(BLACK, 0.5)
    pg.polyline([(-half, top(-half)), (0, 0), (half, top(half))])
    layers = [("WEARING COURSE 50 mm", 0.05, (0.25, 0.25, 0.25), "solid"),
              ("BASE COURSE 150 mm", 0.15, None, 45),
              ("SUB-BASE 200 mm", 0.20, None, 135)]
    d = 0.0
    label_y = [1.6, 1.0, 0.4]
    for (name, t, rgb, kind), ly in zip(layers, label_y):
        poly = [(-half, top(-half) - d), (0, -d), (half, top(half) - d), (half, top(half) - d - t), (0, -d - t), (-half, top(-half) - d - t)]
        pg.pen(BLACK, 0.25)
        pg.polyline(poly, closed=True)
        if kind == "solid":
            pg.brush(rgb)
            pg.fill(poly)
        else:
            pg.pen(GREY, 0.13)
            pg.hatch(poly, kind, 3.175)
        # a leader from the layer up to its label, above the right footpath
        mid = (half - 0.8, top(half - 0.8) - d - t / 2)
        pg.pen(BLACK, 0.18)
        pg.polyline([mid, (half + 0.6, ly), (half + 1.2, ly)])
        pg.brush(BLACK)
        pg.fill([mid, (mid[0] + 0.09, mid[1] + 0.2), (mid[0] + 0.2, mid[1] + 0.12)])
        pg.text(half + 1.3, ly - 0.05, 2.2, name)
        d += t
    # kerbs and footpaths
    pg.pen(BLACK, 0.35)
    for sgn in (-1, 1):
        k0 = sgn * half
        pg.polyline([(k0, top(half)), (k0, top(half) + 0.15), (k0 + sgn * 0.15, top(half) + 0.15), (k0 + sgn * 0.15, top(half) - 0.3), (k0, top(half) - 0.3)], closed=False)
        pg.polyline([(k0 + sgn * 0.15, top(half) + 0.15), (k0 + sgn * 2.15, top(half) + 0.19)])
        # a side drain: a U channel
        dx = k0 + sgn * 2.35
        pg.polyline([(dx, top(half) + 0.19), (dx, top(half) - 0.45), (dx + sgn * 0.5, top(half) - 0.45), (dx + sgn * 0.5, top(half) + 0.19)])
    # the centre line (CENTER) and the ground (DASHED)
    pg.pen(RED, 0.18)
    pg.polyline([(0, 0.9), (0, -0.9)], pattern_mm=CENTER)
    pg.text(0.1, 0.95, 2.2, "CL", rgb=RED)
    pg.pen(BROWN, 0.25)
    pg.polyline([(-7.2, -0.35), (-5, -0.3), (5, -0.42), (7.2, -0.38)], pattern_mm=DASHED)
    pg.text(-7.1, -0.25, 2.0, "EXISTING GROUND", rgb=BROWN)
    # dimensions
    pg.dimension((-half, top(half)), (half, top(half)), -1.3, CYAN)  # 7.30
    pg.dimension((-half, top(half) + 0.15), (-half - 2.15, top(half) + 0.19), -0.6, CYAN, text="2.15")
    pg.dimension((half, top(half) + 0.15), (half + 2.15, top(half) + 0.19), 0.6, CYAN, text="2.15")
    pg.text(-1.9, 0.12, 2.0, "2.5 %", angle=math.degrees(math.atan(0.025)))
    pg.text(0.9, 0.0, 2.0, "2.5 %", angle=-math.degrees(math.atan(0.025)))
    return pg


# ---------------------------------------------------------------------------------------------
# The PDF file
# ---------------------------------------------------------------------------------------------

def write(path, which=(1, 2)):
    p1, layers = site_plan()
    p2 = cross_section()
    objs = []

    def add(s):
        objs.append(s)
        return len(objs)

    cat = add(None)
    pages = add(None)
    f1 = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    f2 = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
    ocgs = [add(f"<< /Type /OCG /Name ({n}) >>".encode()) for n in layers]
    kids = []
    for i, pg in [(i, pg) for i, pg in enumerate((p1, p2)) if i + 1 in which]:
        data = zlib.compress("\n".join(pg.ops).encode("latin-1"))
        content = add(b"<< /Length %d /Filter /FlateDecode >>\nstream\n" % len(data) + data + b"\nendstream")
        props = " ".join(f"/L{k} {ocgs[k]} 0 R" for k in range(len(layers))) if i == 0 else ""
        res = f"<< /Font << /F1 {f1} 0 R /F2 {f2} 0 R >> /Properties << {props} >> >>"
        kids.append(add(f"<< /Type /Page /Parent {pages} 0 R /MediaBox [0 0 {pg.w:.2f} {pg.h:.2f}] /Contents {content} 0 R /Resources {res} >>".encode()))
    objs[pages - 1] = f"<< /Type /Pages /Kids [{' '.join(f'{k} 0 R' for k in kids)}] /Count {len(kids)} >>".encode()
    refs = " ".join(f"{o} 0 R" for o in ocgs)
    objs[cat - 1] = f"<< /Type /Catalog /Pages {pages} 0 R /OCProperties << /OCGs [{refs}] /D << /ON [{refs}] /Order [{refs}] >> >> >>".encode()
    info = add(b"<< /Title (Sample site plan) /Creator (Auto Drafting sample) /Producer (make_sample_plan_pdf.py) >>")

    out = bytearray(b"%PDF-1.6\n%\xe2\xe3\xcf\xd3\n")
    offs = []
    for i, o in enumerate(objs):
        offs.append(len(out))
        out += f"{i + 1} 0 obj\n".encode() + o + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    for o in offs:
        out += f"{o:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs) + 1} /Root {cat} 0 R /Info {info} 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    with open(path, "wb") as f:
        f.write(out)
    print(path, len(out), "bytes")


if __name__ == "__main__":
    # an optional second argument: just one page ("1" or "2")
    write(sys.argv[1] if len(sys.argv) > 1 else "sample-site-plan.pdf", tuple(int(x) for x in sys.argv[2].split(",")) if len(sys.argv) > 2 else (1, 2))
