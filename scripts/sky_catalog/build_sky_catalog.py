#!/usr/bin/env python3
"""Builds assets/sky/sky_catalog.bin, the Sky View star and constellation data.

Run once at development time; the app never touches the network for this.

    python3 scripts/sky_catalog/build_sky_catalog.py <empty-download-dir>

Sources are pinned by commit and SHA-256, so a changed upstream file stops the
build rather than silently changing the sky. See
docs/licenses/sky-catalog-provenance.md.

File layout (little endian), read by lib/features/sky_view/data/sky_star_catalog.dart:
  'WSKY', u16 version, u16 stars, u16 segments, u16 constellations, u16 labels, u16 polygons
  stars, brightest first: u16 hr[], f32 ra[], f32 dec[], i16 mag*100[], u8 constellation[],
    then for each star u8 length + UTF-8 designation
  constellations: 3 ASCII abbreviation, u8 length + UTF-8 name
  labels: u8 constellation, f32 ra, f32 dec, u8 length + UTF-8 name
  segments: u16 star a, u16 star b, u8 constellation
  polygons: u8 constellation, u16 points, then f32 ra, f32 dec per point
All angles are J2000 degrees, ra in [0, 360).
"""
import hashlib
import json
import math
import os
import re
import struct
import sys
import urllib.request

BSC_COMMIT = "abffb3b7223ae37e879b0a3ff5b49ad06aed5576"
D3_COMMIT = "7e720a3de062059d4c5400a379146a601d9010e0"
BSC = f"https://raw.githubusercontent.com/brettonw/YaleBrightStarCatalog/{BSC_COMMIT}"
D3 = f"https://raw.githubusercontent.com/ofrohn/d3-celestial/{D3_COMMIT}"
SOURCES = {
    "bsc5.json": (f"{BSC}/bsc5.json", "08b019f560a20fdf67565604b2ad04c3e40938f71a4a7c187af2b88fad1a6e8b"),
    "lines.json": (f"{D3}/data/constellations.lines.json", "294f66bef5d5cf50b1e17f16d2efa1d97a15131612c68dd935adef6e7373e13c"),
    "names.json": (f"{D3}/data/constellations.json", "ab4ae692027cbc042c0d6791a84456a65eb7c55656107fd00c58ff6e55d4d8b2"),
    "bounds.json": (f"{D3}/data/constellations.bounds.json", "f2e2687af6b20b24567879f838c21874d412efcc93ecc1966be07e78431cc196"),
}
MAGNITUDE_LIMIT = 6.0
MATCH_DEGREES = 0.1
GREEK = dict(
    Alp="α", Bet="β", Gam="γ", Del="δ", Eps="ε", Zet="ζ", Eta="η", The="θ",
    Iot="ι", Kap="κ", Lam="λ", Mu="μ", Nu="ν", Xi="ξ", Omi="ο", Pi="π",
    Rho="ρ", Sig="σ", Tau="τ", Ups="υ", Phi="φ", Chi="χ", Psi="ψ", Ome="ω",
)
SUPERSCRIPT = {"1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"}


def fetch(folder):
    loaded = {}
    for name, (url, want) in SOURCES.items():
        path = os.path.join(folder, name)
        if not os.path.exists(path):
            urllib.request.urlretrieve(url, path)
        with open(path, "rb") as f:
            raw = f.read()
        got = hashlib.sha256(raw).hexdigest()
        if got != want:
            sys.exit(f"{name}: expected sha256 {want}, got {got}")
        loaded[name] = json.loads(raw)
    return loaded


def parse_ra(text):
    m = re.fullmatch(r"(\d+)h\s*(\d+)m\s*([\d.]+)s", text.strip())
    return (int(m[1]) + int(m[2]) / 60 + float(m[3]) / 3600) * 15


def parse_dec(text):
    m = re.fullmatch(r"([+-])(\d+)°\s*(\d+)′\s*(\d+)″", text.strip())
    value = int(m[2]) + int(m[3]) / 60 + int(m[4]) / 3600
    return -value if m[1] == "-" else value


