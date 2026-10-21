import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_snackbars.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/location/location_service.dart';
import '../../data/services/imagery_sanitizer_service.dart';
import '../../domain/image_metadata_sanitizer.dart';
import '../../domain/cloud_observation.dart';
import '../../domain/cloud_classification.dart';
import '../../domain/imagery_submission_payload.dart';

const String _kMlUnavailableText =
    'On-device ML classification is unavailable in this build.';

class ImageryUploadScreen extends ConsumerStatefulWidget {
  const ImageryUploadScreen({
    super.key,
    this.cloudClassifier = const NoOpCloudClassifier(),
    this.pickImagePath,
    this.sanitizedDirectory,
  });

  final CloudClassifier cloudClassifier;

  /// Test seam: returns the path of the picked photo. Defaults to the platform picker.
  final Future<String?> Function(ImageSource source)? pickImagePath;

  /// Test seam: where the sanitized copy is written. Defaults to the app's temporary directory.
  final Directory? sanitizedDirectory;

  @override
  ConsumerState<ImageryUploadScreen> createState() =>
      _ImageryUploadScreenState();
}

class _ImageryUploadScreenState extends ConsumerState<ImageryUploadScreen> {
  String? _imagePath;
  String _category = 'cloud_formation';
  CloudGenus _cloudGenus = CloudGenus.uncertain;
  String _description = '';
  CloudClassificationSuggestion? _cloudClassification;
  double? _latitude;
  double? _longitude;
  bool _submitting = false;
  bool _isClassifying = false;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final position = await ref
        .read(locationServiceProvider)
        .getCurrentPosition();
    if (position != null && mounted) {
      setState(() {
        _latitude = LocationService.anonymize(position.latitude);
        _longitude = LocationService.anonymize(position.longitude);
      });
    }
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final pickedPath = widget.pickImagePath != null
        ? await widget.pickImagePath!(source)
        : (await ImagePicker().pickImage(source: source))?.path;
    if (pickedPath == null || !mounted) return;

