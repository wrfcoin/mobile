import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLocaleOption { system, english, spanish }

enum UnitSystem { metric, imperial }

enum TimezonePreference { deviceLocal, utc }

enum ConsentType { sensor, location, imagery }

class ConsentSettings {
  final bool sensorCollection;
  final bool preciseLocation;
  final bool imageryUpload;

  const ConsentSettings({
    this.sensorCollection = false,
    this.preciseLocation = false,
    this.imageryUpload = false,
  });

  bool get canCollect => sensorCollection && preciseLocation;

  ConsentSettings copyWith({
    bool? sensorCollection,
    bool? preciseLocation,
    bool? imageryUpload,
  }) {
    return ConsentSettings(
      sensorCollection: sensorCollection ?? this.sensorCollection,
      preciseLocation: preciseLocation ?? this.preciseLocation,
      imageryUpload: imageryUpload ?? this.imageryUpload,
    );
  }

  bool valueFor(ConsentType type) {
    return switch (type) {
      ConsentType.sensor => sensorCollection,
      ConsentType.location => preciseLocation,
      ConsentType.imagery => imageryUpload,
    };
  }

  ConsentSettings withValue(ConsentType type, bool value) {
    return switch (type) {
      ConsentType.sensor => copyWith(sensorCollection: value),
      ConsentType.location => copyWith(preciseLocation: value),
      ConsentType.imagery => copyWith(imageryUpload: value),
    };
  }
}

class AppPreferences {
  final ThemeMode themeMode;
  final AppLocaleOption localeOption;
  final UnitSystem unitSystem;
  final TimezonePreference timezonePreference;
  final ConsentSettings consent;

  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.localeOption = AppLocaleOption.system,
    this.unitSystem = UnitSystem.metric,
    this.timezonePreference = TimezonePreference.deviceLocal,
    this.consent = const ConsentSettings(),
  });

  Locale? get locale {
    return switch (localeOption) {
      AppLocaleOption.system => null,
      AppLocaleOption.english => const Locale('en'),
      AppLocaleOption.spanish => const Locale('es'),
    };
  }

  AppPreferences copyWith({
    ThemeMode? themeMode,
    AppLocaleOption? localeOption,
    UnitSystem? unitSystem,
    TimezonePreference? timezonePreference,
    ConsentSettings? consent,
  }) {
    return AppPreferences(
      themeMode: themeMode ?? this.themeMode,
      localeOption: localeOption ?? this.localeOption,
      unitSystem: unitSystem ?? this.unitSystem,
      timezonePreference: timezonePreference ?? this.timezonePreference,
      consent: consent ?? this.consent,
    );
  }
}

class AppPreferencesState {
  final AppPreferences preferences;
  final bool loaded;

  const AppPreferencesState({
    this.preferences = const AppPreferences(),
    this.loaded = false,
  });

  AppPreferencesState copyWith({AppPreferences? preferences, bool? loaded}) {
    return AppPreferencesState(
      preferences: preferences ?? this.preferences,
      loaded: loaded ?? this.loaded,
    );
  }
}

final appPreferencesStoreProvider = Provider<AppPreferencesStore>((ref) {
  return const AppPreferencesStore();
});

final appPreferencesProvider =
    NotifierProvider<AppPreferencesNotifier, AppPreferencesState>(
      AppPreferencesNotifier.new,
    );

class AppPreferencesNotifier extends Notifier<AppPreferencesState> {
  late AppPreferencesStore _store;

  @override
  AppPreferencesState build() {
    _store = ref.watch(appPreferencesStoreProvider);
    Future.microtask(load);
    return const AppPreferencesState();
  }

  Future<void> load() async {
    final preferences = await _store.load();
    state = state.copyWith(preferences: preferences, loaded: true);
  }

  Future<void> setThemeMode(ThemeMode themeMode) async {
    await _update(state.preferences.copyWith(themeMode: themeMode));
  }

  Future<void> setLocaleOption(AppLocaleOption localeOption) async {
    await _update(state.preferences.copyWith(localeOption: localeOption));
  }