def unit(ra, dec):
    r, d = math.radians(ra), math.radians(dec)
    return (math.cos(d) * math.cos(r), math.cos(d) * math.sin(r), math.sin(d))


def designation(name, hr):
    """'58Alp Ori' becomes '58 α Ori'; a star with no such name keeps its HR number."""
    if not name:
        return f"HR {hr}"
    text = name.rjust(10)
    flamsteed, bayer, index, constellation = text[:3].strip(), text[3:6].strip(), text[6].strip(), text[7:10]
    letter = GREEK.get(bayer, bayer) + SUPERSCRIPT.get(index, index)
    return " ".join(part for part in (flamsteed, letter, constellation) if part)


def rings(feature):
    geometry = feature["geometry"]
    if geometry["type"] != "Polygon":
        sys.exit(f"{feature['id']}: unexpected boundary type {geometry['type']}")
    return geometry["coordinates"]


def contains(polygon, ra, dec):
    """Same rule as the app: a meridian ray north, flipped for the polygon around the north pole."""
    inside = False
    winding = 0.0
    for (ra1, dec1), (ra2, dec2) in zip(polygon, polygon[1:] + polygon[:1]):
        step = (ra2 - ra1 + 180) % 360 - 180
        winding += step
        offset = (ra - ra1 + 180) % 360 - 180
        if (step > 0 and 0 <= offset < step) or (step < 0 and step <= offset < 0):
            if dec1 + (dec2 - dec1) * offset / step > dec:
                inside = not inside
    if abs(winding) > 180 and sum(p[1] for p in polygon) > 0:
        inside = not inside
    return inside


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    folder = sys.argv[1]
    os.makedirs(folder, exist_ok=True)
    data = fetch(folder)
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    # Constellations, in the source's order, one per abbreviation.
    abbreviations, names, labels = [], {}, []
    for feature in data["names.json"]["features"]:
        abbreviation = feature["id"]
        label = feature["properties"]["name"]
        if abbreviation not in names:
            abbreviations.append(abbreviation)
            # Serpens has two parts with their own labels and one name.
            names[abbreviation] = "Serpens" if abbreviation == "Ser" else label
        lon, lat = feature["geometry"]["coordinates"]
        labels.append((abbreviation, lon % 360, lat, label))
    if len(abbreviations) != 88:
        sys.exit(f"expected 88 constellations, got {len(abbreviations)}")
    index = {a: i for i, a in enumerate(abbreviations)}

    polygons = []
    for feature in data["bounds.json"]["features"]:
        for ring in rings(feature):
            points = [(lon % 360, lat) for lon, lat in ring]
            if points[0] == points[-1]:
                points.pop()
            polygons.append((feature["id"], points))
    if {p[0] for p in polygons} != set(abbreviations):
        sys.exit("boundary constellations differ from the name list")

    source = []
    for row in data["bsc5.json"]:
        ra, dec, mag = parse_ra(row["RA"]), parse_dec(row["Dec"]), float(row["Vmag"])
        source.append(dict(hr=int(row["HR"]), ra=ra, dec=dec, mag=mag, name=row.get("Name", ""), unit=unit(ra, dec)))

    # Every figure endpoint must be a real catalog star, even a slightly faint one.
    segments, needed, worst, longest = [], set(), 0.0, 0.0
    for feature in data["lines.json"]["features"]:
        for line in feature["geometry"]["coordinates"]:
            matched = []
            for lon, lat in line:
                u = unit(lon % 360, lat)
                best = max(source, key=lambda s: sum(a * b for a, b in zip(u, s["unit"])))
                gap = math.degrees(math.acos(min(1, sum(a * b for a, b in zip(u, best["unit"])))))
                if gap > MATCH_DEGREES:
                    sys.exit(f"{feature['id']}: endpoint {lon},{lat} is {gap:.3f} deg from any catalog star")
                worst = max(worst, gap)
                needed.add(best["hr"])
                matched.append(best)
            for a, b in zip(matched, matched[1:]):
                dot = sum(p * q for p, q in zip(a["unit"], b["unit"]))
                longest = max(longest, math.degrees(math.acos(min(1, dot))))
                segments.append((a["hr"], b["hr"], feature["id"]))

    stars = sorted(
        (s for s in source if s["mag"] <= MAGNITUDE_LIMIT or s["hr"] in needed),
        key=lambda s: (s["mag"], s["hr"]),
    )
    position = {s["hr"]: i for i, s in enumerate(stars)}

    # Bayer or Flamsteed names state the constellation; the rest come from the boundaries.
    disagreements = []
    for star in stars:
        hits = [c for c, points in polygons if contains(points, star["ra"], star["dec"])]
        named = star["name"][-3:] if star["name"] else None
        star["constellation"] = named or (hits[0] if hits else None)
        if star["constellation"] not in index:
            sys.exit(f"HR {star['hr']}: no constellation")
        if named and hits and named != hits[0]:
            disagreements.append((star["hr"], named, hits[0]))

    out = bytearray(b"WSKY")
    out += struct.pack("<6H", 1, len(stars), len(segments), len(abbreviations), len(labels), len(polygons))
    for s in stars:
        out += struct.pack("<H", s["hr"])
    for s in stars:
        out += struct.pack("<f", s["ra"])
    for s in stars:
        out += struct.pack("<f", s["dec"])
    for s in stars:
        out += struct.pack("<h", round(s["mag"] * 100))
    for s in stars:
        out.append(index[s["constellation"]])

    def text(value):
        raw = value.encode()
        return bytes([len(raw)]) + raw

    for s in stars:
        out += text(designation(s["name"], s["hr"]))
    for a in abbreviations:
        out += a.encode("ascii") + text(names[a])
    for a, ra, dec, label in labels:
        out.append(index[a])
        out += struct.pack("<ff", ra, dec) + text(label)
    for a, b, c in segments:
        out += struct.pack("<HHB", position[a], position[b], index[c])
    for c, points in polygons:
        out += struct.pack("<BH", index[c], len(points))
        for ra, dec in points:
            out += struct.pack("<ff", ra, dec)
    target = os.path.join(root, "assets/sky/sky_catalog.bin")
    with open(target, "wb") as f:
        f.write(out)

    # Raw source rows and figures for the accuracy tests, untouched.
    fixtures = os.path.join(root, "test/features/sky_view/fixtures")
    keep = {424, 2061, 7001, 2491, 5340}
    rows = [r for i, r in enumerate(data["bsc5.json"]) if int(r["HR"]) in keep or (i % 37 == 0 and float(r["Vmag"]) <= MAGNITUDE_LIMIT)]
    with open(os.path.join(fixtures, "bsc5_sample.json"), "w", encoding="utf-8") as f:
        json.dump([{k: r[k] for k in ("HR", "RA", "Dec", "Vmag", "Name") if k in r} for r in rows], f, ensure_ascii=False, indent=0)
        f.write("\n")
    with open(os.path.join(fixtures, "constellation_lines_source.json"), "w") as f:
        json.dump([[x["id"], x["geometry"]["coordinates"]] for x in data["lines.json"]["features"]], f, separators=(",", ":"))
        f.write("\n")

    print(f"stars {len(stars)} (limit {MAGNITUDE_LIMIT}, {sum(1 for s in stars if s['mag'] > MAGNITUDE_LIMIT)} fainter figure stars)")
    print(f"constellations {len(abbreviations)}, labels {len(labels)}, segments {len(segments)}, polygons {len(polygons)}")
    print(f"worst endpoint match {worst:.4f} deg, longest segment {longest:.1f} deg")
    print(f"named constellation vs boundary disagreements: {len(disagreements)} {disagreements}")
    print(f"asset {len(out)} bytes, sample rows {len(rows)}")


if __name__ == "__main__":
    main()