    // The picked file can carry full-precision GPS in its metadata. Only a sanitized copy made by
    // this app is ever shown, classified or uploaded; if it cannot be made, the photo is refused.
    final File clean;
    try {
      clean = await sanitizePickedImage(
        pickedPath,
        into: widget.sanitizedDirectory,
      );
    } catch (e) {
      await _discardSanitizedFile();
      if (!mounted) return;
      setState(() {
        _imagePath = null;
        _cloudClassification = null;
      });
      AppSnackbars.error(
        context,
        ServerFailure(
          e is ImageSanitizeException
              ? 'This photo was not used: ${e.message}'
              : 'This photo was not used: its location data could not be removed.',
        ),
      );
      return;
    }
    if (!mounted) return;
    await _discardSanitizedFile();
    setState(() {
      _imagePath = clean.path;
      _cloudClassification = null;
    });
    await _refreshCloudClassification();
  }

  Future<void> _discardSanitizedFile() async {
    final path = _imagePath;
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    final path = _imagePath;
    if (path != null) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _refreshCloudClassification() async {
    if (_imagePath == null || !widget.cloudClassifier.isDeviceAvailable) {
      return;
    }

    setState(() => _isClassifying = true);
    try {
      final classification = await widget.cloudClassifier.classify(
        File(_imagePath!),
      );
      if (!mounted) return;

      setState(() {
        _cloudClassification = classification;
        if (classification != null && _category == 'cloud_formation') {
          _cloudGenus = classification.primary.genus;
          if (_description.isEmpty) {
            _description = classification.primary.genus.label;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cloudClassification = null;
      });
    } finally {
      if (mounted) setState(() => _isClassifying = false);
    }
  }

  Future<void> _submit() async {
    if (_imagePath == null) return;

    setState(() => _submitting = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final formData = FormData.fromMap({
        ...buildImagerySubmissionPayload(
          category: _category,
          cloudGenus: _cloudGenus,
          description: _description,
          latitude: _latitude,
          longitude: _longitude,
        ),
        'image': await MultipartFile.fromFile(
          _imagePath!,
          filename: _imagePath!.endsWith('.png')
              ? 'weather_image.png'
              : 'weather_image.jpg',
        ),
      });

      await apiClient.dio.post(
        ApiConstants.oracleSubmitData,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (mounted) {
        AppSnackbars.success(context, 'Image submitted for validation');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppSnackbars.error(
          context,
          e is Failure ? e : ServerFailure(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final consent = ref.watch(appPreferencesProvider).preferences.consent;

    return Scaffold(
      appBar: AppBar(title: const Text('Submit Imagery')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!consent.imageryUpload)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.privacy_tip),
                      const SizedBox(width: 8),
                      Expanded(child: Text(localizations.imageryConsentHint)),
                    ],
                  ),
                ),
              ),
            ),
          // Image preview / pick
          GestureDetector(
            onTap: consent.imageryUpload ? _pickImage : null,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: _imagePath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(_imagePath!),
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt,
                            size: 48,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Tap to take photo or select from gallery',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // Category
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: const [
              DropdownMenuItem(
                value: 'cloud_formation',
                child: Text('Cloud Formation'),
              ),
              DropdownMenuItem(
                value: 'storm_damage',
                child: Text('Storm Damage'),
              ),
              DropdownMenuItem(value: 'pollution', child: Text('Pollution')),
              DropdownMenuItem(value: 'flooding', child: Text('Flooding')),
              DropdownMenuItem(
                value: 'wildfire',
                child: Text('Wildfire/Smoke'),
              ),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 16),

          if (_category == 'cloud_formation') ...[
            DropdownButtonFormField<CloudGenus>(
              initialValue: _cloudGenus,
              decoration: const InputDecoration(
                labelText: 'Cloud type you observe',
                helperText: 'User confirmed. ML runtime is still pending in this slice.',
              ),
              items: CloudGenus.values
                  .map(
                    (genus) => DropdownMenuItem(
                      value: genus,
                      child: Text(genus.label),
                    ),
                  )
                  .toList(),
              onChanged: (genus) {
                if (genus != null) setState(() => _cloudGenus = genus);
              },
            ),
            const SizedBox(height: 16),

            if (_isClassifying)
              const LinearProgressIndicator()
            else if (_cloudClassification != null)
              ListTile(
                leading: const Icon(
                  Icons.memory,
                  color: AppColors.textSecondary,
                ),
                title: const Text('Cloud ML suggestion'),
                subtitle: Text(
                  '${_cloudClassification!.primary.genus.label} '
                  '(${(_cloudClassification!.primary.confidence * 100).toStringAsFixed(1)}%)',
                ),
                trailing: _cloudClassification!.isHighConfidence
                    ? const Icon(Icons.verified, color: AppColors.success)
                    : null,
              )
            else if (!widget.cloudClassifier.isDeviceAvailable)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  _kMlUnavailableText,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],

          // Description
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'Describe what you see...',
            ),
            maxLines: 3,
            onChanged: (v) => _description = v,
          ),
          const SizedBox(height: 16),

          // Location
          Card(
            child: ListTile(
              leading: const Icon(Icons.location_on, color: AppColors.primary),
              title: const Text('Location'),
              subtitle: Text(
                _latitude != null
                    ? '${_latitude!.toStringAsFixed(1)}, ${_longitude!.toStringAsFixed(1)}'
                    : 'Detecting...',
                style: const TextStyle(fontSize: 13),
              ),
              trailing: const Icon(
                Icons.shield,
                color: AppColors.success,
                size: 18,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 4),
            child: Text(
              'Location rounded to ~11 km (0.1°)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed:
                _imagePath == null || _submitting || !consent.imageryUpload
                ? null
                : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit for validation'),
          ),
        ],
      ),
    );
  }
}
