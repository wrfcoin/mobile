import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('es')];

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    assert(localizations != null, 'AppLocalizations not found in context');
    return localizations!;
  }

  static const _localizedValues = <String, Map<String, String>>{
    'en': {
      'settings': 'Settings',
      'appearance': 'Appearance',
      'themeMode': 'Theme Mode',
      'themeSystem': 'System',
      'themeLight': 'Light',
      'themeDark': 'Dark',
      'dataDisplay': 'Data Display',
      'unitSystem': 'Unit System',
      'unitsMetric': 'Metric',
      'unitsImperial': 'Imperial',
      'language': 'Language',
      'languageSystem': 'Use device language',
      'languageEnglish': 'English',
      'languageSpanish': 'Spanish',
      'timezone': 'Timezone',
      'timezoneDevice': 'Device Local',
      'timezoneUtc': 'UTC',
      'privacyCenter': 'Privacy Center',
      'privacySummary':
          'Review what the app can collect and revoke consent at any time.',
      'openPrivacyCenter': 'Open Privacy Center',
      'consentTitle': 'Data Collection Consent',
      'consentSummary': 'Collection stays off until you opt in. Revoking consent stops workers and clears unsynced local data.',
      'sensorConsent': 'Sensor readings',
      'sensorConsentDescription':
          'Allows the app to sample pressure readings and queue them for sync.',
      'locationConsent': 'Approximate location',
      'locationConsentDescription':
          'Stores coordinates rounded to ~11 km (0.1°) for each reading.',
      'imageryConsent': 'Imagery uploads',
      'imageryConsentDescription':
          'Allows camera/gallery submission for weather event validation.',
      'requiredForCollecting': 'Sensor readings and location are both required before collection can start.',
      'retentionTitle': 'Retention Summary',
      'retentionBody': 'Unsynced sensor readings and imagery stay only on-device until uploaded or consent is revoked. Revocation clears pending local collection data immediately.',
      'policyLinks': 'Policy Links',
      'privacyPolicy': 'Privacy Policy',
      'dataPolicy': 'Data Usage Policy',
      'termsOfService': 'Terms of Service',
      'copiedLink': 'Policy link copied',
      'revokeConsent': 'Revoke All Collection Consent',
      'revokeConsentTitle': 'Revoke collection consent?',
      'revokeConsentBody': 'This stops background collection and clears unsynced local readings and imagery on this device.',
      'stay': 'Stay',
      'revoke': 'Revoke',
      'consentRevoked': 'Collection consent revoked',
      'consentRevokedDetail':
          'Background collection stopped and pending local data was cleared.',
      'grantConsentHint': 'Grant sensor and location consent in Privacy Center to enable collection.',
      'imageryConsentHint':
          'Enable imagery consent in Privacy Center before submitting photos.',
      'statusOn': 'On',
      'statusOff': 'Off',
      'collectionEnabled': 'Collection enabled',
      'collectionBlocked': 'Collection blocked',
    },
    'es': {
      'settings': 'Ajustes',
      'appearance': 'Apariencia',
      'themeMode': 'Tema',
      'themeSystem': 'Sistema',
      'themeLight': 'Claro',
      'themeDark': 'Oscuro',
      'dataDisplay': 'Visualizacion de datos',
      'unitSystem': 'Sistema de unidades',
      'unitsMetric': 'Metrico',
      'unitsImperial': 'Imperial',
      'language': 'Idioma',
      'languageSystem': 'Usar idioma del dispositivo',
      'languageEnglish': 'Ingles',
      'languageSpanish': 'Espanol',
      'timezone': 'Zona horaria',
      'timezoneDevice': 'Del dispositivo',
      'timezoneUtc': 'UTC',
      'privacyCenter': 'Centro de privacidad',
      'privacySummary': 'Revisa que puede recopilar la app y revoca el consentimiento cuando quieras.',
      'openPrivacyCenter': 'Abrir centro de privacidad',
      'consentTitle': 'Consentimiento de recopilacion',
      'consentSummary': 'La recopilacion permanece desactivada hasta que aceptes. Revocar el consentimiento detiene los procesos y borra los datos locales pendientes.',
      'sensorConsent': 'Lecturas de sensores',
      'sensorConsentDescription': 'Permite a la app muestrear presion y poner lecturas en cola para sincronizacion.',
      'locationConsent': 'Ubicacion aproximada',
      'locationConsentDescription':
          'Guarda coordenadas redondeadas a ~11 km (0.1°) para cada lectura.',
      'imageryConsent': 'Carga de imagenes',
      'imageryConsentDescription': 'Permite enviar fotos de camara o galeria para validacion meteorologica.',
      'requiredForCollecting': 'Las lecturas de sensores y la ubicacion son necesarias para iniciar la recopilacion.',
      'retentionTitle': 'Resumen de retencion',
      'retentionBody': 'Las lecturas e imagenes sin sincronizar permanecen solo en el dispositivo hasta subirse o revocarse el consentimiento. La revocacion limpia los datos locales pendientes de inmediato.',
      'policyLinks': 'Enlaces de politicas',
      'privacyPolicy': 'Politica de privacidad',
      'dataPolicy': 'Politica de uso de datos',
      'termsOfService': 'Terminos del servicio',
      'copiedLink': 'Enlace copiado',
      'revokeConsent': 'Revocar todo el consentimiento',
      'revokeConsentTitle': '¿Revocar el consentimiento?',
      'revokeConsentBody': 'Esto detiene la recopilacion en segundo plano y borra lecturas e imagenes locales pendientes en este dispositivo.',
      'stay': 'Permanecer',
      'revoke': 'Revocar',
      'consentRevoked': 'Consentimiento revocado',
      'consentRevokedDetail': 'La recopilacion en segundo plano se detuvo y los datos locales pendientes se borraron.',
      'grantConsentHint': 'Otorga consentimiento de sensores y ubicacion en el Centro de privacidad para habilitar la recopilacion.',
      'imageryConsentHint': 'Activa el consentimiento de imagenes en el Centro de privacidad antes de enviar fotos.',
      'statusOn': 'Activo',
      'statusOff': 'Inactivo',
      'collectionEnabled': 'Recopilacion habilitada',
      'collectionBlocked': 'Recopilacion bloqueada',
    },
  };

  String _value(String key) {
    final languageCode = _localizedValues.containsKey(locale.languageCode)
        ? locale.languageCode
        : 'en';
    return _localizedValues[languageCode]![key] ??
        _localizedValues['en']![key]!;
  }

  String get settings => _value('settings');
  String get appearance => _value('appearance');
  String get themeMode => _value('themeMode');
  String get themeSystem => _value('themeSystem');
  String get themeLight => _value('themeLight');
  String get themeDark => _value('themeDark');
  String get dataDisplay => _value('dataDisplay');
  String get unitSystem => _value('unitSystem');
  String get unitsMetric => _value('unitsMetric');
  String get unitsImperial => _value('unitsImperial');
  String get language => _value('language');
  String get languageSystem => _value('languageSystem');
  String get languageEnglish => _value('languageEnglish');
  String get languageSpanish => _value('languageSpanish');
  String get timezone => _value('timezone');
  String get timezoneDevice => _value('timezoneDevice');
  String get timezoneUtc => _value('timezoneUtc');
  String get privacyCenter => _value('privacyCenter');
  String get privacySummary => _value('privacySummary');
  String get openPrivacyCenter => _value('openPrivacyCenter');
  String get consentTitle => _value('consentTitle');
  String get consentSummary => _value('consentSummary');
  String get sensorConsent => _value('sensorConsent');
  String get sensorConsentDescription => _value('sensorConsentDescription');
  String get locationConsent => _value('locationConsent');
  String get locationConsentDescription => _value('locationConsentDescription');
  String get imageryConsent => _value('imageryConsent');
  String get imageryConsentDescription => _value('imageryConsentDescription');
  String get requiredForCollecting => _value('requiredForCollecting');
  String get retentionTitle => _value('retentionTitle');
  String get retentionBody => _value('retentionBody');
  String get policyLinks => _value('policyLinks');
  String get privacyPolicy => _value('privacyPolicy');
  String get dataPolicy => _value('dataPolicy');
  String get termsOfService => _value('termsOfService');
  String get copiedLink => _value('copiedLink');
  String get revokeConsent => _value('revokeConsent');
  String get revokeConsentTitle => _value('revokeConsentTitle');
  String get revokeConsentBody => _value('revokeConsentBody');
  String get stay => _value('stay');
  String get revoke => _value('revoke');
  String get consentRevoked => _value('consentRevoked');
  String get consentRevokedDetail => _value('consentRevokedDetail');
  String get grantConsentHint => _value('grantConsentHint');
  String get imageryConsentHint => _value('imageryConsentHint');
  String get statusOn => _value('statusOn');
  String get statusOff => _value('statusOff');
  String get collectionEnabled => _value('collectionEnabled');
  String get collectionBlocked => _value('collectionBlocked');
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