  Future<void> setUnitSystem(UnitSystem unitSystem) async {
    await _update(state.preferences.copyWith(unitSystem: unitSystem));
  }

  Future<void> setTimezonePreference(
    TimezonePreference timezonePreference,
  ) async {
    await _update(
      state.preferences.copyWith(timezonePreference: timezonePreference),
    );
  }

  Future<void> setConsent(ConsentType type, bool granted) async {
    await _update(
      state.preferences.copyWith(
        consent: state.preferences.consent.withValue(type, granted),
      ),
    );
  }

  Future<void> revokeAllCollectionConsent() async {
    await _update(state.preferences.copyWith(consent: const ConsentSettings()));
  }

  Future<void> _update(AppPreferences preferences) async {
    state = state.copyWith(preferences: preferences, loaded: true);
    await _store.save(preferences);
  }
}

class AppPreferencesStore {
  const AppPreferencesStore();

  static const _themeModeKey = 'app.theme_mode';
  static const _localeKey = 'app.locale';
  static const _unitSystemKey = 'app.unit_system';
  static const _timezoneKey = 'app.timezone';
  static const _sensorConsentKey = 'privacy.sensor_collection';
  static const _locationConsentKey = 'privacy.location_collection';
  static const _imageryConsentKey = 'privacy.imagery_upload';

  Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences(
      themeMode: _themeModeFromKey(prefs.getString(_themeModeKey)),
      localeOption: _localeOptionFromKey(prefs.getString(_localeKey)),
      unitSystem: _unitSystemFromKey(prefs.getString(_unitSystemKey)),
      timezonePreference: _timezoneFromKey(prefs.getString(_timezoneKey)),
      consent: ConsentSettings(
        sensorCollection: prefs.getBool(_sensorConsentKey) ?? false,
        preciseLocation: prefs.getBool(_locationConsentKey) ?? false,
        imageryUpload: prefs.getBool(_imageryConsentKey) ?? false,
      ),
    );
  }

  Future<void> save(AppPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_themeModeKey, _themeModeKeyFor(preferences.themeMode)),
      prefs.setString(_localeKey, _localeKeyFor(preferences.localeOption)),
      prefs.setString(
        _unitSystemKey,
        _unitSystemKeyFor(preferences.unitSystem),
      ),
      prefs.setString(
        _timezoneKey,
        _timezoneKeyFor(preferences.timezonePreference),
      ),
      prefs.setBool(_sensorConsentKey, preferences.consent.sensorCollection),
      prefs.setBool(_locationConsentKey, preferences.consent.preciseLocation),
      prefs.setBool(_imageryConsentKey, preferences.consent.imageryUpload),
    ]);
  }

  String _themeModeKeyFor(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
    };
  }

  ThemeMode _themeModeFromKey(String? key) {
    return switch (key) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  String _localeKeyFor(AppLocaleOption locale) {
    return switch (locale) {
      AppLocaleOption.system => 'system',
      AppLocaleOption.english => 'en',
      AppLocaleOption.spanish => 'es',
    };
  }

  AppLocaleOption _localeOptionFromKey(String? key) {
    return switch (key) {
      'en' => AppLocaleOption.english,
      'es' => AppLocaleOption.spanish,
      _ => AppLocaleOption.system,
    };
  }

  String _unitSystemKeyFor(UnitSystem system) {
    return switch (system) {
      UnitSystem.metric => 'metric',
      UnitSystem.imperial => 'imperial',
    };
  }

  UnitSystem _unitSystemFromKey(String? key) {
    return switch (key) {
      'imperial' => UnitSystem.imperial,
      _ => UnitSystem.metric,
    };
  }

  String _timezoneKeyFor(TimezonePreference timezone) {
    return switch (timezone) {
      TimezonePreference.deviceLocal => 'device',
      TimezonePreference.utc => 'utc',
    };
  }

  TimezonePreference _timezoneFromKey(String? key) {
    return switch (key) {
      'utc' => TimezonePreference.utc,
      _ => TimezonePreference.deviceLocal,
    };
  }
}
