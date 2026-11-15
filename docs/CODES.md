# Auto Draft: field codes

<!-- Made by tool/codes_doc.dart from lib/src/engine/codes.dart. Edit those, not this file. -->

Type the code in the total station's code field. Upper or lower case; words are separated by spaces
(commas, semicolons and slashes work too).

## Lines and their number

Points with the same **line code and number** are joined into one line, in the order they were
surveyed: `RE1` is road edge 1, `RE2` road edge 2. A code without a number (`RE`) is line 0.
Lines can be surveyed mixed together: `RE1`, `RE2`, `RE1`, `RE2`… still makes two lines.

## Control words

Written after the code they steer.

| Word | Example | What it does |
|---|---|---|
| `ST` (or `START`) | `RE1 ST` | Starts a new line here; the line before it ends |
| `END` | `RE1 END` | This is the line's last point |
| `CLS` (or `CLOSE`) | `BLD1 CLS` | Closes the shape back to its first point |
| `RECT` | `BLD2 RECT` | On the 3rd corner: the 4th corner is added (a rectangle) and the shape closed |
| `ARC` | `WL1 ARC` | A curve starts here |
| `EARC` (or `ENDARC`) | `WL1 EARC` | The curve ends here; `EARC ARC` starts the next curve at once |

A point can be on two lines: `WL1 GT1` is on wall 1 and gate 1. A word that is neither a code nor a
control word is kept as a remark (`TR NEEM`). Three points make a curve as a circular arc; more points
a smooth curve through every one.

## Line codes

| Code | Feature | Layer | Colour | Line type | Contours |
|---|---|---|---|---|---|
| `BB` | Bottom of bank (toe) | `TOE_OF_BANK` | 2 | dashed | breakline |
| `BLD` | Building | `BUILDING` | 140 | continuous | left out (not on the ground) |
| `CL` | Centre line | `CENTRE_LINE` | 6 | center | breakline |
| `CV` | Culvert / bridge | `CULVERT` | 150 | continuous | points used |
| `DR` | Drain | `DRAIN` | 4 | continuous | breakline |
| `EP` | Edge of pavement | `PAVEMENT_EDGE` | 1 | continuous | breakline |
| `FN` | Fence | `FENCE` | 3 | dashed | points used |
| `FP` | Footpath | `FOOTPATH` | 8 | continuous | breakline |
| `GT` | Gate | `GATE` | 30 | continuous | points used |
| `HT` | Overhead power line | `POWER_LINE` | 1 | dashdot | left out (not on the ground) |
| `KB` | Kerb | `KERB` | 30 | continuous | breakline |
| `NL` | Nala / canal edge | `NALA` | 4 | continuous | breakline |
| `PB` | Plot boundary | `PLOT_BOUNDARY` | 6 | dashdot | points used |
| `PIPE` | Pipe line | `PIPE` | 4 | hidden | left out (not on the ground) |
| `RE` | Road edge | `ROAD_EDGE` | 1 | continuous | breakline |
| `RLY` | Railway | `RAILWAY` | 8 | dashdot | points used |
| `SH` | Shoulder | `SHOULDER` | 40 | dashed | breakline |
| `TB` | Top of bank | `TOP_OF_BANK` | 2 | continuous | breakline |
| `TRK` | Track / kacha road | `TRACK` | 42 | dashed | breakline |
| `WE` | Water edge (pond) | `WATER_EDGE` | 4 | dashed | breakline |
| `WL` | Wall | `WALL` | 7 | continuous | breakline |

## Point codes

| Code | Feature | Layer | Colour | Symbol | Contours |
|---|---|---|---|---|---|
| `BM` | Benchmark | `BENCHMARK` | 6 | Benchmark | points used |
| `CP` | Control point / station | `CONTROL` | 6 | Control point | points used |
| `EPL` | Electric pole | `ELECTRIC_POLE` | 1 | Electric pole | points used |
| `HP` | Hand pump | `HAND_PUMP` | 4 | Hand pump | points used |
| `KM` | Kilometre stone | `KM_STONE` | 7 | Kilometre stone | points used |
| `LP` | Light pole | `LIGHT_POLE` | 2 | Light pole | points used |
| `MH` | Manhole | `MANHOLE` | 4 | Manhole | points used |
| `NGL` | Natural ground level | `SPOT_LEVEL` | 8 | Spot level | points used |
| `SB` | Sign board | `SIGN` | 2 | Sign board | points used |
| `SP` | Spot level | `SPOT_LEVEL` | 8 | Spot level | points used |
| `TBM` | Temporary benchmark | `BENCHMARK` | 6 | Benchmark | points used |
| `TF` | Transformer | `TRANSFORMER` | 1 | Transformer | points used |
| `TP` | Telephone pole | `TELEPHONE_POLE` | 30 | Telephone pole | points used |
| `TR` | Tree | `TREE` | 3 | Tree | points used |
| `TW` | Tubewell | `TUBEWELL` | 4 | Tubewell | points used |
| `VLV` | Valve | `VALVE` | 4 | Valve | points used |
| `WEL` | Well | `WELL` | 4 | Well | points used |

## Other layers

`POINTS` (a point at every survey point, at its level), `LEVELS` (level text), `POINT_NUMBERS` and
`POINT_CODES` (when switched on in the settings) and `UNKNOWN_CODES` (points whose code isn't in the list).

Colours are AutoCAD colour numbers (1 red, 2 yellow, 3 green, 4 cyan, 5 blue, 6 magenta, 7 white/black,
8 grey). Your own list: Codes tab → Save this list, edit, Load a code list.
