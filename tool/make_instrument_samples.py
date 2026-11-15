"""Writes test/fixtures/*: the first points of the sample survey in instrument formats, so the readers
can be checked against known coordinates.

  sample-16.gsi     Leica GSI-16, coordinates (81 82 83) and codes (71)
  sample-8.gsi      Leica GSI-8, coordinates in mm, a code block (41) before a point
  sample-obs.gsi    Leica GSI-16, a station (84 85 86 88) and measurements (21 22 31 87)
  sample.sdr        Sokkia SDR33, 16-character records (08KI)
  sample-short.sdr  Sokkia SDR2x, 4-character point numbers
  sample.raw        Nikon RAW: a station point (MP), the station (ST) and side shots (SS)

Run: python3 tool/make_instrument_samples.py
"""
import csv, math, os

def code_words(code, w):
    # GSI words hold no spaces: the code in 71, a control word (ST, CLS…) in 72
    parts = code.split()
    return "".join(w(71 + i, "....", p) for i, p in enumerate(parts[:2]))

here = os.path.dirname(__file__)
rows = list(csv.reader(open(os.path.join(here, "..", "assets", "samples", "sample-survey.csv"))))[1:13]
pts = [(r[0], float(r[1]), float(r[2]), float(r[3]), r[4]) for r in rows]
out = os.path.join(here, "..", "test", "fixtures")
os.makedirs(out, exist_ok=True)

def w16(wi, info, value):
    s = str(value)
    return "%02d%s%s%s " % (wi, info, "-" if s.startswith("-") else "+", s.lstrip("-").rjust(16, "0"))

def w8(wi, info, value):
    s = str(value)
    return "%02d%s%s%s " % (wi, info, "-" if s.startswith("-") else "+", s.lstrip("-").rjust(8, "0")[-8:])

# GSI-16 coordinates, 1/10 mm (unit 6)
with open(os.path.join(out, "sample-16.gsi"), "w", newline="") as f:
    for i, (pid, e, n, z, code) in enumerate(pts):
        f.write(("*" + w16(11, "%04d" % (i + 1), pid) + w16(81, "..16", round(e * 1e4)) + w16(82, "..16", round(n * 1e4))
                + w16(83, "..16", round(z * 1e4)) + code_words(code, w16)).rstrip() + "\r\n")

# GSI-8: easting and northing too long for 8 digits in mm, so a local grid (minus 436000 / 3487000)
with open(os.path.join(out, "sample-8.gsi"), "w", newline="") as f:
    for i, (pid, e, n, z, code) in enumerate(pts[:6]):
        if i == 2:
            f.write(w8(41, "0003", code.split()[0]).rstrip() + "\r\n")  # a code block before point 3
        words = w8(11, "%04d" % (i + 1), pid) + w8(81, "..10", round((e - 436000) * 1000)) + w8(82, "..10", round((n - 3487000) * 1000)) + w8(83, "..10", round(z * 1000))
        if i != 2:
            words += code_words(code, w8)
        f.write(words.rstrip() + "\r\n")

# GSI-16 measurements from a station at the benchmark (point 1), 1.500 instrument, 1.600 target
sid, se, sn, sz, _ = pts[0]
hi, hr = 1.5, 1.6
with open(os.path.join(out, "sample-obs.gsi"), "w", newline="") as f:
    f.write("*" + w16(11, "0001", sid) + w16(84, "..18", round(se * 1e5)) + w16(85, "..18", round(sn * 1e5))
            + w16(86, "..18", round(sz * 1e5)) + w16(88, "..18", round(hi * 1e5)).rstrip() + "\r\n")
    for i, (pid, e, n, z, code) in enumerate(pts[1:], start=2):
        de, dn = e - se, n - sn
        hd = math.hypot(de, dn)
        dz = z - (sz + hi - hr)
        sd = math.hypot(hd, dz)
        hz = (math.degrees(math.atan2(de, dn)) + 360) % 360
        v = math.degrees(math.atan2(hd, dz))
        f.write(("*" + w16(11, "%04d" % i, pid) + w16(21, ".107", round(hz * 1e6)) + w16(22, ".107", round(v * 1e6))
                + w16(31, "..08", round(sd * 1e5)) + w16(87, "..18", round(hr * 1e5)) + code_words(code, w16)).rstrip() + "\r\n")

# Sokkia SDR33 (16-character fields: N, E, Z)
with open(os.path.join(out, "sample.sdr"), "w", newline="") as f:
    f.write("00NMSDR33 V04-04.02     15-Nov-26 10:00 113111\r\n")
    for pid, e, n, z, code in pts:
        f.write("08KI" + pid.ljust(16) + ("%.4f" % n).rjust(16) + ("%.4f" % e).rjust(16) + ("%.4f" % z).rjust(16) + code.ljust(16) + "\r\n")
    f.write("09F1" + "0001".ljust(16) + "0002".ljust(16) + "   45.3210000   90.1000000   10.0000000\r\n")

# Sokkia SDR2x (4-character numbers, 10-character values)
with open(os.path.join(out, "sample-short.sdr"), "w", newline="") as f:
    f.write("00NMSDR20 V03-05\r\n")
    for pid, e, n, z, code in pts[:5]:
        f.write("08KI" + pid.rjust(4) + ("%.3f" % (n - 3487000)).rjust(10) + ("%.3f" % (e - 436000)).rjust(10) + ("%.3f" % z).rjust(10) + code.ljust(16) + "\r\n")

def dms(deg):
    d = int(deg); m = int((deg - d) * 60); s = (deg - d - m / 60) * 3600
    if s >= 59.995: m += 1; s = 0
    if m == 60: d += 1; m = 0
    return "%d.%02d%02d" % (d, m, round(s))

# Nikon RAW: station = point 1, back-sight azimuth 45°00'00" at HA 0
with open(os.path.join(out, "sample.raw"), "w", newline="") as f:
    f.write("CO,Nikon RAW data format V2.00\r\nCO,Units: Angle:DDDMMSS Distance:Metres\r\n")
    f.write("MP,%s,,%.4f,%.4f,%.4f,TBM\r\n" % (sid, sn, se, sz))
    f.write("ST,%s,,BS1,,%.3f,45.0000,0.0000\r\n" % (sid, hi))
    for pid, e, n, z, code in pts[1:]:
        de, dn = e - se, n - sn
        hd = math.hypot(de, dn)
        dz = z - (sz + hi - hr)
        sd = math.hypot(hd, dz)
        az = (math.degrees(math.atan2(de, dn)) + 360) % 360
        ha = (az - 45 + 360) % 360
        va = math.degrees(math.atan2(hd, dz))
        f.write("SS,%s,%.3f,%.4f,%s,%s,10:00:00,%s\r\n" % (pid, hr, sd, dms(ha), dms(va), code))
print("wrote", sorted(os.listdir(out)))
