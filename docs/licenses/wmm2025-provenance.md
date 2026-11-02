# World Magnetic Model 2025

Source: https://www.ncei.noaa.gov/sites/default/files/2024-12/WMM2025COF.zip
(linked from https://www.ncei.noaa.gov/products/world-magnetic-model/wmm-coefficients)

Archive SHA256: 2e76569370d081f2cd7919490218bd094ca9afde347b198eff5621e0af460d03
WMM2025.COF SHA256: dfa8597825af4e0b87ff4198a5b4fb661b3c49f4cd090cd0164e0259b075582f
WMM2025_TestValues.txt SHA256: e6975b093dddeb6153e0b23cc418425c438167e7c5b1dd795da379cb654f5819

Produced by NOAA NCEI and the British Geological Survey. As a work of the US
government, the model is in the public domain in the United States; NCEI asks
that it be cited. Valid 2025.0 to 2030.0. Sky View refuses to extrapolate past
that and says the compass is uncorrected until the model is updated.

`lib/features/sky_view/data/wmm2025_coefficients.dart` is generated from the .COF
file with no value changed. `test/features/sky_view/fixtures/WMM2025_TestValues.txt`
is the official table, checked row by row in `wmm_test.dart`.
