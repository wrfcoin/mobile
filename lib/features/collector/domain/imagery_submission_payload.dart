import '../../weather/domain/models/coarse_location.dart';
import 'cloud_observation.dart';

/// Builds the existing imagery submission contract.
///
/// Classifier output intentionally stays local until the backend owns and
/// validates a versioned classification envelope.
Map<String, dynamic> buildImagerySubmissionPayload({
  required String category,
  required CloudGenus cloudGenus,
  required String description,
  double? latitude,
  double? longitude,
}) {
  return <String, dynamic>{
    'dataType': 'imagery',
    'category': category,
    'description': category == 'cloud_formation'
        ? cloudObservationDescription(
            genus: cloudGenus,
            description: description,
          )
        : description,
    // 0.1 degree (~11 km) only, whatever the caller passed.
    'latitude': ?(latitude == null ? null : CoarseLocation.coarsen(latitude)),
    'longitude': ?(longitude == null
        ? null
        : CoarseLocation.coarsen(longitude)),
  };
}
