# Auto Draft: plan

**One line:** the surveyor opens the day's points; Auto Draft draws the finished survey drawing (lines
joined, symbols placed, levels written, every feature on its own layer) and saves a DXF any CAD program
opens.

**Who:** surveyors and survey firms doing topographic surveys for roads, housing schemes, irrigation and
buildings. Today drafting a survey in AutoCAD takes 1–3 days; with Auto Draft about 10 minutes.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Standalone app or AutoCAD plugin | Standalone Windows app (Flutter), writing DXF | Works with every CAD program, AutoCAD LT included (RoadPro's plugin can't reach LT); same stack as Slope Calculator and the Survey Toolkit |
| DXF version | R12 (AC1009) | The one version every CAD and GIS program reads; checked with ezdxf in CI |
| Close a shape | `CLS` (not `CL`) | `CL` is the centre line code; a control word can never be a code |
| Electric pole | `EPL` | `EP` is edge of pavement |
| Engine | plain Dart, no Flutter | the same code runs in the app, on the command line and in tests |
| Lines | flat by default, 3D as a setting | most drawings are flat; Civil 3D users want levels on the lines |

## Phases

1. **Core (done in this first version).** Import CSV/TXT/Excel with column guessing; the code list
   (38 codes); lines by code and number with `ST`, `END`, `CLS`, `RECT`, `ARC`/`EARC` and points on two
   lines; symbols; level, number and code text sized for the scale; checks (unknown codes, one-point lines,
   long jumps, duplicate numbers, points in one place, missing or zero levels, unsquare rectangles);
   DXF R12 writer; command-line tool; sample survey; ezdxf check in CI.
2. **Review (done).** Drawing view with zoom and pan; click a point for its card (code, E N Z, change
   code); problem list that zooms to the place, with one-click fixes for an unknown code (add it to the
   list, or change it on every point); layers on/off; points list with find, corrected codes marked;
   code editor (add, change, remove: code, name, line or point, layer, colour, line type or symbol, levels)
   checked as typed; undo and redo of every change (Ctrl+Z, Ctrl+Y, 100 steps); save the corrected points
   as CSV, and a reminder before closing with unsaved corrections; drag a file onto the window.
3. **Print-ready (done).** The sheet round the survey: paper A4–A0, landscape or portrait, or the
   smallest that fits at the scale (with advice when it doesn't fit, and one-click fixes); frame; coordinate
   grid with E/N labels (every ~100 mm on paper); a panel with the legend made from the codes used, north
   arrow, scale bar, notes and the title block (firm, title, location, client, surveyed/drawn by, date,
   drawing no., scale, sheet). In the DXF on its own layers (it prints at scale from model space), on
   screen, and as a vector PDF at scale. The firm, people, notes and paper are remembered.
4. **Total station files (done).** Opened like a CSV, with what was read and skipped shown first:
   Leica GSI-8 and GSI-16 (coordinates, or worked out from the measurements and the station; codes from
   words 71-79 or a code block), Sokkia SDR33 / SDR2x coordinate records, Nikon RAW (coordinate records,
   and side shots worked out from their station and back-sight). KML for Google Earth in the chosen UTM
   zone (remembered): lines in their colours, point features as pins, every point (off at first).
   Topcon: its CSV export already opens. Written from the formats' specifications and checked against
   files made from known coordinates; to be tried with files from the firm's own instruments.
5. **Contours (done).** The ground surface (TIN): Delaunay triangulation of the points with levels,
   leaving out codes that aren't on the ground (buildings' roofs, power lines, pipes); breaklines (road
   edges, kerbs, banks, drains, walls…) made edges of the TIN so contours bend at them; long triangles on
   the outside trimmed. Contours at a chosen or automatic interval, every 5th major and labelled along
   its line; in the DXF at their elevation (Civil 3D reads them), the TIN as 3D faces when shown; in the
   PDF, on screen, in the legend and in the KML. Each code says whether it is on the ground and whether
   it is a breakline (code editor).
6. **Launch.**
   - First release `v0.1.0` (owner's go-ahead): `AutoDraft-Setup.exe` + `latest.json` on GitHub Releases.
   - **Survey Toolkit:** add Auto Draft to the website's Toolkit feed (`lib/toolkit/feed.ts` in the website
     repository: id `auto-draft`, this repository's latest release, NSIS quiet install `/S`), so the Toolkit
     installs and updates it like the other tools. Toolkit app: its icon and description.
   - **Website:** product page `/auto-draft` (what it does, screenshots, the code guide, download with the
     "Your download is starting" notice), in the menu, Downloads and the sitemap; reviews.
   - Sign-in with the website account, as the other programs, so downloads and use show in Admin.

## How it is checked

- Engine tests: codes, lines, curves (on the circle to 1e-6 m), rectangles, every check, import formats,
  the DXF's structure (sections, every layer and block defined, ASCII only, numbers).
- App tests: open → columns → draw → save; mistakes listed and fixed; settings remembered; layers; code
  lists saved and loaded; quick fixes, the code editor's checks, undo/redo by button and Ctrl+Z, clicking
  a point, saving corrected points, the reminder before closing.
- State tests: every change undone and redone, the 100-step history, renaming and removing codes, the
  code list remembered as undone, the points CSV (quoting, read back the same).
- Sheet tests: paper choice, advice, everything on the paper, grid, legend, title block, DXF and PDF.
- CI: the sample survey becomes a DXF that ezdxf reads and audits with no errors, flat, 3D and with the
  sheet; the PDF is one A3 page (pdfinfo) and is drawn to a picture; the Windows
  program and installer are built, installed, opened (window, screenshot) and uninstalled.
