"""Opens a DXF made from a PDF (tool/pdfdraft.dart) the way a CAD program would and checks it:
ezdxf's reader and auditor, AutoCAD 2000 format, every object on a defined layer with a defined
line type, every dimension's block present. Optionally draws it to a PNG to look at.

  python3 tool/check_pdf_dxf.py drawing.dxf [picture.png] [--expect DIMENSION=1 --expect HATCH=2 ...]

Exits 1 when the file can't be read, the auditor finds errors, or a count differs.
"""
import sys

import ezdxf
from ezdxf import recover

args = sys.argv[1:]
path = args.pop(0)
png = args.pop(0) if args and not args[0].startswith("--") else None
expect = {}
while args:
    if args.pop(0) == "--expect":
        k, v = args.pop(0).split("=")
        expect[k] = int(v)

doc, auditor = recover.readfile(path)
ok = True
if auditor.has_errors:
    for e in auditor.errors:
        print("ERROR", e.message)
    ok = False
audit = doc.audit()
if audit.has_errors:
    for e in audit.errors:
        print("AUDIT ERROR", e.message)
    ok = False
msp = doc.modelspace()
counts = {}
for e in msp:
    counts[e.dxftype()] = counts.get(e.dxftype(), 0) + 1
print("version", doc.dxfversion, "| entities", counts)
print("layers", sorted((l.dxf.name, l.dxf.color, l.dxf.linetype) for l in doc.layers))
print("auditor fixes", len(audit.fixes), [f.message for f in audit.fixes][:5])
if doc.dxfversion != "AC1015":
    print("FAILED version", doc.dxfversion)
    ok = False
for k, n in expect.items():
    if counts.get(k, 0) != n:
        print("FAILED", k, "count", counts.get(k, 0), "expected", n)
        ok = False
for e in msp:
    if e.dxf.layer not in doc.layers:
        print("FAILED object on an undefined layer", e.dxf.layer)
        ok = False
    lt = e.dxf.get("linetype", "BYLAYER")
    if lt.upper() not in ("BYLAYER", "BYBLOCK") and lt not in doc.linetypes:
        print("FAILED undefined line type", lt)
        ok = False
    if e.dxftype() == "DIMENSION" and e.dxf.geometry not in doc.blocks:
        print("FAILED dimension without its block", e.dxf.geometry)
        ok = False
if png:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from ezdxf.addons.drawing import Frontend, RenderContext
    from ezdxf.addons.drawing.matplotlib import MatplotlibBackend

    fig = plt.figure(figsize=(14, 10))
    ax = fig.add_axes([0, 0, 1, 1])
    Frontend(RenderContext(doc), MatplotlibBackend(ax)).draw_layout(msp)
    fig.savefig(png, dpi=90)
sys.exit(0 if ok else 1)
