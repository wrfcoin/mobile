# Offline geometric rise/set estimates

Refs #341, #398. This adds the next small story after #383: tapped Sky View
objects show approximate horizon-crossing times over the next 24 hours.
The UTC date is included because the next event can fall tomorrow.

The existing [NASA/JPL approximate planetary model](https://ssd.jpl.nasa.gov/planets/approx_pos.html)
supplies each solar body's position at every evaluated time; catalog stars
retain J2000 positions. Both go through existing precession and horizontal
coordinate transforms. No new data, packages or license material is added.

The original numerical search samples geometric altitude at one-minute
intervals and bisects sign changes to sub-second numerical resolution.
Displayed times stop at minutes: numerical resolution does not establish
observational accuracy. Latitude/longitude come only from the existing 0.1°
coarse cell. The complete 24-hour window must stay within 1800–2050; otherwise
details say unavailable. Missing crossings say "Not found in next 24h" and
never supply midnight defaults or assert permanent circumpolar status.
Short grazing excursions between samples may be missed, which details disclose.

This searches the object's centre at the flat, zero-degree geometric horizon.
It includes neither atmospheric refraction, solar limb, terrain nor observer
elevation, and provides no twilight or physical visibility guarantee.
[NOAA's calculation notes](https://gml.noaa.gov/grad/solcalc/calcdetails.html)
distinguish observed sunrise/sunset using a refraction correction from this
geometric convention. The existing model is approximate; these are planning
estimates, without telescope or navigation claims.

Computation happens only on a details tap; it uses no HTTP, new location read,
storage or background timer. The existing sensor/permission/lifecycle rules
still control which objects can be selected. Moon, constellation lines,
camera and feed-backed objects remain separate phase-1/future stories.

Evidence: actual AR route details fail on unchanged main when horizon labels
are required. Analytic J2000 fixed-star quarter/three-quarter sidereal-day and
east-longitude references check direction and timing independently. Polar
no-event, moving-Sun crossing, coarse-cell equivalence, UTC and range controls
cover the pure calculator. Mounted Sirius details retain the HTTP-denying
transport. Local tests establish source behavior, not physical device accuracy.
