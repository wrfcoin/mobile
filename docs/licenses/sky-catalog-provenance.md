# Sky View catalog

Built by `scripts/sky_catalog/build_sky_catalog.py` into `assets/sky/sky_catalog.bin`. The script pins
each source by commit and SHA-256. The app reads the asset offline and never fetches any of this.

## Stars: Bright Star Catalogue, 5th Revised Ed.

- Original: Hoffleit and Warren (1991), NSSDC/ADC, CDS catalog V/50. J2000 mean equatorial coordinates.
- Source: https://raw.githubusercontent.com/brettonw/YaleBrightStarCatalog/abffb3b7223ae37e879b0a3ff5b49ad06aed5576/bsc5.json
- SHA256: 08b019f560a20fdf67565604b2ad04c3e40938f71a4a7c187af2b88fad1a6e8b
- License of this conversion: MIT, see yale-bsc5-MIT.txt.
- Upstream terms: the catalog's own ReadMe (tdc-www.harvard.edu/catalogs/bsc5.readme, read 2026-11-01)
  states no copyright, license or restriction. The CDS terms page could not be reached that day.
- Selection: visual magnitude <= 6.0, plus the 2 fainter stars (HR 3474, HR 5328) a constellation figure
  uses: 5,082 of 9,096. Sorted brightest first.
- Omitted: proper motion. It is small at this precision (the fastest stars move about 2 arcminutes since J2000).
- A star's constellation comes from its Bayer or Flamsteed name. A star with neither gets one from
  the boundaries below. They disagree for 2 named stars (HR 7724, HR 695), and the name is kept.

`lib/features/sky_view/data/bright_stars.dart` stays as the named subset: magnitude <= 2.5 from
bsc5-short.json at the same commit, SHA256 94b0581379ef9ea49f1ce664734a06d2fbbff2d7487f926acad3e9ef0960e0d8.

## Constellations: d3-celestial

- Source: https://github.com/ofrohn/d3-celestial at commit 7e720a3de062059d4c5400a379146a601d9010e0,
  files data/constellations.lines.json, constellations.json, constellations.bounds.json. Hashes in the script.
- License: BSD 3-Clause, see d3-celestial-BSD.txt.
- It cites the IAU constellation pages for the figures, with line changes by its author, and Davenhall and
  Leggett (1989), VizieR VI/49, for the boundaries.
- The figures store coordinates. The script matches each of the 893 endpoints to a catalog star (worst
  match 0.0025 degrees) and stops if any is more than 0.1 degrees from one.
