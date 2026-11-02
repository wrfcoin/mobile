#!/usr/bin/env python3
"""Regenerates horizons_altaz.json and horizons_moon.json from JPL Horizons.

Horizons output only: nothing here comes from the code under test.
Usage: python3 fetch_horizons_altaz.py <output directory>
"""
import json
import re
import sys
import urllib.parse
import urllib.request

API = "https://ssd.jpl.nasa.gov/api/horizons.api"
BODIES = {"Sun": "10", "Moon": "301", "Venus": "299", "Mars": "499",
          "Jupiter": "599", "Saturn": "699"}
# Longitude east, latitude north, kilometres above the ellipsoid. Both sit
# exactly on the app's 0.1 degree grid.
SITES = {"north": (-122.4, 37.8), "south": (151.2, -33.9)}
ALTAZ_JDS = [2461055.75, 2461345.6666666665, 2461577.9166666665,
             2461833.0, 2462502.5]
MOON_JDS = [2461041.5 + i * 13.37 for i in range(28)]


def call(params):
    query = urllib.parse.urlencode(
        {"format": "text", "MAKE_EPHEM": "YES", "OBJ_DATA": "NO",
         "EPHEM_TYPE": "OBSERVER", "ANG_FORMAT": "DEG", "CSV_FORMAT": "YES",
         "CAL_FORMAT": "JD", **params}, safe="'@,")
    text = urllib.request.urlopen(f"{API}?{query}", timeout=60).read().decode()
    block = re.search(r"\$\$SOE\n(.*?)\$\$EOE", text, re.S)
    if not block:
        raise SystemExit(text[:2000])
    return [[c.strip() for c in row.split(",")]
            for row in block.group(1).strip().splitlines()]


def tlist(jds):
    return "'" + ",".join(f"{jd:.9f}" for jd in jds) + "'"


def main(out):
    altaz = {}
    for site, (lon, lat) in SITES.items():
        altaz[site] = {"latitude": lat, "longitude": lon, "bodies": {}}
        for name, code in BODIES.items():
            rows = call({"COMMAND": f"'{code}'", "CENTER": "'coord@399'",
                         "COORD_TYPE": "'GEODETIC'",
                         "SITE_COORD": f"'{lon},{lat},0'",
                         "TLIST": tlist(ALTAZ_JDS), "QUANTITIES": "'4'",
                         "APPARENT": "'AIRLESS'"})
            altaz[site]["bodies"][name] = [
                [float(r[0]), float(r[3]), float(r[4])] for r in rows]
    with open(f"{out}/horizons_altaz.json", "w") as f:
        json.dump(altaz, f, indent=1)
    rows = call({"COMMAND": "'301'", "CENTER": "'500@399'",
                 "TLIST": tlist(MOON_JDS), "QUANTITIES": "'1'"})
    with open(f"{out}/horizons_moon.json", "w") as f:
        json.dump([[float(r[0]), float(r[3]), float(r[4])] for r in rows],
                  f, indent=1)


if __name__ == "__main__":
    main(sys.argv[1])
