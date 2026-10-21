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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    latitude,
    longitude,
    pressureHpa,
    timestamp,
    synced,
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
  const SensorReading({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.pressureHpa,
    required this.timestamp,
    required this.synced,
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
    };
  }

  SensorReading copyWith({
    int? id,
    double? latitude,
    double? longitude,
    double? pressureHpa,
    DateTime? timestamp,
    bool? synced,
  }) => SensorReading(
    id: id ?? this.id,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    pressureHpa: pressureHpa ?? this.pressureHpa,
    timestamp: timestamp ?? this.timestamp,
    synced: synced ?? this.synced,
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
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, latitude, longitude, pressureHpa, timestamp, synced);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SensorReading &&
          other.id == this.id &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.pressureHpa == this.pressureHpa &&
          other.timestamp == this.timestamp &&
          other.synced == this.synced);
}

class SensorReadingsCompanion extends UpdateCompanion<SensorReading> {
  final Value<int> id;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double> pressureHpa;
  final Value<DateTime> timestamp;
  final Value<bool> synced;
  const SensorReadingsCompanion({
    this.id = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.pressureHpa = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.synced = const Value.absent(),
  });
  SensorReadingsCompanion.insert({
    this.id = const Value.absent(),
    required double latitude,
    required double longitude,
    required double pressureHpa,
    required DateTime timestamp,
    this.synced = const Value.absent(),
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
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (pressureHpa != null) 'pressure_hpa': pressureHpa,
      if (timestamp != null) 'timestamp': timestamp,
      if (synced != null) 'synced': synced,
    });
  }

  SensorReadingsCompanion copyWith({
    Value<int>? id,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<double>? pressureHpa,
    Value<DateTime>? timestamp,
    Value<bool>? synced,
  }) {
    return SensorReadingsCompanion(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      pressureHpa: pressureHpa ?? this.pressureHpa,
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
          ..write('synced: $synced')
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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SensorReadingsTable sensorReadings = $SensorReadingsTable(this);
  late final $PendingImagesTable pendingImages = $PendingImagesTable(this);
  late final $SyncMetadataEntriesTable syncMetadataEntries =
      $SyncMetadataEntriesTable(this);
  late final $OfflineDataEntriesTable offlineDataEntries =
      $OfflineDataEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sensorReadings,
    pendingImages,
    syncMetadataEntries,
    offlineDataEntries,
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
    });
typedef $$SensorReadingsTableUpdateCompanionBuilder =
    SensorReadingsCompanion Function({
      Value<int> id,
      Value<double> latitude,
      Value<double> longitude,
      Value<double> pressureHpa,
      Value<DateTime> timestamp,
      Value<bool> synced,
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
              }) => SensorReadingsCompanion(
                id: id,
                latitude: latitude,
                longitude: longitude,
                pressureHpa: pressureHpa,
                timestamp: timestamp,
                synced: synced,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required double latitude,
                required double longitude,
                required double pressureHpa,
                required DateTime timestamp,
                Value<bool> synced = const Value.absent(),
              }) => SensorReadingsCompanion.insert(
                id: id,
                latitude: latitude,
                longitude: longitude,
                pressureHpa: pressureHpa,
                timestamp: timestamp,
                synced: synced,
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
}
