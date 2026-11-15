"""Writes assets/samples/sample-survey.csv: a small made-up topographic survey in field order.

A road with a curve (RE1 / RE2, ARC ... EARC), its centre line, a drain and a fence; a plot with a
boundary wall and a gate, two buildings (one closed with CLS, one finished from 3 corners with
RECT), trees, poles, manholes, a hand pump, a benchmark and spot levels. Coordinates are UTM metres
near Lahore. Run: python3 tool/make_sample.py
"""
import math, os

E0, N0 = 436200.0, 3487400.0
rows = []

def pt(x, y, z, code):
    rows.append((len(rows) + 1, round(E0 + x, 3), round(N0 + y, 3), round(z, 3), code))

def road_z(x, off):  # 0.2 % fall along the road, 2.5 % crossfall from the centre
    return 214.60 - 0.002 * x - 0.025 * abs(off)

def edge(off, code):
    for x in (0, 20, 40, 60, 80):
        c = code + (" ST" if x == 0 else "") + (" ARC" if x == 80 else "")
        pt(x, off, road_z(x, off), c)
    # the curve: centre at (80, 60), turning left
    r = 60 - off
    for i, a in enumerate((15, 30)):
        t = math.radians(-90 + a)
        pt(80 + r * math.cos(t), 60 + r * math.sin(t), road_z(80 + a / 2, off), code + (" EARC" if a == 30 else ""))
    t = math.radians(-60)
    x1, y1 = 80 + r * math.cos(t), 60 + r * math.sin(t)
    # straight on along the tangent
    pt(x1 + 20 * math.cos(math.radians(30)), y1 + 20 * math.sin(math.radians(30)), road_z(120, off), code + " END")

pt(2, 2, 214.250, "TBM")
edge(0.0, "RE1")
edge(-7.3, "RE2")
for x in (0, 20, 40, 60, 80):
    pt(x, -3.65, road_z(x, 0) + 0.0, "CL")
pt(30, -3.65, road_z(30, 0) - 0.01, "MH")
pt(70, -3.65, road_z(70, 0) - 0.01, "MH")
for x in (0, 20, 40, 60, 80):
    pt(x, -9.5, 213.70 - 0.002 * x, "DR1")
for x in (0, 20, 40, 60, 80):
    pt(x, -14, 213.95 - 0.001 * x, "FN1")
for x in (10, 45, 80):
    pt(x, 2, 214.40, "EPL")
# the plot: wall from the gate, round, back to the gate
pt(40, 4, 214.45, "WL1 ST GT1")
pt(12, 4, 214.44, "WL1")
pt(12, 26, 214.52, "WL1")
pt(72, 26, 214.48, "WL1")
pt(72, 4, 214.41, "WL1")
pt(46, 4, 214.44, "WL1 END GT1")
for x, y in ((20, 8), (38, 8), (38, 20), (20, 20)):
    pt(x, y, 214.75, "BLD1" + (" CLS" if (x, y) == (20, 20) else ""))
pt(50, 10, 214.78, "BLD2")
pt(64, 10, 214.78, "BLD2")
pt(64, 19, 214.78, "BLD2 RECT")
pt(66, 22, 214.50, "HP")
for x, y in ((5, 12), (8, 30), (78, 12), (90, -20), (30, -18), (60, -17)):
    pt(x, y, 214.1 if y > 0 else 213.6, "TR")
for x in (0, 20, 40, 60, 80):
    pt(x, -25, 213.40 - 0.003 * x, "SP")
for x in (0, 20, 40, 60, 85):
    pt(x, 35, 214.30 - 0.002 * x, "SP")

out = os.path.join(os.path.dirname(__file__), "..", "assets", "samples", "sample-survey.csv")
with open(out, "w", newline="") as f:
    f.write("Point,Easting,Northing,Level,Code\r\n")
    for r in rows:
        f.write("%d,%.3f,%.3f,%.3f,%s\r\n" % r)
print("wrote", len(rows), "points to", os.path.normpath(out))
