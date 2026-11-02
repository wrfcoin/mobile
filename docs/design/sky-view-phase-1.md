# Offline Sky View phase 1 (Refs #341)

Superseded for the live screen by `sky-view-stage-1.md`. Kept for the data,
licensing and privacy reasoning, which still applies, except where that note
says otherwise.

Design recorded before implementation, 2026-10-02. App tier, r20; after
closed-testnet GO. The existing `/weather/ar` entry becomes a schematic sky
finder. It has no camera and makes no weather, backend or other HTTP calls.

## Delivery

1. Pure Dart astronomy: bundled bright-star subset, UTC Julian/sidereal time,
   J2000-to-date precession, horizontal coordinates and local planetary positions.
2. Integration: sensor orientation, coarse location, visible labels and details,
   calibration, unavailable states and foreground-only subscriptions.
3. Follow-on small changes: constellation lines, Moon and rise/set estimates;
   these remain incomplete until separately evidenced. Camera, satellite,
   aircraft and feed-backed weather layers are outside this contract.

## Data and licensing

Star coordinates are a bounded subset of Yale BSC5 from Bretton Wade's
MIT-licensed transformation at
https://github.com/brettonw/YaleBrightStarCatalog, revision
abffb3b7223ae37e879b0a3ff5b49ad06aed5576. Retain its full license, origin,
selection predicate, source hash and catalog identifiers. Do not claim this
transformed dataset is unlicensed or complete. Bundle as generated Dart constants
to avoid asset-loader/network ambiguity and changes to contested pubspec files.

Planet mathematics is an original implementation of the Keplerian model and
numeric Table 1 elements documented by NASA/JPL:
https://ssd.jpl.nasa.gov/planets/approx_pos.html. Its 1800–2050 validity is enforced.
Use Earth/Moon barycenter as the observer's geocentric approximation, subtract
Earth before converting to equatorial coordinates, then precess to the date.
Include Mercury through Neptune, and Sun as the negative Earth vector. Label
the results approximate: no light-time, aberration, nutation or refraction;
outer planets can differ by tenths of a degree. No telescope/navigation claims.
Reference tests compare independent published/Horizons vectors at pinned dates.

## Privacy and lifecycle

Use a dedicated location boundary which returns only a `CoarseLocation` (0.1°)
and validates finite, in-range inputs. Request location only on explicit user
action; a manual coarse-cell option also works offline. Never retain, log, show
or transmit the original position; never import a weather/network provider into
Sky View. No persistent location history. Re-check permission on resume and
before each location read; failures clear the computed view.

Use existing sensors_plus accelerometer/magnetometer fallback in portrait.
This package does not supply a rotation vector, so do not invent one or claim
that fallback is a fused attitude. A future native rotation-vector adapter is a
separate improvement. Project the phone's rear-facing normal into an east/north/up
basis, not its top edge. Require both fresh sensor samples, reject implausible
gravity/magnetic lengths and near-parallel vectors, and invalidate stale data.
Stop subscriptions and timers on pause/dispose. Calibration guidance includes
figure-eight movement and distance from magnets. Magnetic heading requires a
declination correction: user-entered east-positive offset, visibly unset until
supplied; no unlabeled magnetic-to-true-north assumption. A bundled WMM model
can replace this manual correction in a separate PR after validation.

## UI and verification

The view lists real computed objects above the geometric horizon and identifies
those within a bounded angular cone of the device. Sky background is schematic,
not a camera preview. Empty cones say no bundled object is near the pointing
direction; missing location/orientation/declination never creates defaults.
Tap details show catalog ID/constellation, RA/Dec, azimuth/altitude and approximate
position caveats. The subset label makes omitted faint stars explicit.

Core tests: known UTC epochs, east-positive longitude, cardinal horizon vectors,
precession, catalog integrity, independent multi-date planet references and
validity limits. Integration tests inject actual service/provider seams, deny
permission, omit/stale sensors, cancel lifecycle, and install an HTTP-denying
transport. Main RED and caught sign/frame/privacy mutations precede GREEN.
Run flutter analyze and full flutter test for every published behavior change.
No APK build/install or runtime device claim; local checks are the evidence
until named self-hosted jobs execute nonzero steps.
