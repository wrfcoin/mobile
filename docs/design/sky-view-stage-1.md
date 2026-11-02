# Sky View stage 1: the sky map

Point the phone at the night sky and see what is there. Owner decision: no camera.
It is a drawn map, offline, on the `/weather/ar` route (now labelled Sky View).

## Sensors

`SkyRotationVectorStream.kt` is a small `EventChannel` for `TYPE_ROTATION_VECTOR`
at about 30 Hz, sending the quaternion, `SensorEvent.accuracy`, `values[4]` (heading
accuracy) and `Display.getRotation()`. A channel, not a plugin: it adds no
dependency and is under 100 lines. It also holds the screen on while listening.
No sensor, a stream error, or no reading within 2 s starts the
accelerometer/magnetometer fallback, and the screen says it is less steady.

Both paths produce a device-to-magnetic quaternion. `SkyPose.from` is the only place
that turns magnetic into true, so declination cannot be applied twice.

## Corrections, in order

1. Declination: WMM2025 from the 0.1 degree cell and today's date, or a typed
   override, which replaces it. The model is valid 2025 to 2030. Past that the map
   stays usable and says "magnetic north, uncorrected".
2. Alignment: a stored azimuth and altitude offset from "Align on a star". Limited
   to 30 and 15 degrees, because a larger gap means the wrong star, and refused above
   80 degrees altitude, where azimuth stops meaning much.

## Positions

Stars, Sun and planets as in phase 1. Moon: the Astronomical Almanac low-precision
formula, with parallax as altitude minus parallax times cos(altitude).
No refraction, and the map says so.

Checked against JPL Horizons airless topocentric values (0.5 degrees for the Moon,
0.3 for planets, 0.1 for the Sun) and against the identity that Polaris's altitude
equals the latitude to within its own polar distance. WMM is checked against every
row of NOAA's official test table.

## Drawing

Stereographic projection, 60 degrees across the short side. The horizon is an
exact circle in this projection, so it needs no sampling. Sky positions refresh
every 5 s; a frame only re-projects them. The ticker runs only while the map is
moving: inside a 0.05 degree dead band (about a third of a pixel) it stops, so a
resting phone draws nothing. Sensors stop when the app is hidden, not for the
notification shade or Android's own permission dialog.

## Adding a layer later

`skySources` in `data/sky_catalog.dart` is a list of functions from a time to a list
of `SkyObject`. Constellations, satellites and flights start there.
