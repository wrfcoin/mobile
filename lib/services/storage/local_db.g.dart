// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
class $SensorReadingsTable extends SensorReadings
    with TableInfo<$SensorReadingsTable, SensorReading> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SensorReadingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pressureHpaMeta = const VerificationMeta(
    'pressureHpa',
  );
  @override
  late final GeneratedColumn<double> pressureHpa = GeneratedColumn<double>(
    'pressure_hpa',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationSourceMeta = const VerificationMeta(
    'locationSource',
  );
  @override
  late final GeneratedColumn<String> locationSource = GeneratedColumn<String>(
    'location_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationAtMeta = const VerificationMeta(
    'locationAt',
  );
  @override
  late final GeneratedColumn<DateTime> locationAt = GeneratedColumn<DateTime>(
    'location_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    latitude,
    longitude,
    pressureHpa,
    timestamp,
    synced,
    source,
    locationSource,
    locationAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sensor_readings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SensorReading> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('pressure_hpa')) {
      context.handle(
        _pressureHpaMeta,
        pressureHpa.isAcceptableOrUnknown(
          data['pressure_hpa']!,
          _pressureHpaMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pressureHpaMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('location_source')) {
      context.handle(
        _locationSourceMeta,
        locationSource.isAcceptableOrUnknown(
          data['location_source']!,
          _locationSourceMeta,
        ),
      );
    }
    if (data.containsKey('location_at')) {
      context.handle(
        _locationAtMeta,
        locationAt.isAcceptableOrUnknown(data['location_at']!, _locationAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SensorReading map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SensorReading(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      pressureHpa: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pressure_hpa'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      synced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}synced'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
      locationSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_source'],
      ),
      locationAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}location_at'],
      ),
    );
  }

  @override
  $SensorReadingsTable createAlias(String alias) {
    return $SensorReadingsTable(attachedDatabase, alias);
  }
}

class SensorReading extends DataClass implements Insertable<SensorReading> {
  final int id;
  final double latitude;
  final double longitude;
  final double pressureHpa;
  final DateTime timestamp;
  final bool synced;

  /// [ReadingSource.dbValue]. Null: taken before this was recorded.
  final String? source;

  /// 'fresh' or 'reused', and when that location was obtained.
  final String? locationSource;
  final DateTime? locationAt;
  const SensorReading({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.pressureHpa,
    required this.timestamp,
    required this.synced,
    this.source,
    this.locationSource,
    this.locationAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['pressure_hpa'] = Variable<double>(pressureHpa);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['synced'] = Variable<bool>(synced);
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    if (!nullToAbsent || locationSource != null) {
      map['location_source'] = Variable<String>(locationSource);
    }
    if (!nullToAbsent || locationAt != null) {
      map['location_at'] = Variable<DateTime>(locationAt);
    }
    return map;
  }

  SensorReadingsCompanion toCompanion(bool nullToAbsent) {
    return SensorReadingsCompanion(
      id: Value(id),
      latitude: Value(latitude),
      longitude: Value(longitude),
      pressureHpa: Value(pressureHpa),
      timestamp: Value(timestamp),
      synced: Value(synced),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
      locationSource: locationSource == null && nullToAbsent
          ? const Value.absent()
          : Value(locationSource),
      locationAt: locationAt == null && nullToAbsent
          ? const Value.absent()
          : Value(locationAt),
    );
  }

  factory SensorReading.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SensorReading(
      id: serializer.fromJson<int>(json['id']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      pressureHpa: serializer.fromJson<double>(json['pressureHpa']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      synced: serializer.fromJson<bool>(json['synced']),
      source: serializer.fromJson<String?>(json['source']),
      locationSource: serializer.fromJson<String?>(json['locationSource']),
      locationAt: serializer.fromJson<DateTime?>(json['locationAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'pressureHpa': serializer.toJson<double>(pressureHpa),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'synced': serializer.toJson<bool>(synced),
      'source': serializer.toJson<String?>(source),
      'locationSource': serializer.toJson<String?>(locationSource),
      'locationAt': serializer.toJson<DateTime?>(locationAt),
    };
  }

  SensorReading copyWith({
    int? id,
    double? latitude,
    double? longitude,
    double? pressureHpa,
    DateTime? timestamp,
    bool? synced,
    Value<String?> source = const Value.absent(),
    Value<String?> locationSource = const Value.absent(),
    Value<DateTime?> locationAt = const Value.absent(),
  }) => SensorReading(
    id: id ?? this.id,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    pressureHpa: pressureHpa ?? this.pressureHpa,
    timestamp: timestamp ?? this.timestamp,
    synced: synced ?? this.synced,
    source: source.present ? source.value : this.source,
    locationSource: locationSource.present
        ? locationSource.value
        : this.locationSource,
    locationAt: locationAt.present ? locationAt.value : this.locationAt,
  );
  SensorReading copyWithCompanion(SensorReadingsCompanion data) {
    return SensorReading(
      id: data.id.present ? data.id.value : this.id,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      pressureHpa: data.pressureHpa.present
          ? data.pressureHpa.value
          : this.pressureHpa,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      synced: data.synced.present ? data.synced.value : this.synced,
      source: data.source.present ? data.source.value : this.source,
      locationSource: data.locationSource.present
          ? data.locationSource.value
          : this.locationSource,
      locationAt: data.locationAt.present
          ? data.locationAt.value
          : this.locationAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SensorReading(')
          ..write('id: $id, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('pressureHpa: $pressureHpa, ')
          ..write('timestamp: $timestamp, ')
          ..write('synced: $synced, ')
          ..write('source: $source, ')
          ..write('locationSource: $locationSource, ')
          ..write('locationAt: $locationAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    latitude,
    longitude,
    pressureHpa,
    timestamp,
    synced,
    source,
    locationSource,
    locationAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SensorReading &&
          other.id == this.id &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.pressureHpa == this.pressureHpa &&
          other.timestamp == this.timestamp &&
          other.synced == this.synced &&
          other.source == this.source &&
          other.locationSource == this.locationSource &&
          other.locationAt == this.locationAt);
}

class SensorReadingsCompanion extends UpdateCompanion<SensorReading> {
  final Value<int> id;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double> pressureHpa;
  final Value<DateTime> timestamp;
  final Value<bool> synced;
  final Value<String?> source;
  final Value<String?> locationSource;
  final Value<DateTime?> locationAt;
  const SensorReadingsCompanion({
    this.id = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.pressureHpa = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.synced = const Value.absent(),
    this.source = const Value.absent(),
    this.locationSource = const Value.absent(),
    this.locationAt = const Value.absent(),
  });
  SensorReadingsCompanion.insert({
    this.id = const Value.absent(),
    required double latitude,
    required double longitude,
    required double pressureHpa,
    required DateTime timestamp,
    this.synced = const Value.absent(),
    this.source = const Value.absent(),
    this.locationSource = const Value.absent(),
    this.locationAt = const Value.absent(),
  }) : latitude = Value(latitude),
       longitude = Value(longitude),
       pressureHpa = Value(pressureHpa),
       timestamp = Value(timestamp);
  static Insertable<SensorReading> custom({
    Expression<int>? id,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? pressureHpa,
    Expression<DateTime>? timestamp,
    Expression<bool>? synced,
    Expression<String>? source,
    Expression<String>? locationSource,
    Expression<DateTime>? locationAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (pressureHpa != null) 'pressure_hpa': pressureHpa,
      if (timestamp != null) 'timestamp': timestamp,
      if (synced != null) 'synced': synced,
      if (source != null) 'source': source,
      if (locationSource != null) 'location_source': locationSource,
      if (locationAt != null) 'location_at': locationAt,
    });
  }

  SensorReadingsCompanion copyWith({
    Value<int>? id,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<double>? pressureHpa,
    Value<DateTime>? timestamp,
    Value<bool>? synced,
    Value<String?>? source,
    Value<String?>? locationSource,
    Value<DateTime?>? locationAt,
  }) {
    return SensorReadingsCompanion(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      pressureHpa: pressureHpa ?? this.pressureHpa,
      timestamp: timestamp ?? this.timestamp,
      synced: synced ?? this.synced,
      source: source ?? this.source,
      locationSource: locationSource ?? this.locationSource,
      locationAt: locationAt ?? this.locationAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (pressureHpa.present) {
      map['pressure_hpa'] = Variable<double>(pressureHpa.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (locationSource.present) {
      map['location_source'] = Variable<String>(locationSource.value);
    }
    if (locationAt.present) {
      map['location_at'] = Variable<DateTime>(locationAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SensorReadingsCompanion(')
          ..write('id: $id, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('pressureHpa: $pressureHpa, ')
          ..write('timestamp: $timestamp, ')
          ..write('synced: $synced, ')
          ..write('source: $source, ')
          ..write('locationSource: $locationSource, ')
          ..write('locationAt: $locationAt')
          ..write(')'))
        .toString();
  }
}

class $PendingImagesTable extends PendingImages
    with TableInfo<$PendingImagesTable, PendingImage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageMetadataMeta = const VerificationMeta(
    'imageMetadata',
  );
  @override
  late final GeneratedColumn<String> imageMetadata = GeneratedColumn<String>(
    'image_metadata',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    filePath,
    latitude,
    longitude,
    imageMetadata,
    timestamp,
    synced,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_images';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingImage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('image_metadata')) {
      context.handle(
        _imageMetadataMeta,
        imageMetadata.isAcceptableOrUnknown(
          data['image_metadata']!,
          _imageMetadataMeta,
        ),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingImage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingImage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      imageMetadata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_metadata'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      synced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}synced'],
      )!,
    );
  }

  @override
  $PendingImagesTable createAlias(String alias) {
    return $PendingImagesTable(attachedDatabase, alias);
  }
}

class PendingImage extends DataClass implements Insertable<PendingImage> {
  final int id;
  final String filePath;
  final double latitude;
  final double longitude;
  final String imageMetadata;
  final DateTime timestamp;
  final bool synced;
  const PendingImage({
    required this.id,
    required this.filePath,
    required this.latitude,
    required this.longitude,
    required this.imageMetadata,
    required this.timestamp,
    required this.synced,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['file_path'] = Variable<String>(filePath);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['image_metadata'] = Variable<String>(imageMetadata);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['synced'] = Variable<bool>(synced);
    return map;
  }

  PendingImagesCompanion toCompanion(bool nullToAbsent) {
    return PendingImagesCompanion(
      id: Value(id),
      filePath: Value(filePath),
      latitude: Value(latitude),
      longitude: Value(longitude),
      imageMetadata: Value(imageMetadata),
      timestamp: Value(timestamp),
      synced: Value(synced),
    );
  }

  factory PendingImage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingImage(
      id: serializer.fromJson<int>(json['id']),
      filePath: serializer.fromJson<String>(json['filePath']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      imageMetadata: serializer.fromJson<String>(json['imageMetadata']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      synced: serializer.fromJson<bool>(json['synced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'filePath': serializer.toJson<String>(filePath),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'imageMetadata': serializer.toJson<String>(imageMetadata),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'synced': serializer.toJson<bool>(synced),
    };
  }

  PendingImage copyWith({
    int? id,
    String? filePath,
    double? latitude,
    double? longitude,
    String? imageMetadata,
    DateTime? timestamp,
    bool? synced,
  }) => PendingImage(
    id: id ?? this.id,
    filePath: filePath ?? this.filePath,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    imageMetadata: imageMetadata ?? this.imageMetadata,
    timestamp: timestamp ?? this.timestamp,
    synced: synced ?? this.synced,
  );
  PendingImage copyWithCompanion(PendingImagesCompanion data) {
    return PendingImage(
      id: data.id.present ? data.id.value : this.id,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      imageMetadata: data.imageMetadata.present
          ? data.imageMetadata.value
          : this.imageMetadata,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      synced: data.synced.present ? data.synced.value : this.synced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingImage(')
          ..write('id: $id, ')
          ..write('filePath: $filePath, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('imageMetadata: $imageMetadata, ')
          ..write('timestamp: $timestamp, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    filePath,
    latitude,
    longitude,
    imageMetadata,
    timestamp,
    synced,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingImage &&
          other.id == this.id &&
          other.filePath == this.filePath &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.imageMetadata == this.imageMetadata &&
          other.timestamp == this.timestamp &&
          other.synced == this.synced);
}

class PendingImagesCompanion extends UpdateCompanion<PendingImage> {
  final Value<int> id;
  final Value<String> filePath;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<String> imageMetadata;
  final Value<DateTime> timestamp;
  final Value<bool> synced;
  const PendingImagesCompanion({
    this.id = const Value.absent(),
    this.filePath = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.imageMetadata = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.synced = const Value.absent(),
  });
  PendingImagesCompanion.insert({
    this.id = const Value.absent(),
    required String filePath,
    required double latitude,
    required double longitude,
    this.imageMetadata = const Value.absent(),
    required DateTime timestamp,
    this.synced = const Value.absent(),
  }) : filePath = Value(filePath),
       latitude = Value(latitude),
       longitude = Value(longitude),
       timestamp = Value(timestamp);
  static Insertable<PendingImage> custom({
    Expression<int>? id,
    Expression<String>? filePath,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<String>? imageMetadata,
    Expression<DateTime>? timestamp,
    Expression<bool>? synced,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (filePath != null) 'file_path': filePath,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (imageMetadata != null) 'image_metadata': imageMetadata,
      if (timestamp != null) 'timestamp': timestamp,
      if (synced != null) 'synced': synced,
    });
  }

  PendingImagesCompanion copyWith({
    Value<int>? id,
    Value<String>? filePath,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<String>? imageMetadata,
    Value<DateTime>? timestamp,
    Value<bool>? synced,
  }) {
    return PendingImagesCompanion(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageMetadata: imageMetadata ?? this.imageMetadata,
      timestamp: timestamp ?? this.timestamp,
      synced: synced ?? this.synced,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (imageMetadata.present) {
      map['image_metadata'] = Variable<String>(imageMetadata.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingImagesCompanion(')
          ..write('id: $id, ')
          ..write('filePath: $filePath, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('imageMetadata: $imageMetadata, ')
          ..write('timestamp: $timestamp, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }
}

class $SyncMetadataEntriesTable extends SyncMetadataEntries
    with TableInfo<$SyncMetadataEntriesTable, SyncMetadataEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetadataEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _syncTableNameMeta = const VerificationMeta(
    'syncTableName',
  );
  @override
  late final GeneratedColumn<String> syncTableName = GeneratedColumn<String>(
    'sync_table_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncAttemptAtMeta = const VerificationMeta(
    'lastSyncAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAttemptAt =
      GeneratedColumn<DateTime>(
        'last_sync_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastSyncErrorMeta = const VerificationMeta(
    'lastSyncError',
  );
  @override
  late final GeneratedColumn<String> lastSyncError = GeneratedColumn<String>(
    'last_sync_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pendingCountMeta = const VerificationMeta(
    'pendingCount',
  );
  @override
  late final GeneratedColumn<int> pendingCount = GeneratedColumn<int>(
    'pending_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    syncTableName,
    lastSyncAt,
    lastSyncAttemptAt,
    lastSyncError,
    pendingCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_metadata_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetadataEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_table_name')) {
      context.handle(
        _syncTableNameMeta,
        syncTableName.isAcceptableOrUnknown(
          data['sync_table_name']!,
          _syncTableNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_syncTableNameMeta);
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_attempt_at')) {
      context.handle(
        _lastSyncAttemptAtMeta,
        lastSyncAttemptAt.isAcceptableOrUnknown(
          data['last_sync_attempt_at']!,
          _lastSyncAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_error')) {
      context.handle(
        _lastSyncErrorMeta,
        lastSyncError.isAcceptableOrUnknown(
          data['last_sync_error']!,
          _lastSyncErrorMeta,
        ),
      );
    }
    if (data.containsKey('pending_count')) {
      context.handle(
        _pendingCountMeta,
        pendingCount.isAcceptableOrUnknown(
          data['pending_count']!,
          _pendingCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncMetadataEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetadataEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      syncTableName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_table_name'],
      )!,
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
      lastSyncAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_attempt_at'],
      ),
      lastSyncError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_sync_error'],
      ),
      pendingCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pending_count'],
      )!,
    );
  }

  @override
  $SyncMetadataEntriesTable createAlias(String alias) {
    return $SyncMetadataEntriesTable(attachedDatabase, alias);
  }
}

class SyncMetadataEntry extends DataClass
    implements Insertable<SyncMetadataEntry> {
  final int id;
  final String syncTableName;
  final DateTime? lastSyncAt;
  final DateTime? lastSyncAttemptAt;
  final String? lastSyncError;
  final int pendingCount;
  const SyncMetadataEntry({
    required this.id,
    required this.syncTableName,
    this.lastSyncAt,
    this.lastSyncAttemptAt,
    this.lastSyncError,
    required this.pendingCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['sync_table_name'] = Variable<String>(syncTableName);
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
    if (!nullToAbsent || lastSyncAttemptAt != null) {
      map['last_sync_attempt_at'] = Variable<DateTime>(lastSyncAttemptAt);
    }
    if (!nullToAbsent || lastSyncError != null) {
      map['last_sync_error'] = Variable<String>(lastSyncError);
    }
    map['pending_count'] = Variable<int>(pendingCount);
    return map;
  }

  SyncMetadataEntriesCompanion toCompanion(bool nullToAbsent) {
    return SyncMetadataEntriesCompanion(
      id: Value(id),
      syncTableName: Value(syncTableName),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
      lastSyncAttemptAt: lastSyncAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAttemptAt),
      lastSyncError: lastSyncError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncError),
      pendingCount: Value(pendingCount),
    );
  }

  factory SyncMetadataEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetadataEntry(
      id: serializer.fromJson<int>(json['id']),
      syncTableName: serializer.fromJson<String>(json['syncTableName']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
      lastSyncAttemptAt: serializer.fromJson<DateTime?>(
        json['lastSyncAttemptAt'],
      ),
      lastSyncError: serializer.fromJson<String?>(json['lastSyncError']),
      pendingCount: serializer.fromJson<int>(json['pendingCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncTableName': serializer.toJson<String>(syncTableName),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
      'lastSyncAttemptAt': serializer.toJson<DateTime?>(lastSyncAttemptAt),
      'lastSyncError': serializer.toJson<String?>(lastSyncError),
      'pendingCount': serializer.toJson<int>(pendingCount),
    };
  }

  SyncMetadataEntry copyWith({
    int? id,
    String? syncTableName,
    Value<DateTime?> lastSyncAt = const Value.absent(),
    Value<DateTime?> lastSyncAttemptAt = const Value.absent(),
    Value<String?> lastSyncError = const Value.absent(),
    int? pendingCount,
  }) => SyncMetadataEntry(
    id: id ?? this.id,
    syncTableName: syncTableName ?? this.syncTableName,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
    lastSyncAttemptAt: lastSyncAttemptAt.present
        ? lastSyncAttemptAt.value
        : this.lastSyncAttemptAt,
    lastSyncError: lastSyncError.present
        ? lastSyncError.value
        : this.lastSyncError,
    pendingCount: pendingCount ?? this.pendingCount,
  );
  SyncMetadataEntry copyWithCompanion(SyncMetadataEntriesCompanion data) {
    return SyncMetadataEntry(
      id: data.id.present ? data.id.value : this.id,
      syncTableName: data.syncTableName.present
          ? data.syncTableName.value
          : this.syncTableName,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
      lastSyncAttemptAt: data.lastSyncAttemptAt.present
          ? data.lastSyncAttemptAt.value
          : this.lastSyncAttemptAt,
      lastSyncError: data.lastSyncError.present
          ? data.lastSyncError.value
          : this.lastSyncError,
      pendingCount: data.pendingCount.present
          ? data.pendingCount.value
          : this.pendingCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataEntry(')
          ..write('id: $id, ')
          ..write('syncTableName: $syncTableName, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('lastSyncAttemptAt: $lastSyncAttemptAt, ')
          ..write('lastSyncError: $lastSyncError, ')
          ..write('pendingCount: $pendingCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    syncTableName,
    lastSyncAt,
    lastSyncAttemptAt,
    lastSyncError,
    pendingCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetadataEntry &&
          other.id == this.id &&
          other.syncTableName == this.syncTableName &&
          other.lastSyncAt == this.lastSyncAt &&
          other.lastSyncAttemptAt == this.lastSyncAttemptAt &&
          other.lastSyncError == this.lastSyncError &&
          other.pendingCount == this.pendingCount);
}

class SyncMetadataEntriesCompanion extends UpdateCompanion<SyncMetadataEntry> {
  final Value<int> id;
  final Value<String> syncTableName;
  final Value<DateTime?> lastSyncAt;
  final Value<DateTime?> lastSyncAttemptAt;
  final Value<String?> lastSyncError;
  final Value<int> pendingCount;
  const SyncMetadataEntriesCompanion({
    this.id = const Value.absent(),
    this.syncTableName = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.lastSyncAttemptAt = const Value.absent(),
    this.lastSyncError = const Value.absent(),
    this.pendingCount = const Value.absent(),
  });
  SyncMetadataEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String syncTableName,
    this.lastSyncAt = const Value.absent(),
    this.lastSyncAttemptAt = const Value.absent(),
    this.lastSyncError = const Value.absent(),
    this.pendingCount = const Value.absent(),
  }) : syncTableName = Value(syncTableName);
  static Insertable<SyncMetadataEntry> custom({
    Expression<int>? id,
    Expression<String>? syncTableName,
    Expression<DateTime>? lastSyncAt,
    Expression<DateTime>? lastSyncAttemptAt,
    Expression<String>? lastSyncError,
    Expression<int>? pendingCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncTableName != null) 'sync_table_name': syncTableName,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (lastSyncAttemptAt != null) 'last_sync_attempt_at': lastSyncAttemptAt,
      if (lastSyncError != null) 'last_sync_error': lastSyncError,
      if (pendingCount != null) 'pending_count': pendingCount,
    });
  }

  SyncMetadataEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? syncTableName,
    Value<DateTime?>? lastSyncAt,
    Value<DateTime?>? lastSyncAttemptAt,
    Value<String?>? lastSyncError,
    Value<int>? pendingCount,
  }) {
    return SyncMetadataEntriesCompanion(
      id: id ?? this.id,
      syncTableName: syncTableName ?? this.syncTableName,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastSyncAttemptAt: lastSyncAttemptAt ?? this.lastSyncAttemptAt,
      lastSyncError: lastSyncError ?? this.lastSyncError,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncTableName.present) {
      map['sync_table_name'] = Variable<String>(syncTableName.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    if (lastSyncAttemptAt.present) {
      map['last_sync_attempt_at'] = Variable<DateTime>(lastSyncAttemptAt.value);
    }
    if (lastSyncError.present) {
      map['last_sync_error'] = Variable<String>(lastSyncError.value);
    }
    if (pendingCount.present) {
      map['pending_count'] = Variable<int>(pendingCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataEntriesCompanion(')
          ..write('id: $id, ')
          ..write('syncTableName: $syncTableName, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('lastSyncAttemptAt: $lastSyncAttemptAt, ')
          ..write('lastSyncError: $lastSyncError, ')
          ..write('pendingCount: $pendingCount')
          ..write(')'))
        .toString();
  }
}

class $OfflineDataEntriesTable extends OfflineDataEntries
    with TableInfo<$OfflineDataEntriesTable, OfflineDataEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineDataEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, cacheKey, payload, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_data_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineDataEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfflineDataEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineDataEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $OfflineDataEntriesTable createAlias(String alias) {
    return $OfflineDataEntriesTable(attachedDatabase, alias);
  }
}

class OfflineDataEntry extends DataClass
    implements Insertable<OfflineDataEntry> {
  final int id;
  final String cacheKey;
  final String payload;
  final DateTime cachedAt;
  const OfflineDataEntry({
    required this.id,
    required this.cacheKey,
    required this.payload,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cache_key'] = Variable<String>(cacheKey);
    map['payload'] = Variable<String>(payload);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  OfflineDataEntriesCompanion toCompanion(bool nullToAbsent) {
    return OfflineDataEntriesCompanion(
      id: Value(id),
      cacheKey: Value(cacheKey),
      payload: Value(payload),
      cachedAt: Value(cachedAt),
    );
  }

  factory OfflineDataEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineDataEntry(
      id: serializer.fromJson<int>(json['id']),
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      payload: serializer.fromJson<String>(json['payload']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cacheKey': serializer.toJson<String>(cacheKey),
      'payload': serializer.toJson<String>(payload),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  OfflineDataEntry copyWith({
    int? id,
    String? cacheKey,
    String? payload,
    DateTime? cachedAt,
  }) => OfflineDataEntry(
    id: id ?? this.id,
    cacheKey: cacheKey ?? this.cacheKey,
    payload: payload ?? this.payload,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  OfflineDataEntry copyWithCompanion(OfflineDataEntriesCompanion data) {
    return OfflineDataEntry(
      id: data.id.present ? data.id.value : this.id,
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      payload: data.payload.present ? data.payload.value : this.payload,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineDataEntry(')
          ..write('id: $id, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('payload: $payload, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, cacheKey, payload, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineDataEntry &&
          other.id == this.id &&
          other.cacheKey == this.cacheKey &&
          other.payload == this.payload &&
          other.cachedAt == this.cachedAt);
}

class OfflineDataEntriesCompanion extends UpdateCompanion<OfflineDataEntry> {
  final Value<int> id;
  final Value<String> cacheKey;
  final Value<String> payload;
  final Value<DateTime> cachedAt;
  const OfflineDataEntriesCompanion({
    this.id = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.payload = const Value.absent(),
    this.cachedAt = const Value.absent(),
  });
  OfflineDataEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String cacheKey,
    required String payload,
    required DateTime cachedAt,
  }) : cacheKey = Value(cacheKey),
       payload = Value(payload),
       cachedAt = Value(cachedAt);
  static Insertable<OfflineDataEntry> custom({
    Expression<int>? id,
    Expression<String>? cacheKey,
    Expression<String>? payload,
    Expression<DateTime>? cachedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cacheKey != null) 'cache_key': cacheKey,
      if (payload != null) 'payload': payload,
      if (cachedAt != null) 'cached_at': cachedAt,
    });
  }

  OfflineDataEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? cacheKey,
    Value<String>? payload,
    Value<DateTime>? cachedAt,
  }) {
    return OfflineDataEntriesCompanion(
      id: id ?? this.id,
      cacheKey: cacheKey ?? this.cacheKey,
      payload: payload ?? this.payload,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineDataEntriesCompanion(')
          ..write('id: $id, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('payload: $payload, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }
}

class $CollectionRunsTable extends CollectionRuns
    with TableInfo<$CollectionRunsTable, CollectionRun> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acceptedCountMeta = const VerificationMeta(
    'acceptedCount',
  );
  @override
  late final GeneratedColumn<int> acceptedCount = GeneratedColumn<int>(
    'accepted_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    outcome,
    detail,
    acceptedCount,
    startedAt,
    finishedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collection_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionRun> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    } else if (isInserting) {
      context.missing(_outcomeMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    if (data.containsKey('accepted_count')) {
      context.handle(
        _acceptedCountMeta,
        acceptedCount.isAcceptableOrUnknown(
          data['accepted_count']!,
          _acceptedCountMeta,
        ),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_finishedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CollectionRun map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionRun(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      )!,
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      ),
      acceptedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accepted_count'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      )!,
    );
  }

  @override
  $CollectionRunsTable createAlias(String alias) {
    return $CollectionRunsTable(attachedDatabase, alias);
  }
}

class CollectionRun extends DataClass implements Insertable<CollectionRun> {
  final int id;
  final String kind;
  final String outcome;
  final String? detail;
  final int acceptedCount;
  final DateTime startedAt;
  final DateTime finishedAt;
  const CollectionRun({
    required this.id,
    required this.kind,
    required this.outcome,
    this.detail,
    required this.acceptedCount,
    required this.startedAt,
    required this.finishedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    map['outcome'] = Variable<String>(outcome);
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    map['accepted_count'] = Variable<int>(acceptedCount);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['finished_at'] = Variable<DateTime>(finishedAt);
    return map;
  }

  CollectionRunsCompanion toCompanion(bool nullToAbsent) {
    return CollectionRunsCompanion(
      id: Value(id),
      kind: Value(kind),
      outcome: Value(outcome),
      detail: detail == null && nullToAbsent
          ? const Value.absent()
          : Value(detail),
      acceptedCount: Value(acceptedCount),
      startedAt: Value(startedAt),
      finishedAt: Value(finishedAt),
    );
  }

  factory CollectionRun.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionRun(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      outcome: serializer.fromJson<String>(json['outcome']),
      detail: serializer.fromJson<String?>(json['detail']),
      acceptedCount: serializer.fromJson<int>(json['acceptedCount']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      finishedAt: serializer.fromJson<DateTime>(json['finishedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'outcome': serializer.toJson<String>(outcome),
      'detail': serializer.toJson<String?>(detail),
      'acceptedCount': serializer.toJson<int>(acceptedCount),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'finishedAt': serializer.toJson<DateTime>(finishedAt),
    };
  }

  CollectionRun copyWith({
    int? id,
    String? kind,
    String? outcome,
    Value<String?> detail = const Value.absent(),
    int? acceptedCount,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) => CollectionRun(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    outcome: outcome ?? this.outcome,
    detail: detail.present ? detail.value : this.detail,
    acceptedCount: acceptedCount ?? this.acceptedCount,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
  );
  CollectionRun copyWithCompanion(CollectionRunsCompanion data) {
    return CollectionRun(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      detail: data.detail.present ? data.detail.value : this.detail,
      acceptedCount: data.acceptedCount.present
          ? data.acceptedCount.value
          : this.acceptedCount,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionRun(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('outcome: $outcome, ')
          ..write('detail: $detail, ')
          ..write('acceptedCount: $acceptedCount, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    outcome,
    detail,
    acceptedCount,
    startedAt,
    finishedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionRun &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.outcome == this.outcome &&
          other.detail == this.detail &&
          other.acceptedCount == this.acceptedCount &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt);
}

class CollectionRunsCompanion extends UpdateCompanion<CollectionRun> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String> outcome;
  final Value<String?> detail;
  final Value<int> acceptedCount;
  final Value<DateTime> startedAt;
  final Value<DateTime> finishedAt;
  const CollectionRunsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.outcome = const Value.absent(),
    this.detail = const Value.absent(),
    this.acceptedCount = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
  });
  CollectionRunsCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    required String outcome,
    this.detail = const Value.absent(),
    this.acceptedCount = const Value.absent(),
    required DateTime startedAt,
    required DateTime finishedAt,
  }) : kind = Value(kind),
       outcome = Value(outcome),
       startedAt = Value(startedAt),
       finishedAt = Value(finishedAt);
  static Insertable<CollectionRun> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? outcome,
    Expression<String>? detail,
    Expression<int>? acceptedCount,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? finishedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (outcome != null) 'outcome': outcome,
      if (detail != null) 'detail': detail,
      if (acceptedCount != null) 'accepted_count': acceptedCount,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
    });
  }

  CollectionRunsCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<String>? outcome,
    Value<String?>? detail,
    Value<int>? acceptedCount,
    Value<DateTime>? startedAt,
    Value<DateTime>? finishedAt,
  }) {
    return CollectionRunsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      outcome: outcome ?? this.outcome,
      detail: detail ?? this.detail,
      acceptedCount: acceptedCount ?? this.acceptedCount,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (acceptedCount.present) {
      map['accepted_count'] = Variable<int>(acceptedCount.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionRunsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('outcome: $outcome, ')
          ..write('detail: $detail, ')
          ..write('acceptedCount: $acceptedCount, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SensorReadingsTable sensorReadings = $SensorReadingsTable(this);
  late final $PendingImagesTable pendingImages = $PendingImagesTable(this);
  late final $SyncMetadataEntriesTable syncMetadataEntries =
      $SyncMetadataEntriesTable(this);
  late final $OfflineDataEntriesTable offlineDataEntries =
      $OfflineDataEntriesTable(this);
  late final $CollectionRunsTable collectionRuns = $CollectionRunsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sensorReadings,
    pendingImages,
    syncMetadataEntries,
    offlineDataEntries,
    collectionRuns,
  ];
}

typedef $$SensorReadingsTableCreateCompanionBuilder =
    SensorReadingsCompanion Function({
      Value<int> id,
      required double latitude,
      required double longitude,
      required double pressureHpa,
      required DateTime timestamp,
      Value<bool> synced,
      Value<String?> source,
      Value<String?> locationSource,
      Value<DateTime?> locationAt,
    });
typedef $$SensorReadingsTableUpdateCompanionBuilder =
    SensorReadingsCompanion Function({
      Value<int> id,
      Value<double> latitude,
      Value<double> longitude,
      Value<double> pressureHpa,
      Value<DateTime> timestamp,
      Value<bool> synced,
      Value<String?> source,
      Value<String?> locationSource,
      Value<DateTime?> locationAt,
    });

class $$SensorReadingsTableFilterComposer
    extends Composer<_$AppDatabase, $SensorReadingsTable> {
  $$SensorReadingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pressureHpa => $composableBuilder(
    column: $table.pressureHpa,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationSource => $composableBuilder(
    column: $table.locationSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get locationAt => $composableBuilder(
    column: $table.locationAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SensorReadingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SensorReadingsTable> {
  $$SensorReadingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pressureHpa => $composableBuilder(
    column: $table.pressureHpa,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationSource => $composableBuilder(
    column: $table.locationSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get locationAt => $composableBuilder(
    column: $table.locationAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SensorReadingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SensorReadingsTable> {
  $$SensorReadingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get pressureHpa => $composableBuilder(
    column: $table.pressureHpa,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get locationSource => $composableBuilder(
    column: $table.locationSource,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get locationAt => $composableBuilder(
    column: $table.locationAt,
    builder: (column) => column,
  );
}

class $$SensorReadingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SensorReadingsTable,
          SensorReading,
          $$SensorReadingsTableFilterComposer,
          $$SensorReadingsTableOrderingComposer,
          $$SensorReadingsTableAnnotationComposer,
          $$SensorReadingsTableCreateCompanionBuilder,
          $$SensorReadingsTableUpdateCompanionBuilder,
          (
            SensorReading,
            BaseReferences<_$AppDatabase, $SensorReadingsTable, SensorReading>,
          ),
          SensorReading,
          PrefetchHooks Function()
        > {
  $$SensorReadingsTableTableManager(
    _$AppDatabase db,
    $SensorReadingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SensorReadingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SensorReadingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SensorReadingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<double> pressureHpa = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<bool> synced = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> locationSource = const Value.absent(),
                Value<DateTime?> locationAt = const Value.absent(),
              }) => SensorReadingsCompanion(
                id: id,
                latitude: latitude,
                longitude: longitude,
                pressureHpa: pressureHpa,
                timestamp: timestamp,
                synced: synced,
                source: source,
                locationSource: locationSource,
                locationAt: locationAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required double latitude,
                required double longitude,
                required double pressureHpa,
                required DateTime timestamp,
                Value<bool> synced = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> locationSource = const Value.absent(),
                Value<DateTime?> locationAt = const Value.absent(),
              }) => SensorReadingsCompanion.insert(
                id: id,
                latitude: latitude,
                longitude: longitude,
                pressureHpa: pressureHpa,
                timestamp: timestamp,
                synced: synced,
                source: source,
                locationSource: locationSource,
                locationAt: locationAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SensorReadingsTable, SensorReading>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SensorReadingsTable,
                    SensorReading
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SensorReadingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SensorReadingsTable,
      SensorReading,
      $$SensorReadingsTableFilterComposer,
      $$SensorReadingsTableOrderingComposer,
      $$SensorReadingsTableAnnotationComposer,
      $$SensorReadingsTableCreateCompanionBuilder,
      $$SensorReadingsTableUpdateCompanionBuilder,
      (
        SensorReading,
        BaseReferences<_$AppDatabase, $SensorReadingsTable, SensorReading>,
      ),
      SensorReading,
      PrefetchHooks Function()
    >;
typedef $$PendingImagesTableCreateCompanionBuilder =
    PendingImagesCompanion Function({
      Value<int> id,
      required String filePath,
      required double latitude,
      required double longitude,
      Value<String> imageMetadata,
      required DateTime timestamp,
      Value<bool> synced,
    });
typedef $$PendingImagesTableUpdateCompanionBuilder =
    PendingImagesCompanion Function({
      Value<int> id,
      Value<String> filePath,
      Value<double> latitude,
      Value<double> longitude,
      Value<String> imageMetadata,
      Value<DateTime> timestamp,
      Value<bool> synced,
    });

class $$PendingImagesTableFilterComposer
    extends Composer<_$AppDatabase, $PendingImagesTable> {
  $$PendingImagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageMetadata => $composableBuilder(
    column: $table.imageMetadata,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingImagesTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingImagesTable> {
  $$PendingImagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageMetadata => $composableBuilder(
    column: $table.imageMetadata,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingImagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingImagesTable> {
  $$PendingImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<String> get imageMetadata => $composableBuilder(
    column: $table.imageMetadata,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);
}

class $$PendingImagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingImagesTable,
          PendingImage,
          $$PendingImagesTableFilterComposer,
          $$PendingImagesTableOrderingComposer,
          $$PendingImagesTableAnnotationComposer,
          $$PendingImagesTableCreateCompanionBuilder,
          $$PendingImagesTableUpdateCompanionBuilder,
          (
            PendingImage,
            BaseReferences<_$AppDatabase, $PendingImagesTable, PendingImage>,
          ),
          PendingImage,
          PrefetchHooks Function()
        > {
  $$PendingImagesTableTableManager(_$AppDatabase db, $PendingImagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<String> imageMetadata = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<bool> synced = const Value.absent(),
              }) => PendingImagesCompanion(
                id: id,
                filePath: filePath,
                latitude: latitude,
                longitude: longitude,
                imageMetadata: imageMetadata,
                timestamp: timestamp,
                synced: synced,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String filePath,
                required double latitude,
                required double longitude,
                Value<String> imageMetadata = const Value.absent(),
                required DateTime timestamp,
                Value<bool> synced = const Value.absent(),
              }) => PendingImagesCompanion.insert(
                id: id,
                filePath: filePath,
                latitude: latitude,
                longitude: longitude,
                imageMetadata: imageMetadata,
                timestamp: timestamp,
                synced: synced,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingImagesTable, PendingImage>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PendingImagesTable,
                    PendingImage
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingImagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingImagesTable,
      PendingImage,
      $$PendingImagesTableFilterComposer,
      $$PendingImagesTableOrderingComposer,
      $$PendingImagesTableAnnotationComposer,
      $$PendingImagesTableCreateCompanionBuilder,
      $$PendingImagesTableUpdateCompanionBuilder,
      (
        PendingImage,
        BaseReferences<_$AppDatabase, $PendingImagesTable, PendingImage>,
      ),
      PendingImage,
      PrefetchHooks Function()
    >;
typedef $$SyncMetadataEntriesTableCreateCompanionBuilder =
    SyncMetadataEntriesCompanion Function({
      Value<int> id,
      required String syncTableName,
      Value<DateTime?> lastSyncAt,
      Value<DateTime?> lastSyncAttemptAt,
      Value<String?> lastSyncError,
      Value<int> pendingCount,
    });
typedef $$SyncMetadataEntriesTableUpdateCompanionBuilder =
    SyncMetadataEntriesCompanion Function({
      Value<int> id,
      Value<String> syncTableName,
      Value<DateTime?> lastSyncAt,
      Value<DateTime?> lastSyncAttemptAt,
      Value<String?> lastSyncError,
      Value<int> pendingCount,
    });

class $$SyncMetadataEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetadataEntriesTable> {
  $$SyncMetadataEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncTableName => $composableBuilder(
    column: $table.syncTableName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAttemptAt => $composableBuilder(
    column: $table.lastSyncAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pendingCount => $composableBuilder(
    column: $table.pendingCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetadataEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetadataEntriesTable> {
  $$SyncMetadataEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncTableName => $composableBuilder(
    column: $table.syncTableName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAttemptAt => $composableBuilder(
    column: $table.lastSyncAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pendingCount => $composableBuilder(
    column: $table.pendingCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetadataEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetadataEntriesTable> {
  $$SyncMetadataEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syncTableName => $composableBuilder(
    column: $table.syncTableName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncAttemptAt => $composableBuilder(
    column: $table.lastSyncAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pendingCount => $composableBuilder(
    column: $table.pendingCount,
    builder: (column) => column,
  );
}

class $$SyncMetadataEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetadataEntriesTable,
          SyncMetadataEntry,
          $$SyncMetadataEntriesTableFilterComposer,
          $$SyncMetadataEntriesTableOrderingComposer,
          $$SyncMetadataEntriesTableAnnotationComposer,
          $$SyncMetadataEntriesTableCreateCompanionBuilder,
          $$SyncMetadataEntriesTableUpdateCompanionBuilder,
          (
            SyncMetadataEntry,
            BaseReferences<
              _$AppDatabase,
              $SyncMetadataEntriesTable,
              SyncMetadataEntry
            >,
          ),
          SyncMetadataEntry,
          PrefetchHooks Function()
        > {
  $$SyncMetadataEntriesTableTableManager(
    _$AppDatabase db,
    $SyncMetadataEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetadataEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetadataEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SyncMetadataEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> syncTableName = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<DateTime?> lastSyncAttemptAt = const Value.absent(),
                Value<String?> lastSyncError = const Value.absent(),
                Value<int> pendingCount = const Value.absent(),
              }) => SyncMetadataEntriesCompanion(
                id: id,
                syncTableName: syncTableName,
                lastSyncAt: lastSyncAt,
                lastSyncAttemptAt: lastSyncAttemptAt,
                lastSyncError: lastSyncError,
                pendingCount: pendingCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String syncTableName,
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<DateTime?> lastSyncAttemptAt = const Value.absent(),
                Value<String?> lastSyncError = const Value.absent(),
                Value<int> pendingCount = const Value.absent(),
              }) => SyncMetadataEntriesCompanion.insert(
                id: id,
                syncTableName: syncTableName,
                lastSyncAt: lastSyncAt,
                lastSyncAttemptAt: lastSyncAttemptAt,
                lastSyncError: lastSyncError,
                pendingCount: pendingCount,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncMetadataEntriesTable, SyncMetadataEntry>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncMetadataEntriesTable,
                    SyncMetadataEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetadataEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetadataEntriesTable,
      SyncMetadataEntry,
      $$SyncMetadataEntriesTableFilterComposer,
      $$SyncMetadataEntriesTableOrderingComposer,
      $$SyncMetadataEntriesTableAnnotationComposer,
      $$SyncMetadataEntriesTableCreateCompanionBuilder,
      $$SyncMetadataEntriesTableUpdateCompanionBuilder,
      (
        SyncMetadataEntry,
        BaseReferences<
          _$AppDatabase,
          $SyncMetadataEntriesTable,
          SyncMetadataEntry
        >,
      ),
      SyncMetadataEntry,
      PrefetchHooks Function()
    >;
typedef $$OfflineDataEntriesTableCreateCompanionBuilder =
    OfflineDataEntriesCompanion Function({
      Value<int> id,
      required String cacheKey,
      required String payload,
      required DateTime cachedAt,
    });
typedef $$OfflineDataEntriesTableUpdateCompanionBuilder =
    OfflineDataEntriesCompanion Function({
      Value<int> id,
      Value<String> cacheKey,
      Value<String> payload,
      Value<DateTime> cachedAt,
    });

class $$OfflineDataEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineDataEntriesTable> {
  $$OfflineDataEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineDataEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineDataEntriesTable> {
  $$OfflineDataEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineDataEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineDataEntriesTable> {
  $$OfflineDataEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$OfflineDataEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflineDataEntriesTable,
          OfflineDataEntry,
          $$OfflineDataEntriesTableFilterComposer,
          $$OfflineDataEntriesTableOrderingComposer,
          $$OfflineDataEntriesTableAnnotationComposer,
          $$OfflineDataEntriesTableCreateCompanionBuilder,
          $$OfflineDataEntriesTableUpdateCompanionBuilder,
          (
            OfflineDataEntry,
            BaseReferences<
              _$AppDatabase,
              $OfflineDataEntriesTable,
              OfflineDataEntry
            >,
          ),
          OfflineDataEntry,
          PrefetchHooks Function()
        > {
  $$OfflineDataEntriesTableTableManager(
    _$AppDatabase db,
    $OfflineDataEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineDataEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineDataEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflineDataEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> cacheKey = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
              }) => OfflineDataEntriesCompanion(
                id: id,
                cacheKey: cacheKey,
                payload: payload,
                cachedAt: cachedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String cacheKey,
                required String payload,
                required DateTime cachedAt,
              }) => OfflineDataEntriesCompanion.insert(
                id: id,
                cacheKey: cacheKey,
                payload: payload,
                cachedAt: cachedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OfflineDataEntriesTable, OfflineDataEntry>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $OfflineDataEntriesTable,
                    OfflineDataEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineDataEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflineDataEntriesTable,
      OfflineDataEntry,
      $$OfflineDataEntriesTableFilterComposer,
      $$OfflineDataEntriesTableOrderingComposer,
      $$OfflineDataEntriesTableAnnotationComposer,
      $$OfflineDataEntriesTableCreateCompanionBuilder,
      $$OfflineDataEntriesTableUpdateCompanionBuilder,
      (
        OfflineDataEntry,
        BaseReferences<
          _$AppDatabase,
          $OfflineDataEntriesTable,
          OfflineDataEntry
        >,
      ),
      OfflineDataEntry,
      PrefetchHooks Function()
    >;
typedef $$CollectionRunsTableCreateCompanionBuilder =
    CollectionRunsCompanion Function({
      Value<int> id,
      required String kind,
      required String outcome,
      Value<String?> detail,
      Value<int> acceptedCount,
      required DateTime startedAt,
      required DateTime finishedAt,
    });
typedef $$CollectionRunsTableUpdateCompanionBuilder =
    CollectionRunsCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<String> outcome,
      Value<String?> detail,
      Value<int> acceptedCount,
      Value<DateTime> startedAt,
      Value<DateTime> finishedAt,
    });

class $$CollectionRunsTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionRunsTable> {
  $$CollectionRunsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acceptedCount => $composableBuilder(
    column: $table.acceptedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CollectionRunsTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionRunsTable> {
  $$CollectionRunsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acceptedCount => $composableBuilder(
    column: $table.acceptedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionRunsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionRunsTable> {
  $$CollectionRunsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<int> get acceptedCount => $composableBuilder(
    column: $table.acceptedCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );
}

class $$CollectionRunsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionRunsTable,
          CollectionRun,
          $$CollectionRunsTableFilterComposer,
          $$CollectionRunsTableOrderingComposer,
          $$CollectionRunsTableAnnotationComposer,
          $$CollectionRunsTableCreateCompanionBuilder,
          $$CollectionRunsTableUpdateCompanionBuilder,
          (
            CollectionRun,
            BaseReferences<_$AppDatabase, $CollectionRunsTable, CollectionRun>,
          ),
          CollectionRun,
          PrefetchHooks Function()
        > {
  $$CollectionRunsTableTableManager(
    _$AppDatabase db,
    $CollectionRunsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionRunsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionRunsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionRunsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> outcome = const Value.absent(),
                Value<String?> detail = const Value.absent(),
                Value<int> acceptedCount = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime> finishedAt = const Value.absent(),
              }) => CollectionRunsCompanion(
                id: id,
                kind: kind,
                outcome: outcome,
                detail: detail,
                acceptedCount: acceptedCount,
                startedAt: startedAt,
                finishedAt: finishedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                required String outcome,
                Value<String?> detail = const Value.absent(),
                Value<int> acceptedCount = const Value.absent(),
                required DateTime startedAt,
                required DateTime finishedAt,
              }) => CollectionRunsCompanion.insert(
                id: id,
                kind: kind,
                outcome: outcome,
                detail: detail,
                acceptedCount: acceptedCount,
                startedAt: startedAt,
                finishedAt: finishedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CollectionRunsTable, CollectionRun>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CollectionRunsTable,
                    CollectionRun
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CollectionRunsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionRunsTable,
      CollectionRun,
      $$CollectionRunsTableFilterComposer,
      $$CollectionRunsTableOrderingComposer,
      $$CollectionRunsTableAnnotationComposer,
      $$CollectionRunsTableCreateCompanionBuilder,
      $$CollectionRunsTableUpdateCompanionBuilder,
      (
        CollectionRun,
        BaseReferences<_$AppDatabase, $CollectionRunsTable, CollectionRun>,
      ),
      CollectionRun,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SensorReadingsTableTableManager get sensorReadings =>
      $$SensorReadingsTableTableManager(_db, _db.sensorReadings);
  $$PendingImagesTableTableManager get pendingImages =>
      $$PendingImagesTableTableManager(_db, _db.pendingImages);
  $$SyncMetadataEntriesTableTableManager get syncMetadataEntries =>
      $$SyncMetadataEntriesTableTableManager(_db, _db.syncMetadataEntries);
  $$OfflineDataEntriesTableTableManager get offlineDataEntries =>
      $$OfflineDataEntriesTableTableManager(_db, _db.offlineDataEntries);
  $$CollectionRunsTableTableManager get collectionRuns =>
      $$CollectionRunsTableTableManager(_db, _db.collectionRuns);
}
