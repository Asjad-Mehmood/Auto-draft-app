"""Opens a DXF the way a CAD program would and checks it (ezdxf's reader and auditor), then
optionally draws it to a PNG to look at.

  python3 tool/check_dxf.py drawing.dxf [picture.png] [--expect-lines N] [--expect-inserts N]

Exits 1 when the file can't be read, the auditor finds errors, or the counts differ.
"""
import sys
import ezdxf
from ezdxf import recover

args = sys.argv[1:]
path = args.pop(0)
png = args.pop(0) if args and not args[0].startswith("--") else None
expect = {}
while args:
    k = args.pop(0)
    expect[k] = int(args.pop(0))

doc, auditor = recover.readfile(path)
if auditor.has_errors:
    for e in auditor.errors:
        print("ERROR", e.message)
    sys.exit(1)
fixes = [f.message for f in auditor.fixes]
msp = doc.modelspace()
counts = {}
for e in msp:
    counts[e.dxftype()] = counts.get(e.dxftype(), 0) + 1
print("version", doc.dxfversion, "| entities", counts)
print("layers", sorted(l.dxf.name for l in doc.layers))
print("blocks", sorted(b.name for b in doc.blocks if not b.name.startswith("*")))
print("auditor fixes", len(fixes), fixes[:5])
ok = doc.dxfversion == "AC1009"
for k, n in expect.items():
    t = {"--expect-lines": "POLYLINE", "--expect-inserts": "INSERT", "--expect-points": "POINT", "--expect-texts": "TEXT"}[k]
    if counts.get(t, 0) != n:
        print("FAILED", t, "count", counts.get(t, 0), "expected", n)
        ok = False
for ins in msp.query("INSERT"):
    if ins.dxf.name not in doc.blocks:
        print("FAILED insert of a missing block", ins.dxf.name)
        ok = False
for e in msp:
    if e.dxf.layer not in doc.layers:
        print("FAILED entity on an undefined layer", e.dxf.layer)
        ok = False
if png:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from ezdxf.addons.drawing import RenderContext, Frontend
    from ezdxf.addons.drawing.matplotlib import MatplotlibBackend
    fig = plt.figure(figsize=(14, 9), dpi=110)
    ax = fig.add_axes([0, 0, 1, 1])
    ctx = RenderContext(doc)
    Frontend(ctx, MatplotlibBackend(ax)).draw_layout(msp, finalize=True)
    fig.savefig(png, facecolor="#0b1220")
    print("picture", png)
print("DXF check:", "all good" if ok else "FAILED")
sys.exit(0 if ok else 1)
