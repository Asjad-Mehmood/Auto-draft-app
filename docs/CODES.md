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

| Code | Feature | Layer | Colour | Line type |
|---|---|---|---|---|
| `BB` | Bottom of bank (toe) | `TOE_OF_BANK` | 2 | dashed |
| `BLD` | Building | `BUILDING` | 140 | continuous |
| `CL` | Centre line | `CENTRE_LINE` | 6 | center |
| `CV` | Culvert / bridge | `CULVERT` | 150 | continuous |
| `DR` | Drain | `DRAIN` | 4 | continuous |
| `EP` | Edge of pavement | `PAVEMENT_EDGE` | 1 | continuous |
| `FN` | Fence | `FENCE` | 3 | dashed |
| `FP` | Footpath | `FOOTPATH` | 8 | continuous |
| `GT` | Gate | `GATE` | 30 | continuous |
| `HT` | Overhead power line | `POWER_LINE` | 1 | dashdot |
| `KB` | Kerb | `KERB` | 30 | continuous |
| `NL` | Nala / canal edge | `NALA` | 4 | continuous |
| `PB` | Plot boundary | `PLOT_BOUNDARY` | 6 | dashdot |
| `PIPE` | Pipe line | `PIPE` | 4 | hidden |
| `RE` | Road edge | `ROAD_EDGE` | 1 | continuous |
| `RLY` | Railway | `RAILWAY` | 8 | dashdot |
| `SH` | Shoulder | `SHOULDER` | 40 | dashed |
| `TB` | Top of bank | `TOP_OF_BANK` | 2 | continuous |
| `TRK` | Track / kacha road | `TRACK` | 42 | dashed |
| `WE` | Water edge (pond) | `WATER_EDGE` | 4 | dashed |
| `WL` | Wall | `WALL` | 7 | continuous |

## Point codes

| Code | Feature | Layer | Colour | Symbol |
|---|---|---|---|---|
| `BM` | Benchmark | `BENCHMARK` | 6 | Benchmark |
| `CP` | Control point / station | `CONTROL` | 6 | Control point |
| `EPL` | Electric pole | `ELECTRIC_POLE` | 1 | Electric pole |
| `HP` | Hand pump | `HAND_PUMP` | 4 | Hand pump |
| `KM` | Kilometre stone | `KM_STONE` | 7 | Kilometre stone |
| `LP` | Light pole | `LIGHT_POLE` | 2 | Light pole |
| `MH` | Manhole | `MANHOLE` | 4 | Manhole |
| `NGL` | Natural ground level | `SPOT_LEVEL` | 8 | Spot level |
| `SB` | Sign board | `SIGN` | 2 | Sign board |
| `SP` | Spot level | `SPOT_LEVEL` | 8 | Spot level |
| `TBM` | Temporary benchmark | `BENCHMARK` | 6 | Benchmark |
| `TF` | Transformer | `TRANSFORMER` | 1 | Transformer |
| `TP` | Telephone pole | `TELEPHONE_POLE` | 30 | Telephone pole |
| `TR` | Tree | `TREE` | 3 | Tree |
| `TW` | Tubewell | `TUBEWELL` | 4 | Tubewell |
| `VLV` | Valve | `VALVE` | 4 | Valve |
| `WEL` | Well | `WELL` | 4 | Well |

## Other layers

`POINTS` (a point at every survey point, at its level), `LEVELS` (level text), `POINT_NUMBERS` and
`POINT_CODES` (when switched on in the settings) and `UNKNOWN_CODES` (points whose code isn't in the list).

Colours are AutoCAD colour numbers (1 red, 2 yellow, 3 green, 4 cyan, 5 blue, 6 magenta, 7 white/black,
8 grey). Your own list: Codes tab → Save this list, edit, Load a code list.
