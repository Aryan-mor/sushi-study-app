// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sushi_catalog.dart';

// ignore_for_file: type=lint
class $CatalogItemsTable extends CatalogItems
    with TableInfo<$CatalogItemsTable, CatalogItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tmdbIdMeta = const VerificationMeta('tmdbId');
  @override
  late final GeneratedColumn<int> tmdbId = GeneratedColumn<int>(
      'tmdb_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
      'kind', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
      'year', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
      'rating', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _posterMeta = const VerificationMeta('poster');
  @override
  late final GeneratedColumn<String> poster = GeneratedColumn<String>(
      'poster', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [tmdbId, kind, title, year, rating, poster];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_items';
  @override
  VerificationContext validateIntegrity(Insertable<CatalogItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tmdb_id')) {
      context.handle(_tmdbIdMeta,
          tmdbId.isAcceptableOrUnknown(data['tmdb_id']!, _tmdbIdMeta));
    } else if (isInserting) {
      context.missing(_tmdbIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('year')) {
      context.handle(
          _yearMeta, year.isAcceptableOrUnknown(data['year']!, _yearMeta));
    } else if (isInserting) {
      context.missing(_yearMeta);
    }
    if (data.containsKey('rating')) {
      context.handle(_ratingMeta,
          rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta));
    } else if (isInserting) {
      context.missing(_ratingMeta);
    }
    if (data.containsKey('poster')) {
      context.handle(_posterMeta,
          poster.isAcceptableOrUnknown(data['poster']!, _posterMeta));
    } else if (isInserting) {
      context.missing(_posterMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tmdbId, kind};
  @override
  CatalogItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogItem(
      tmdbId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tmdb_id'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}kind'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      year: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}year'])!,
      rating: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rating'])!,
      poster: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}poster'])!,
    );
  }

  @override
  $CatalogItemsTable createAlias(String alias) {
    return $CatalogItemsTable(attachedDatabase, alias);
  }
}

class CatalogItem extends DataClass implements Insertable<CatalogItem> {
  final int tmdbId;
  final int kind;
  final String title;
  final int year;
  final int rating;
  final String poster;
  const CatalogItem(
      {required this.tmdbId,
      required this.kind,
      required this.title,
      required this.year,
      required this.rating,
      required this.poster});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tmdb_id'] = Variable<int>(tmdbId);
    map['kind'] = Variable<int>(kind);
    map['title'] = Variable<String>(title);
    map['year'] = Variable<int>(year);
    map['rating'] = Variable<int>(rating);
    map['poster'] = Variable<String>(poster);
    return map;
  }

  CatalogItemsCompanion toCompanion(bool nullToAbsent) {
    return CatalogItemsCompanion(
      tmdbId: Value(tmdbId),
      kind: Value(kind),
      title: Value(title),
      year: Value(year),
      rating: Value(rating),
      poster: Value(poster),
    );
  }

  factory CatalogItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogItem(
      tmdbId: serializer.fromJson<int>(json['tmdbId']),
      kind: serializer.fromJson<int>(json['kind']),
      title: serializer.fromJson<String>(json['title']),
      year: serializer.fromJson<int>(json['year']),
      rating: serializer.fromJson<int>(json['rating']),
      poster: serializer.fromJson<String>(json['poster']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tmdbId': serializer.toJson<int>(tmdbId),
      'kind': serializer.toJson<int>(kind),
      'title': serializer.toJson<String>(title),
      'year': serializer.toJson<int>(year),
      'rating': serializer.toJson<int>(rating),
      'poster': serializer.toJson<String>(poster),
    };
  }

  CatalogItem copyWith(
          {int? tmdbId,
          int? kind,
          String? title,
          int? year,
          int? rating,
          String? poster}) =>
      CatalogItem(
        tmdbId: tmdbId ?? this.tmdbId,
        kind: kind ?? this.kind,
        title: title ?? this.title,
        year: year ?? this.year,
        rating: rating ?? this.rating,
        poster: poster ?? this.poster,
      );
  CatalogItem copyWithCompanion(CatalogItemsCompanion data) {
    return CatalogItem(
      tmdbId: data.tmdbId.present ? data.tmdbId.value : this.tmdbId,
      kind: data.kind.present ? data.kind.value : this.kind,
      title: data.title.present ? data.title.value : this.title,
      year: data.year.present ? data.year.value : this.year,
      rating: data.rating.present ? data.rating.value : this.rating,
      poster: data.poster.present ? data.poster.value : this.poster,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogItem(')
          ..write('tmdbId: $tmdbId, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('year: $year, ')
          ..write('rating: $rating, ')
          ..write('poster: $poster')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tmdbId, kind, title, year, rating, poster);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogItem &&
          other.tmdbId == this.tmdbId &&
          other.kind == this.kind &&
          other.title == this.title &&
          other.year == this.year &&
          other.rating == this.rating &&
          other.poster == this.poster);
}

class CatalogItemsCompanion extends UpdateCompanion<CatalogItem> {
  final Value<int> tmdbId;
  final Value<int> kind;
  final Value<String> title;
  final Value<int> year;
  final Value<int> rating;
  final Value<String> poster;
  final Value<int> rowid;
  const CatalogItemsCompanion({
    this.tmdbId = const Value.absent(),
    this.kind = const Value.absent(),
    this.title = const Value.absent(),
    this.year = const Value.absent(),
    this.rating = const Value.absent(),
    this.poster = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogItemsCompanion.insert({
    required int tmdbId,
    required int kind,
    required String title,
    required int year,
    required int rating,
    required String poster,
    this.rowid = const Value.absent(),
  })  : tmdbId = Value(tmdbId),
        kind = Value(kind),
        title = Value(title),
        year = Value(year),
        rating = Value(rating),
        poster = Value(poster);
  static Insertable<CatalogItem> custom({
    Expression<int>? tmdbId,
    Expression<int>? kind,
    Expression<String>? title,
    Expression<int>? year,
    Expression<int>? rating,
    Expression<String>? poster,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tmdbId != null) 'tmdb_id': tmdbId,
      if (kind != null) 'kind': kind,
      if (title != null) 'title': title,
      if (year != null) 'year': year,
      if (rating != null) 'rating': rating,
      if (poster != null) 'poster': poster,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogItemsCompanion copyWith(
      {Value<int>? tmdbId,
      Value<int>? kind,
      Value<String>? title,
      Value<int>? year,
      Value<int>? rating,
      Value<String>? poster,
      Value<int>? rowid}) {
    return CatalogItemsCompanion(
      tmdbId: tmdbId ?? this.tmdbId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      poster: poster ?? this.poster,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tmdbId.present) {
      map['tmdb_id'] = Variable<int>(tmdbId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (poster.present) {
      map['poster'] = Variable<String>(poster.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogItemsCompanion(')
          ..write('tmdbId: $tmdbId, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('year: $year, ')
          ..write('rating: $rating, ')
          ..write('poster: $poster, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ItemPagesTable extends ItemPages
    with TableInfo<$ItemPagesTable, ItemPage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemPagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tmdbIdMeta = const VerificationMeta('tmdbId');
  @override
  late final GeneratedColumn<int> tmdbId = GeneratedColumn<int>(
      'tmdb_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
      'kind', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _wireMeta = const VerificationMeta('wire');
  @override
  late final GeneratedColumn<Uint8List> wire = GeneratedColumn<Uint8List>(
      'wire', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [tmdbId, kind, wire];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'item_pages';
  @override
  VerificationContext validateIntegrity(Insertable<ItemPage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tmdb_id')) {
      context.handle(_tmdbIdMeta,
          tmdbId.isAcceptableOrUnknown(data['tmdb_id']!, _tmdbIdMeta));
    } else if (isInserting) {
      context.missing(_tmdbIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('wire')) {
      context.handle(
          _wireMeta, wire.isAcceptableOrUnknown(data['wire']!, _wireMeta));
    } else if (isInserting) {
      context.missing(_wireMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tmdbId, kind};
  @override
  ItemPage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ItemPage(
      tmdbId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tmdb_id'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}kind'])!,
      wire: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}wire'])!,
    );
  }

  @override
  $ItemPagesTable createAlias(String alias) {
    return $ItemPagesTable(attachedDatabase, alias);
  }
}

class ItemPage extends DataClass implements Insertable<ItemPage> {
  final int tmdbId;
  final int kind;
  final Uint8List wire;
  const ItemPage(
      {required this.tmdbId, required this.kind, required this.wire});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tmdb_id'] = Variable<int>(tmdbId);
    map['kind'] = Variable<int>(kind);
    map['wire'] = Variable<Uint8List>(wire);
    return map;
  }

  ItemPagesCompanion toCompanion(bool nullToAbsent) {
    return ItemPagesCompanion(
      tmdbId: Value(tmdbId),
      kind: Value(kind),
      wire: Value(wire),
    );
  }

  factory ItemPage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ItemPage(
      tmdbId: serializer.fromJson<int>(json['tmdbId']),
      kind: serializer.fromJson<int>(json['kind']),
      wire: serializer.fromJson<Uint8List>(json['wire']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tmdbId': serializer.toJson<int>(tmdbId),
      'kind': serializer.toJson<int>(kind),
      'wire': serializer.toJson<Uint8List>(wire),
    };
  }

  ItemPage copyWith({int? tmdbId, int? kind, Uint8List? wire}) => ItemPage(
        tmdbId: tmdbId ?? this.tmdbId,
        kind: kind ?? this.kind,
        wire: wire ?? this.wire,
      );
  ItemPage copyWithCompanion(ItemPagesCompanion data) {
    return ItemPage(
      tmdbId: data.tmdbId.present ? data.tmdbId.value : this.tmdbId,
      kind: data.kind.present ? data.kind.value : this.kind,
      wire: data.wire.present ? data.wire.value : this.wire,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ItemPage(')
          ..write('tmdbId: $tmdbId, ')
          ..write('kind: $kind, ')
          ..write('wire: $wire')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tmdbId, kind, $driftBlobEquality.hash(wire));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemPage &&
          other.tmdbId == this.tmdbId &&
          other.kind == this.kind &&
          $driftBlobEquality.equals(other.wire, this.wire));
}

class ItemPagesCompanion extends UpdateCompanion<ItemPage> {
  final Value<int> tmdbId;
  final Value<int> kind;
  final Value<Uint8List> wire;
  final Value<int> rowid;
  const ItemPagesCompanion({
    this.tmdbId = const Value.absent(),
    this.kind = const Value.absent(),
    this.wire = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemPagesCompanion.insert({
    required int tmdbId,
    required int kind,
    required Uint8List wire,
    this.rowid = const Value.absent(),
  })  : tmdbId = Value(tmdbId),
        kind = Value(kind),
        wire = Value(wire);
  static Insertable<ItemPage> custom({
    Expression<int>? tmdbId,
    Expression<int>? kind,
    Expression<Uint8List>? wire,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tmdbId != null) 'tmdb_id': tmdbId,
      if (kind != null) 'kind': kind,
      if (wire != null) 'wire': wire,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemPagesCompanion copyWith(
      {Value<int>? tmdbId,
      Value<int>? kind,
      Value<Uint8List>? wire,
      Value<int>? rowid}) {
    return ItemPagesCompanion(
      tmdbId: tmdbId ?? this.tmdbId,
      kind: kind ?? this.kind,
      wire: wire ?? this.wire,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tmdbId.present) {
      map['tmdb_id'] = Variable<int>(tmdbId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (wire.present) {
      map['wire'] = Variable<Uint8List>(wire.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemPagesCompanion(')
          ..write('tmdbId: $tmdbId, ')
          ..write('kind: $kind, ')
          ..write('wire: $wire, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EpisodeFileListsTable extends EpisodeFileLists
    with TableInfo<$EpisodeFileListsTable, EpisodeFileList> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpisodeFileListsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _episodeIdMeta =
      const VerificationMeta('episodeId');
  @override
  late final GeneratedColumn<int> episodeId = GeneratedColumn<int>(
      'episode_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _filesJsonMeta =
      const VerificationMeta('filesJson');
  @override
  late final GeneratedColumn<String> filesJson = GeneratedColumn<String>(
      'files_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fetchedAtMeta =
      const VerificationMeta('fetchedAt');
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
      'fetched_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [episodeId, filesJson, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'episode_file_lists';
  @override
  VerificationContext validateIntegrity(Insertable<EpisodeFileList> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('episode_id')) {
      context.handle(_episodeIdMeta,
          episodeId.isAcceptableOrUnknown(data['episode_id']!, _episodeIdMeta));
    }
    if (data.containsKey('files_json')) {
      context.handle(_filesJsonMeta,
          filesJson.isAcceptableOrUnknown(data['files_json']!, _filesJsonMeta));
    } else if (isInserting) {
      context.missing(_filesJsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(_fetchedAtMeta,
          fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta));
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {episodeId};
  @override
  EpisodeFileList map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EpisodeFileList(
      episodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}episode_id'])!,
      filesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}files_json'])!,
      fetchedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}fetched_at'])!,
    );
  }

  @override
  $EpisodeFileListsTable createAlias(String alias) {
    return $EpisodeFileListsTable(attachedDatabase, alias);
  }
}

class EpisodeFileList extends DataClass implements Insertable<EpisodeFileList> {
  final int episodeId;
  final String filesJson;
  final DateTime fetchedAt;
  const EpisodeFileList(
      {required this.episodeId,
      required this.filesJson,
      required this.fetchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['episode_id'] = Variable<int>(episodeId);
    map['files_json'] = Variable<String>(filesJson);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  EpisodeFileListsCompanion toCompanion(bool nullToAbsent) {
    return EpisodeFileListsCompanion(
      episodeId: Value(episodeId),
      filesJson: Value(filesJson),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory EpisodeFileList.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EpisodeFileList(
      episodeId: serializer.fromJson<int>(json['episodeId']),
      filesJson: serializer.fromJson<String>(json['filesJson']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'episodeId': serializer.toJson<int>(episodeId),
      'filesJson': serializer.toJson<String>(filesJson),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  EpisodeFileList copyWith(
          {int? episodeId, String? filesJson, DateTime? fetchedAt}) =>
      EpisodeFileList(
        episodeId: episodeId ?? this.episodeId,
        filesJson: filesJson ?? this.filesJson,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
  EpisodeFileList copyWithCompanion(EpisodeFileListsCompanion data) {
    return EpisodeFileList(
      episodeId: data.episodeId.present ? data.episodeId.value : this.episodeId,
      filesJson: data.filesJson.present ? data.filesJson.value : this.filesJson,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EpisodeFileList(')
          ..write('episodeId: $episodeId, ')
          ..write('filesJson: $filesJson, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(episodeId, filesJson, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EpisodeFileList &&
          other.episodeId == this.episodeId &&
          other.filesJson == this.filesJson &&
          other.fetchedAt == this.fetchedAt);
}

class EpisodeFileListsCompanion extends UpdateCompanion<EpisodeFileList> {
  final Value<int> episodeId;
  final Value<String> filesJson;
  final Value<DateTime> fetchedAt;
  const EpisodeFileListsCompanion({
    this.episodeId = const Value.absent(),
    this.filesJson = const Value.absent(),
    this.fetchedAt = const Value.absent(),
  });
  EpisodeFileListsCompanion.insert({
    this.episodeId = const Value.absent(),
    required String filesJson,
    required DateTime fetchedAt,
  })  : filesJson = Value(filesJson),
        fetchedAt = Value(fetchedAt);
  static Insertable<EpisodeFileList> custom({
    Expression<int>? episodeId,
    Expression<String>? filesJson,
    Expression<DateTime>? fetchedAt,
  }) {
    return RawValuesInsertable({
      if (episodeId != null) 'episode_id': episodeId,
      if (filesJson != null) 'files_json': filesJson,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
    });
  }

  EpisodeFileListsCompanion copyWith(
      {Value<int>? episodeId,
      Value<String>? filesJson,
      Value<DateTime>? fetchedAt}) {
    return EpisodeFileListsCompanion(
      episodeId: episodeId ?? this.episodeId,
      filesJson: filesJson ?? this.filesJson,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (episodeId.present) {
      map['episode_id'] = Variable<int>(episodeId.value);
    }
    if (filesJson.present) {
      map['files_json'] = Variable<String>(filesJson.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpisodeFileListsCompanion(')
          ..write('episodeId: $episodeId, ')
          ..write('filesJson: $filesJson, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }
}

class $SeasonEpisodeListsTable extends SeasonEpisodeLists
    with TableInfo<$SeasonEpisodeListsTable, SeasonEpisodeList> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeasonEpisodeListsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tmdbIdMeta = const VerificationMeta('tmdbId');
  @override
  late final GeneratedColumn<int> tmdbId = GeneratedColumn<int>(
      'tmdb_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
      'kind', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _seasonNoMeta =
      const VerificationMeta('seasonNo');
  @override
  late final GeneratedColumn<int> seasonNo = GeneratedColumn<int>(
      'season_no', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _episodesJsonMeta =
      const VerificationMeta('episodesJson');
  @override
  late final GeneratedColumn<String> episodesJson = GeneratedColumn<String>(
      'episodes_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [tmdbId, kind, seasonNo, episodesJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'season_episode_lists';
  @override
  VerificationContext validateIntegrity(Insertable<SeasonEpisodeList> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tmdb_id')) {
      context.handle(_tmdbIdMeta,
          tmdbId.isAcceptableOrUnknown(data['tmdb_id']!, _tmdbIdMeta));
    } else if (isInserting) {
      context.missing(_tmdbIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('season_no')) {
      context.handle(_seasonNoMeta,
          seasonNo.isAcceptableOrUnknown(data['season_no']!, _seasonNoMeta));
    } else if (isInserting) {
      context.missing(_seasonNoMeta);
    }
    if (data.containsKey('episodes_json')) {
      context.handle(
          _episodesJsonMeta,
          episodesJson.isAcceptableOrUnknown(
              data['episodes_json']!, _episodesJsonMeta));
    } else if (isInserting) {
      context.missing(_episodesJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tmdbId, kind, seasonNo};
  @override
  SeasonEpisodeList map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeasonEpisodeList(
      tmdbId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tmdb_id'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}kind'])!,
      seasonNo: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}season_no'])!,
      episodesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}episodes_json'])!,
    );
  }

  @override
  $SeasonEpisodeListsTable createAlias(String alias) {
    return $SeasonEpisodeListsTable(attachedDatabase, alias);
  }
}

class SeasonEpisodeList extends DataClass
    implements Insertable<SeasonEpisodeList> {
  final int tmdbId;
  final int kind;
  final int seasonNo;
  final String episodesJson;
  const SeasonEpisodeList(
      {required this.tmdbId,
      required this.kind,
      required this.seasonNo,
      required this.episodesJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tmdb_id'] = Variable<int>(tmdbId);
    map['kind'] = Variable<int>(kind);
    map['season_no'] = Variable<int>(seasonNo);
    map['episodes_json'] = Variable<String>(episodesJson);
    return map;
  }

  SeasonEpisodeListsCompanion toCompanion(bool nullToAbsent) {
    return SeasonEpisodeListsCompanion(
      tmdbId: Value(tmdbId),
      kind: Value(kind),
      seasonNo: Value(seasonNo),
      episodesJson: Value(episodesJson),
    );
  }

  factory SeasonEpisodeList.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeasonEpisodeList(
      tmdbId: serializer.fromJson<int>(json['tmdbId']),
      kind: serializer.fromJson<int>(json['kind']),
      seasonNo: serializer.fromJson<int>(json['seasonNo']),
      episodesJson: serializer.fromJson<String>(json['episodesJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tmdbId': serializer.toJson<int>(tmdbId),
      'kind': serializer.toJson<int>(kind),
      'seasonNo': serializer.toJson<int>(seasonNo),
      'episodesJson': serializer.toJson<String>(episodesJson),
    };
  }

  SeasonEpisodeList copyWith(
          {int? tmdbId, int? kind, int? seasonNo, String? episodesJson}) =>
      SeasonEpisodeList(
        tmdbId: tmdbId ?? this.tmdbId,
        kind: kind ?? this.kind,
        seasonNo: seasonNo ?? this.seasonNo,
        episodesJson: episodesJson ?? this.episodesJson,
      );
  SeasonEpisodeList copyWithCompanion(SeasonEpisodeListsCompanion data) {
    return SeasonEpisodeList(
      tmdbId: data.tmdbId.present ? data.tmdbId.value : this.tmdbId,
      kind: data.kind.present ? data.kind.value : this.kind,
      seasonNo: data.seasonNo.present ? data.seasonNo.value : this.seasonNo,
      episodesJson: data.episodesJson.present
          ? data.episodesJson.value
          : this.episodesJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeasonEpisodeList(')
          ..write('tmdbId: $tmdbId, ')
          ..write('kind: $kind, ')
          ..write('seasonNo: $seasonNo, ')
          ..write('episodesJson: $episodesJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tmdbId, kind, seasonNo, episodesJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeasonEpisodeList &&
          other.tmdbId == this.tmdbId &&
          other.kind == this.kind &&
          other.seasonNo == this.seasonNo &&
          other.episodesJson == this.episodesJson);
}

class SeasonEpisodeListsCompanion extends UpdateCompanion<SeasonEpisodeList> {
  final Value<int> tmdbId;
  final Value<int> kind;
  final Value<int> seasonNo;
  final Value<String> episodesJson;
  final Value<int> rowid;
  const SeasonEpisodeListsCompanion({
    this.tmdbId = const Value.absent(),
    this.kind = const Value.absent(),
    this.seasonNo = const Value.absent(),
    this.episodesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeasonEpisodeListsCompanion.insert({
    required int tmdbId,
    required int kind,
    required int seasonNo,
    required String episodesJson,
    this.rowid = const Value.absent(),
  })  : tmdbId = Value(tmdbId),
        kind = Value(kind),
        seasonNo = Value(seasonNo),
        episodesJson = Value(episodesJson);
  static Insertable<SeasonEpisodeList> custom({
    Expression<int>? tmdbId,
    Expression<int>? kind,
    Expression<int>? seasonNo,
    Expression<String>? episodesJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tmdbId != null) 'tmdb_id': tmdbId,
      if (kind != null) 'kind': kind,
      if (seasonNo != null) 'season_no': seasonNo,
      if (episodesJson != null) 'episodes_json': episodesJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeasonEpisodeListsCompanion copyWith(
      {Value<int>? tmdbId,
      Value<int>? kind,
      Value<int>? seasonNo,
      Value<String>? episodesJson,
      Value<int>? rowid}) {
    return SeasonEpisodeListsCompanion(
      tmdbId: tmdbId ?? this.tmdbId,
      kind: kind ?? this.kind,
      seasonNo: seasonNo ?? this.seasonNo,
      episodesJson: episodesJson ?? this.episodesJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tmdbId.present) {
      map['tmdb_id'] = Variable<int>(tmdbId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (seasonNo.present) {
      map['season_no'] = Variable<int>(seasonNo.value);
    }
    if (episodesJson.present) {
      map['episodes_json'] = Variable<String>(episodesJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeasonEpisodeListsCompanion(')
          ..write('tmdbId: $tmdbId, ')
          ..write('kind: $kind, ')
          ..write('seasonNo: $seasonNo, ')
          ..write('episodesJson: $episodesJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HomeSnapshotsTable extends HomeSnapshots
    with TableInfo<$HomeSnapshotsTable, HomeSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HomeSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
      'seq', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _ttlMsMeta = const VerificationMeta('ttlMs');
  @override
  late final GeneratedColumn<int> ttlMs = GeneratedColumn<int>(
      'ttl_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _fetchedAtMeta =
      const VerificationMeta('fetchedAt');
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
      'fetched_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, seq, ttlMs, fetchedAt, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'home_snapshots';
  @override
  VerificationContext validateIntegrity(Insertable<HomeSnapshot> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('seq')) {
      context.handle(
          _seqMeta, seq.isAcceptableOrUnknown(data['seq']!, _seqMeta));
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('ttl_ms')) {
      context.handle(
          _ttlMsMeta, ttlMs.isAcceptableOrUnknown(data['ttl_ms']!, _ttlMsMeta));
    } else if (isInserting) {
      context.missing(_ttlMsMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(_fetchedAtMeta,
          fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta));
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HomeSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HomeSnapshot(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      seq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}seq'])!,
      ttlMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ttl_ms'])!,
      fetchedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}fetched_at'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
    );
  }

  @override
  $HomeSnapshotsTable createAlias(String alias) {
    return $HomeSnapshotsTable(attachedDatabase, alias);
  }
}

class HomeSnapshot extends DataClass implements Insertable<HomeSnapshot> {
  final int id;
  final int seq;
  final int ttlMs;
  final DateTime fetchedAt;
  final String payload;
  const HomeSnapshot(
      {required this.id,
      required this.seq,
      required this.ttlMs,
      required this.fetchedAt,
      required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['seq'] = Variable<int>(seq);
    map['ttl_ms'] = Variable<int>(ttlMs);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  HomeSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return HomeSnapshotsCompanion(
      id: Value(id),
      seq: Value(seq),
      ttlMs: Value(ttlMs),
      fetchedAt: Value(fetchedAt),
      payload: Value(payload),
    );
  }

  factory HomeSnapshot.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HomeSnapshot(
      id: serializer.fromJson<int>(json['id']),
      seq: serializer.fromJson<int>(json['seq']),
      ttlMs: serializer.fromJson<int>(json['ttlMs']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'seq': serializer.toJson<int>(seq),
      'ttlMs': serializer.toJson<int>(ttlMs),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  HomeSnapshot copyWith(
          {int? id,
          int? seq,
          int? ttlMs,
          DateTime? fetchedAt,
          String? payload}) =>
      HomeSnapshot(
        id: id ?? this.id,
        seq: seq ?? this.seq,
        ttlMs: ttlMs ?? this.ttlMs,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        payload: payload ?? this.payload,
      );
  HomeSnapshot copyWithCompanion(HomeSnapshotsCompanion data) {
    return HomeSnapshot(
      id: data.id.present ? data.id.value : this.id,
      seq: data.seq.present ? data.seq.value : this.seq,
      ttlMs: data.ttlMs.present ? data.ttlMs.value : this.ttlMs,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HomeSnapshot(')
          ..write('id: $id, ')
          ..write('seq: $seq, ')
          ..write('ttlMs: $ttlMs, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, seq, ttlMs, fetchedAt, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HomeSnapshot &&
          other.id == this.id &&
          other.seq == this.seq &&
          other.ttlMs == this.ttlMs &&
          other.fetchedAt == this.fetchedAt &&
          other.payload == this.payload);
}

class HomeSnapshotsCompanion extends UpdateCompanion<HomeSnapshot> {
  final Value<int> id;
  final Value<int> seq;
  final Value<int> ttlMs;
  final Value<DateTime> fetchedAt;
  final Value<String> payload;
  const HomeSnapshotsCompanion({
    this.id = const Value.absent(),
    this.seq = const Value.absent(),
    this.ttlMs = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.payload = const Value.absent(),
  });
  HomeSnapshotsCompanion.insert({
    this.id = const Value.absent(),
    required int seq,
    required int ttlMs,
    required DateTime fetchedAt,
    required String payload,
  })  : seq = Value(seq),
        ttlMs = Value(ttlMs),
        fetchedAt = Value(fetchedAt),
        payload = Value(payload);
  static Insertable<HomeSnapshot> custom({
    Expression<int>? id,
    Expression<int>? seq,
    Expression<int>? ttlMs,
    Expression<DateTime>? fetchedAt,
    Expression<String>? payload,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seq != null) 'seq': seq,
      if (ttlMs != null) 'ttl_ms': ttlMs,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (payload != null) 'payload': payload,
    });
  }

  HomeSnapshotsCompanion copyWith(
      {Value<int>? id,
      Value<int>? seq,
      Value<int>? ttlMs,
      Value<DateTime>? fetchedAt,
      Value<String>? payload}) {
    return HomeSnapshotsCompanion(
      id: id ?? this.id,
      seq: seq ?? this.seq,
      ttlMs: ttlMs ?? this.ttlMs,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      payload: payload ?? this.payload,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (ttlMs.present) {
      map['ttl_ms'] = Variable<int>(ttlMs.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HomeSnapshotsCompanion(')
          ..write('id: $id, ')
          ..write('seq: $seq, ')
          ..write('ttlMs: $ttlMs, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }
}

class $WatchedEpisodesTable extends WatchedEpisodes
    with TableInfo<$WatchedEpisodesTable, WatchedEpisode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchedEpisodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _episodeIdMeta =
      const VerificationMeta('episodeId');
  @override
  late final GeneratedColumn<int> episodeId = GeneratedColumn<int>(
      'episode_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _doneMeta = const VerificationMeta('done');
  @override
  late final GeneratedColumn<bool> done = GeneratedColumn<bool>(
      'done', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("done" IN (0, 1))'));
  @override
  List<GeneratedColumn> get $columns => [episodeId, done];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watched_episodes';
  @override
  VerificationContext validateIntegrity(Insertable<WatchedEpisode> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('episode_id')) {
      context.handle(_episodeIdMeta,
          episodeId.isAcceptableOrUnknown(data['episode_id']!, _episodeIdMeta));
    }
    if (data.containsKey('done')) {
      context.handle(
          _doneMeta, done.isAcceptableOrUnknown(data['done']!, _doneMeta));
    } else if (isInserting) {
      context.missing(_doneMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {episodeId};
  @override
  WatchedEpisode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchedEpisode(
      episodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}episode_id'])!,
      done: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}done'])!,
    );
  }

  @override
  $WatchedEpisodesTable createAlias(String alias) {
    return $WatchedEpisodesTable(attachedDatabase, alias);
  }
}

class WatchedEpisode extends DataClass implements Insertable<WatchedEpisode> {
  final int episodeId;
  final bool done;
  const WatchedEpisode({required this.episodeId, required this.done});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['episode_id'] = Variable<int>(episodeId);
    map['done'] = Variable<bool>(done);
    return map;
  }

  WatchedEpisodesCompanion toCompanion(bool nullToAbsent) {
    return WatchedEpisodesCompanion(
      episodeId: Value(episodeId),
      done: Value(done),
    );
  }

  factory WatchedEpisode.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchedEpisode(
      episodeId: serializer.fromJson<int>(json['episodeId']),
      done: serializer.fromJson<bool>(json['done']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'episodeId': serializer.toJson<int>(episodeId),
      'done': serializer.toJson<bool>(done),
    };
  }

  WatchedEpisode copyWith({int? episodeId, bool? done}) => WatchedEpisode(
        episodeId: episodeId ?? this.episodeId,
        done: done ?? this.done,
      );
  WatchedEpisode copyWithCompanion(WatchedEpisodesCompanion data) {
    return WatchedEpisode(
      episodeId: data.episodeId.present ? data.episodeId.value : this.episodeId,
      done: data.done.present ? data.done.value : this.done,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchedEpisode(')
          ..write('episodeId: $episodeId, ')
          ..write('done: $done')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(episodeId, done);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchedEpisode &&
          other.episodeId == this.episodeId &&
          other.done == this.done);
}

class WatchedEpisodesCompanion extends UpdateCompanion<WatchedEpisode> {
  final Value<int> episodeId;
  final Value<bool> done;
  const WatchedEpisodesCompanion({
    this.episodeId = const Value.absent(),
    this.done = const Value.absent(),
  });
  WatchedEpisodesCompanion.insert({
    this.episodeId = const Value.absent(),
    required bool done,
  }) : done = Value(done);
  static Insertable<WatchedEpisode> custom({
    Expression<int>? episodeId,
    Expression<bool>? done,
  }) {
    return RawValuesInsertable({
      if (episodeId != null) 'episode_id': episodeId,
      if (done != null) 'done': done,
    });
  }

  WatchedEpisodesCompanion copyWith(
      {Value<int>? episodeId, Value<bool>? done}) {
    return WatchedEpisodesCompanion(
      episodeId: episodeId ?? this.episodeId,
      done: done ?? this.done,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (episodeId.present) {
      map['episode_id'] = Variable<int>(episodeId.value);
    }
    if (done.present) {
      map['done'] = Variable<bool>(done.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchedEpisodesCompanion(')
          ..write('episodeId: $episodeId, ')
          ..write('done: $done')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _watchedWatermarkMeta =
      const VerificationMeta('watchedWatermark');
  @override
  late final GeneratedColumn<int> watchedWatermark = GeneratedColumn<int>(
      'watched_watermark', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, watchedWatermark];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(Insertable<SyncStateData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('watched_watermark')) {
      context.handle(
          _watchedWatermarkMeta,
          watchedWatermark.isAcceptableOrUnknown(
              data['watched_watermark']!, _watchedWatermarkMeta));
    } else if (isInserting) {
      context.missing(_watchedWatermarkMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      watchedWatermark: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}watched_watermark'])!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final int id;
  final int watchedWatermark;
  const SyncStateData({required this.id, required this.watchedWatermark});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['watched_watermark'] = Variable<int>(watchedWatermark);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      id: Value(id),
      watchedWatermark: Value(watchedWatermark),
    );
  }

  factory SyncStateData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      id: serializer.fromJson<int>(json['id']),
      watchedWatermark: serializer.fromJson<int>(json['watchedWatermark']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'watchedWatermark': serializer.toJson<int>(watchedWatermark),
    };
  }

  SyncStateData copyWith({int? id, int? watchedWatermark}) => SyncStateData(
        id: id ?? this.id,
        watchedWatermark: watchedWatermark ?? this.watchedWatermark,
      );
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      id: data.id.present ? data.id.value : this.id,
      watchedWatermark: data.watchedWatermark.present
          ? data.watchedWatermark.value
          : this.watchedWatermark,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('id: $id, ')
          ..write('watchedWatermark: $watchedWatermark')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, watchedWatermark);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.id == this.id &&
          other.watchedWatermark == this.watchedWatermark);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<int> id;
  final Value<int> watchedWatermark;
  const SyncStateCompanion({
    this.id = const Value.absent(),
    this.watchedWatermark = const Value.absent(),
  });
  SyncStateCompanion.insert({
    this.id = const Value.absent(),
    required int watchedWatermark,
  }) : watchedWatermark = Value(watchedWatermark);
  static Insertable<SyncStateData> custom({
    Expression<int>? id,
    Expression<int>? watchedWatermark,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (watchedWatermark != null) 'watched_watermark': watchedWatermark,
    });
  }

  SyncStateCompanion copyWith({Value<int>? id, Value<int>? watchedWatermark}) {
    return SyncStateCompanion(
      id: id ?? this.id,
      watchedWatermark: watchedWatermark ?? this.watchedWatermark,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (watchedWatermark.present) {
      map['watched_watermark'] = Variable<int>(watchedWatermark.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('id: $id, ')
          ..write('watchedWatermark: $watchedWatermark')
          ..write(')'))
        .toString();
  }
}

abstract class _$SushiCatalogDatabase extends GeneratedDatabase {
  _$SushiCatalogDatabase(QueryExecutor e) : super(e);
  $SushiCatalogDatabaseManager get managers =>
      $SushiCatalogDatabaseManager(this);
  late final $CatalogItemsTable catalogItems = $CatalogItemsTable(this);
  late final $ItemPagesTable itemPages = $ItemPagesTable(this);
  late final $EpisodeFileListsTable episodeFileLists =
      $EpisodeFileListsTable(this);
  late final $SeasonEpisodeListsTable seasonEpisodeLists =
      $SeasonEpisodeListsTable(this);
  late final $HomeSnapshotsTable homeSnapshots = $HomeSnapshotsTable(this);
  late final $WatchedEpisodesTable watchedEpisodes =
      $WatchedEpisodesTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        catalogItems,
        itemPages,
        episodeFileLists,
        seasonEpisodeLists,
        homeSnapshots,
        watchedEpisodes,
        syncState
      ];
}

typedef $$CatalogItemsTableCreateCompanionBuilder = CatalogItemsCompanion
    Function({
  required int tmdbId,
  required int kind,
  required String title,
  required int year,
  required int rating,
  required String poster,
  Value<int> rowid,
});
typedef $$CatalogItemsTableUpdateCompanionBuilder = CatalogItemsCompanion
    Function({
  Value<int> tmdbId,
  Value<int> kind,
  Value<String> title,
  Value<int> year,
  Value<int> rating,
  Value<String> poster,
  Value<int> rowid,
});

class $$CatalogItemsTableFilterComposer
    extends Composer<_$SushiCatalogDatabase, $CatalogItemsTable> {
  $$CatalogItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get tmdbId => $composableBuilder(
      column: $table.tmdbId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get poster => $composableBuilder(
      column: $table.poster, builder: (column) => ColumnFilters(column));
}

class $$CatalogItemsTableOrderingComposer
    extends Composer<_$SushiCatalogDatabase, $CatalogItemsTable> {
  $$CatalogItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get tmdbId => $composableBuilder(
      column: $table.tmdbId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get poster => $composableBuilder(
      column: $table.poster, builder: (column) => ColumnOrderings(column));
}

class $$CatalogItemsTableAnnotationComposer
    extends Composer<_$SushiCatalogDatabase, $CatalogItemsTable> {
  $$CatalogItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get tmdbId =>
      $composableBuilder(column: $table.tmdbId, builder: (column) => column);

  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<String> get poster =>
      $composableBuilder(column: $table.poster, builder: (column) => column);
}

class $$CatalogItemsTableTableManager extends RootTableManager<
    _$SushiCatalogDatabase,
    $CatalogItemsTable,
    CatalogItem,
    $$CatalogItemsTableFilterComposer,
    $$CatalogItemsTableOrderingComposer,
    $$CatalogItemsTableAnnotationComposer,
    $$CatalogItemsTableCreateCompanionBuilder,
    $$CatalogItemsTableUpdateCompanionBuilder,
    (
      CatalogItem,
      BaseReferences<_$SushiCatalogDatabase, $CatalogItemsTable, CatalogItem>
    ),
    CatalogItem,
    PrefetchHooks Function()> {
  $$CatalogItemsTableTableManager(
      _$SushiCatalogDatabase db, $CatalogItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatalogItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatalogItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> tmdbId = const Value.absent(),
            Value<int> kind = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int> year = const Value.absent(),
            Value<int> rating = const Value.absent(),
            Value<String> poster = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CatalogItemsCompanion(
            tmdbId: tmdbId,
            kind: kind,
            title: title,
            year: year,
            rating: rating,
            poster: poster,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int tmdbId,
            required int kind,
            required String title,
            required int year,
            required int rating,
            required String poster,
            Value<int> rowid = const Value.absent(),
          }) =>
              CatalogItemsCompanion.insert(
            tmdbId: tmdbId,
            kind: kind,
            title: title,
            year: year,
            rating: rating,
            poster: poster,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CatalogItemsTableProcessedTableManager = ProcessedTableManager<
    _$SushiCatalogDatabase,
    $CatalogItemsTable,
    CatalogItem,
    $$CatalogItemsTableFilterComposer,
    $$CatalogItemsTableOrderingComposer,
    $$CatalogItemsTableAnnotationComposer,
    $$CatalogItemsTableCreateCompanionBuilder,
    $$CatalogItemsTableUpdateCompanionBuilder,
    (
      CatalogItem,
      BaseReferences<_$SushiCatalogDatabase, $CatalogItemsTable, CatalogItem>
    ),
    CatalogItem,
    PrefetchHooks Function()>;
typedef $$ItemPagesTableCreateCompanionBuilder = ItemPagesCompanion Function({
  required int tmdbId,
  required int kind,
  required Uint8List wire,
  Value<int> rowid,
});
typedef $$ItemPagesTableUpdateCompanionBuilder = ItemPagesCompanion Function({
  Value<int> tmdbId,
  Value<int> kind,
  Value<Uint8List> wire,
  Value<int> rowid,
});

class $$ItemPagesTableFilterComposer
    extends Composer<_$SushiCatalogDatabase, $ItemPagesTable> {
  $$ItemPagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get tmdbId => $composableBuilder(
      column: $table.tmdbId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get wire => $composableBuilder(
      column: $table.wire, builder: (column) => ColumnFilters(column));
}

class $$ItemPagesTableOrderingComposer
    extends Composer<_$SushiCatalogDatabase, $ItemPagesTable> {
  $$ItemPagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get tmdbId => $composableBuilder(
      column: $table.tmdbId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get wire => $composableBuilder(
      column: $table.wire, builder: (column) => ColumnOrderings(column));
}

class $$ItemPagesTableAnnotationComposer
    extends Composer<_$SushiCatalogDatabase, $ItemPagesTable> {
  $$ItemPagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get tmdbId =>
      $composableBuilder(column: $table.tmdbId, builder: (column) => column);

  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<Uint8List> get wire =>
      $composableBuilder(column: $table.wire, builder: (column) => column);
}

class $$ItemPagesTableTableManager extends RootTableManager<
    _$SushiCatalogDatabase,
    $ItemPagesTable,
    ItemPage,
    $$ItemPagesTableFilterComposer,
    $$ItemPagesTableOrderingComposer,
    $$ItemPagesTableAnnotationComposer,
    $$ItemPagesTableCreateCompanionBuilder,
    $$ItemPagesTableUpdateCompanionBuilder,
    (
      ItemPage,
      BaseReferences<_$SushiCatalogDatabase, $ItemPagesTable, ItemPage>
    ),
    ItemPage,
    PrefetchHooks Function()> {
  $$ItemPagesTableTableManager(_$SushiCatalogDatabase db, $ItemPagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ItemPagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ItemPagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ItemPagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> tmdbId = const Value.absent(),
            Value<int> kind = const Value.absent(),
            Value<Uint8List> wire = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ItemPagesCompanion(
            tmdbId: tmdbId,
            kind: kind,
            wire: wire,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int tmdbId,
            required int kind,
            required Uint8List wire,
            Value<int> rowid = const Value.absent(),
          }) =>
              ItemPagesCompanion.insert(
            tmdbId: tmdbId,
            kind: kind,
            wire: wire,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ItemPagesTableProcessedTableManager = ProcessedTableManager<
    _$SushiCatalogDatabase,
    $ItemPagesTable,
    ItemPage,
    $$ItemPagesTableFilterComposer,
    $$ItemPagesTableOrderingComposer,
    $$ItemPagesTableAnnotationComposer,
    $$ItemPagesTableCreateCompanionBuilder,
    $$ItemPagesTableUpdateCompanionBuilder,
    (
      ItemPage,
      BaseReferences<_$SushiCatalogDatabase, $ItemPagesTable, ItemPage>
    ),
    ItemPage,
    PrefetchHooks Function()>;
typedef $$EpisodeFileListsTableCreateCompanionBuilder
    = EpisodeFileListsCompanion Function({
  Value<int> episodeId,
  required String filesJson,
  required DateTime fetchedAt,
});
typedef $$EpisodeFileListsTableUpdateCompanionBuilder
    = EpisodeFileListsCompanion Function({
  Value<int> episodeId,
  Value<String> filesJson,
  Value<DateTime> fetchedAt,
});

class $$EpisodeFileListsTableFilterComposer
    extends Composer<_$SushiCatalogDatabase, $EpisodeFileListsTable> {
  $$EpisodeFileListsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get episodeId => $composableBuilder(
      column: $table.episodeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filesJson => $composableBuilder(
      column: $table.filesJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnFilters(column));
}

class $$EpisodeFileListsTableOrderingComposer
    extends Composer<_$SushiCatalogDatabase, $EpisodeFileListsTable> {
  $$EpisodeFileListsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get episodeId => $composableBuilder(
      column: $table.episodeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filesJson => $composableBuilder(
      column: $table.filesJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnOrderings(column));
}

class $$EpisodeFileListsTableAnnotationComposer
    extends Composer<_$SushiCatalogDatabase, $EpisodeFileListsTable> {
  $$EpisodeFileListsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get episodeId =>
      $composableBuilder(column: $table.episodeId, builder: (column) => column);

  GeneratedColumn<String> get filesJson =>
      $composableBuilder(column: $table.filesJson, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$EpisodeFileListsTableTableManager extends RootTableManager<
    _$SushiCatalogDatabase,
    $EpisodeFileListsTable,
    EpisodeFileList,
    $$EpisodeFileListsTableFilterComposer,
    $$EpisodeFileListsTableOrderingComposer,
    $$EpisodeFileListsTableAnnotationComposer,
    $$EpisodeFileListsTableCreateCompanionBuilder,
    $$EpisodeFileListsTableUpdateCompanionBuilder,
    (
      EpisodeFileList,
      BaseReferences<_$SushiCatalogDatabase, $EpisodeFileListsTable,
          EpisodeFileList>
    ),
    EpisodeFileList,
    PrefetchHooks Function()> {
  $$EpisodeFileListsTableTableManager(
      _$SushiCatalogDatabase db, $EpisodeFileListsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EpisodeFileListsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EpisodeFileListsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EpisodeFileListsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> episodeId = const Value.absent(),
            Value<String> filesJson = const Value.absent(),
            Value<DateTime> fetchedAt = const Value.absent(),
          }) =>
              EpisodeFileListsCompanion(
            episodeId: episodeId,
            filesJson: filesJson,
            fetchedAt: fetchedAt,
          ),
          createCompanionCallback: ({
            Value<int> episodeId = const Value.absent(),
            required String filesJson,
            required DateTime fetchedAt,
          }) =>
              EpisodeFileListsCompanion.insert(
            episodeId: episodeId,
            filesJson: filesJson,
            fetchedAt: fetchedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$EpisodeFileListsTableProcessedTableManager = ProcessedTableManager<
    _$SushiCatalogDatabase,
    $EpisodeFileListsTable,
    EpisodeFileList,
    $$EpisodeFileListsTableFilterComposer,
    $$EpisodeFileListsTableOrderingComposer,
    $$EpisodeFileListsTableAnnotationComposer,
    $$EpisodeFileListsTableCreateCompanionBuilder,
    $$EpisodeFileListsTableUpdateCompanionBuilder,
    (
      EpisodeFileList,
      BaseReferences<_$SushiCatalogDatabase, $EpisodeFileListsTable,
          EpisodeFileList>
    ),
    EpisodeFileList,
    PrefetchHooks Function()>;
typedef $$SeasonEpisodeListsTableCreateCompanionBuilder
    = SeasonEpisodeListsCompanion Function({
  required int tmdbId,
  required int kind,
  required int seasonNo,
  required String episodesJson,
  Value<int> rowid,
});
typedef $$SeasonEpisodeListsTableUpdateCompanionBuilder
    = SeasonEpisodeListsCompanion Function({
  Value<int> tmdbId,
  Value<int> kind,
  Value<int> seasonNo,
  Value<String> episodesJson,
  Value<int> rowid,
});

class $$SeasonEpisodeListsTableFilterComposer
    extends Composer<_$SushiCatalogDatabase, $SeasonEpisodeListsTable> {
  $$SeasonEpisodeListsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get tmdbId => $composableBuilder(
      column: $table.tmdbId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get seasonNo => $composableBuilder(
      column: $table.seasonNo, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get episodesJson => $composableBuilder(
      column: $table.episodesJson, builder: (column) => ColumnFilters(column));
}

class $$SeasonEpisodeListsTableOrderingComposer
    extends Composer<_$SushiCatalogDatabase, $SeasonEpisodeListsTable> {
  $$SeasonEpisodeListsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get tmdbId => $composableBuilder(
      column: $table.tmdbId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get seasonNo => $composableBuilder(
      column: $table.seasonNo, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get episodesJson => $composableBuilder(
      column: $table.episodesJson,
      builder: (column) => ColumnOrderings(column));
}

class $$SeasonEpisodeListsTableAnnotationComposer
    extends Composer<_$SushiCatalogDatabase, $SeasonEpisodeListsTable> {
  $$SeasonEpisodeListsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get tmdbId =>
      $composableBuilder(column: $table.tmdbId, builder: (column) => column);

  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get seasonNo =>
      $composableBuilder(column: $table.seasonNo, builder: (column) => column);

  GeneratedColumn<String> get episodesJson => $composableBuilder(
      column: $table.episodesJson, builder: (column) => column);
}

class $$SeasonEpisodeListsTableTableManager extends RootTableManager<
    _$SushiCatalogDatabase,
    $SeasonEpisodeListsTable,
    SeasonEpisodeList,
    $$SeasonEpisodeListsTableFilterComposer,
    $$SeasonEpisodeListsTableOrderingComposer,
    $$SeasonEpisodeListsTableAnnotationComposer,
    $$SeasonEpisodeListsTableCreateCompanionBuilder,
    $$SeasonEpisodeListsTableUpdateCompanionBuilder,
    (
      SeasonEpisodeList,
      BaseReferences<_$SushiCatalogDatabase, $SeasonEpisodeListsTable,
          SeasonEpisodeList>
    ),
    SeasonEpisodeList,
    PrefetchHooks Function()> {
  $$SeasonEpisodeListsTableTableManager(
      _$SushiCatalogDatabase db, $SeasonEpisodeListsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeasonEpisodeListsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeasonEpisodeListsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeasonEpisodeListsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> tmdbId = const Value.absent(),
            Value<int> kind = const Value.absent(),
            Value<int> seasonNo = const Value.absent(),
            Value<String> episodesJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SeasonEpisodeListsCompanion(
            tmdbId: tmdbId,
            kind: kind,
            seasonNo: seasonNo,
            episodesJson: episodesJson,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int tmdbId,
            required int kind,
            required int seasonNo,
            required String episodesJson,
            Value<int> rowid = const Value.absent(),
          }) =>
              SeasonEpisodeListsCompanion.insert(
            tmdbId: tmdbId,
            kind: kind,
            seasonNo: seasonNo,
            episodesJson: episodesJson,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SeasonEpisodeListsTableProcessedTableManager = ProcessedTableManager<
    _$SushiCatalogDatabase,
    $SeasonEpisodeListsTable,
    SeasonEpisodeList,
    $$SeasonEpisodeListsTableFilterComposer,
    $$SeasonEpisodeListsTableOrderingComposer,
    $$SeasonEpisodeListsTableAnnotationComposer,
    $$SeasonEpisodeListsTableCreateCompanionBuilder,
    $$SeasonEpisodeListsTableUpdateCompanionBuilder,
    (
      SeasonEpisodeList,
      BaseReferences<_$SushiCatalogDatabase, $SeasonEpisodeListsTable,
          SeasonEpisodeList>
    ),
    SeasonEpisodeList,
    PrefetchHooks Function()>;
typedef $$HomeSnapshotsTableCreateCompanionBuilder = HomeSnapshotsCompanion
    Function({
  Value<int> id,
  required int seq,
  required int ttlMs,
  required DateTime fetchedAt,
  required String payload,
});
typedef $$HomeSnapshotsTableUpdateCompanionBuilder = HomeSnapshotsCompanion
    Function({
  Value<int> id,
  Value<int> seq,
  Value<int> ttlMs,
  Value<DateTime> fetchedAt,
  Value<String> payload,
});

class $$HomeSnapshotsTableFilterComposer
    extends Composer<_$SushiCatalogDatabase, $HomeSnapshotsTable> {
  $$HomeSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ttlMs => $composableBuilder(
      column: $table.ttlMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));
}

class $$HomeSnapshotsTableOrderingComposer
    extends Composer<_$SushiCatalogDatabase, $HomeSnapshotsTable> {
  $$HomeSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ttlMs => $composableBuilder(
      column: $table.ttlMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));
}

class $$HomeSnapshotsTableAnnotationComposer
    extends Composer<_$SushiCatalogDatabase, $HomeSnapshotsTable> {
  $$HomeSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<int> get ttlMs =>
      $composableBuilder(column: $table.ttlMs, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$HomeSnapshotsTableTableManager extends RootTableManager<
    _$SushiCatalogDatabase,
    $HomeSnapshotsTable,
    HomeSnapshot,
    $$HomeSnapshotsTableFilterComposer,
    $$HomeSnapshotsTableOrderingComposer,
    $$HomeSnapshotsTableAnnotationComposer,
    $$HomeSnapshotsTableCreateCompanionBuilder,
    $$HomeSnapshotsTableUpdateCompanionBuilder,
    (
      HomeSnapshot,
      BaseReferences<_$SushiCatalogDatabase, $HomeSnapshotsTable, HomeSnapshot>
    ),
    HomeSnapshot,
    PrefetchHooks Function()> {
  $$HomeSnapshotsTableTableManager(
      _$SushiCatalogDatabase db, $HomeSnapshotsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HomeSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HomeSnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HomeSnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> seq = const Value.absent(),
            Value<int> ttlMs = const Value.absent(),
            Value<DateTime> fetchedAt = const Value.absent(),
            Value<String> payload = const Value.absent(),
          }) =>
              HomeSnapshotsCompanion(
            id: id,
            seq: seq,
            ttlMs: ttlMs,
            fetchedAt: fetchedAt,
            payload: payload,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int seq,
            required int ttlMs,
            required DateTime fetchedAt,
            required String payload,
          }) =>
              HomeSnapshotsCompanion.insert(
            id: id,
            seq: seq,
            ttlMs: ttlMs,
            fetchedAt: fetchedAt,
            payload: payload,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$HomeSnapshotsTableProcessedTableManager = ProcessedTableManager<
    _$SushiCatalogDatabase,
    $HomeSnapshotsTable,
    HomeSnapshot,
    $$HomeSnapshotsTableFilterComposer,
    $$HomeSnapshotsTableOrderingComposer,
    $$HomeSnapshotsTableAnnotationComposer,
    $$HomeSnapshotsTableCreateCompanionBuilder,
    $$HomeSnapshotsTableUpdateCompanionBuilder,
    (
      HomeSnapshot,
      BaseReferences<_$SushiCatalogDatabase, $HomeSnapshotsTable, HomeSnapshot>
    ),
    HomeSnapshot,
    PrefetchHooks Function()>;
typedef $$WatchedEpisodesTableCreateCompanionBuilder = WatchedEpisodesCompanion
    Function({
  Value<int> episodeId,
  required bool done,
});
typedef $$WatchedEpisodesTableUpdateCompanionBuilder = WatchedEpisodesCompanion
    Function({
  Value<int> episodeId,
  Value<bool> done,
});

class $$WatchedEpisodesTableFilterComposer
    extends Composer<_$SushiCatalogDatabase, $WatchedEpisodesTable> {
  $$WatchedEpisodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get episodeId => $composableBuilder(
      column: $table.episodeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get done => $composableBuilder(
      column: $table.done, builder: (column) => ColumnFilters(column));
}

class $$WatchedEpisodesTableOrderingComposer
    extends Composer<_$SushiCatalogDatabase, $WatchedEpisodesTable> {
  $$WatchedEpisodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get episodeId => $composableBuilder(
      column: $table.episodeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get done => $composableBuilder(
      column: $table.done, builder: (column) => ColumnOrderings(column));
}

class $$WatchedEpisodesTableAnnotationComposer
    extends Composer<_$SushiCatalogDatabase, $WatchedEpisodesTable> {
  $$WatchedEpisodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get episodeId =>
      $composableBuilder(column: $table.episodeId, builder: (column) => column);

  GeneratedColumn<bool> get done =>
      $composableBuilder(column: $table.done, builder: (column) => column);
}

class $$WatchedEpisodesTableTableManager extends RootTableManager<
    _$SushiCatalogDatabase,
    $WatchedEpisodesTable,
    WatchedEpisode,
    $$WatchedEpisodesTableFilterComposer,
    $$WatchedEpisodesTableOrderingComposer,
    $$WatchedEpisodesTableAnnotationComposer,
    $$WatchedEpisodesTableCreateCompanionBuilder,
    $$WatchedEpisodesTableUpdateCompanionBuilder,
    (
      WatchedEpisode,
      BaseReferences<_$SushiCatalogDatabase, $WatchedEpisodesTable,
          WatchedEpisode>
    ),
    WatchedEpisode,
    PrefetchHooks Function()> {
  $$WatchedEpisodesTableTableManager(
      _$SushiCatalogDatabase db, $WatchedEpisodesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchedEpisodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchedEpisodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchedEpisodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> episodeId = const Value.absent(),
            Value<bool> done = const Value.absent(),
          }) =>
              WatchedEpisodesCompanion(
            episodeId: episodeId,
            done: done,
          ),
          createCompanionCallback: ({
            Value<int> episodeId = const Value.absent(),
            required bool done,
          }) =>
              WatchedEpisodesCompanion.insert(
            episodeId: episodeId,
            done: done,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WatchedEpisodesTableProcessedTableManager = ProcessedTableManager<
    _$SushiCatalogDatabase,
    $WatchedEpisodesTable,
    WatchedEpisode,
    $$WatchedEpisodesTableFilterComposer,
    $$WatchedEpisodesTableOrderingComposer,
    $$WatchedEpisodesTableAnnotationComposer,
    $$WatchedEpisodesTableCreateCompanionBuilder,
    $$WatchedEpisodesTableUpdateCompanionBuilder,
    (
      WatchedEpisode,
      BaseReferences<_$SushiCatalogDatabase, $WatchedEpisodesTable,
          WatchedEpisode>
    ),
    WatchedEpisode,
    PrefetchHooks Function()>;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  required int watchedWatermark,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  Value<int> watchedWatermark,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$SushiCatalogDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get watchedWatermark => $composableBuilder(
      column: $table.watchedWatermark,
      builder: (column) => ColumnFilters(column));
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$SushiCatalogDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get watchedWatermark => $composableBuilder(
      column: $table.watchedWatermark,
      builder: (column) => ColumnOrderings(column));
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$SushiCatalogDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get watchedWatermark => $composableBuilder(
      column: $table.watchedWatermark, builder: (column) => column);
}

class $$SyncStateTableTableManager extends RootTableManager<
    _$SushiCatalogDatabase,
    $SyncStateTable,
    SyncStateData,
    $$SyncStateTableFilterComposer,
    $$SyncStateTableOrderingComposer,
    $$SyncStateTableAnnotationComposer,
    $$SyncStateTableCreateCompanionBuilder,
    $$SyncStateTableUpdateCompanionBuilder,
    (
      SyncStateData,
      BaseReferences<_$SushiCatalogDatabase, $SyncStateTable, SyncStateData>
    ),
    SyncStateData,
    PrefetchHooks Function()> {
  $$SyncStateTableTableManager(_$SushiCatalogDatabase db, $SyncStateTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> watchedWatermark = const Value.absent(),
          }) =>
              SyncStateCompanion(
            id: id,
            watchedWatermark: watchedWatermark,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int watchedWatermark,
          }) =>
              SyncStateCompanion.insert(
            id: id,
            watchedWatermark: watchedWatermark,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncStateTableProcessedTableManager = ProcessedTableManager<
    _$SushiCatalogDatabase,
    $SyncStateTable,
    SyncStateData,
    $$SyncStateTableFilterComposer,
    $$SyncStateTableOrderingComposer,
    $$SyncStateTableAnnotationComposer,
    $$SyncStateTableCreateCompanionBuilder,
    $$SyncStateTableUpdateCompanionBuilder,
    (
      SyncStateData,
      BaseReferences<_$SushiCatalogDatabase, $SyncStateTable, SyncStateData>
    ),
    SyncStateData,
    PrefetchHooks Function()>;

class $SushiCatalogDatabaseManager {
  final _$SushiCatalogDatabase _db;
  $SushiCatalogDatabaseManager(this._db);
  $$CatalogItemsTableTableManager get catalogItems =>
      $$CatalogItemsTableTableManager(_db, _db.catalogItems);
  $$ItemPagesTableTableManager get itemPages =>
      $$ItemPagesTableTableManager(_db, _db.itemPages);
  $$EpisodeFileListsTableTableManager get episodeFileLists =>
      $$EpisodeFileListsTableTableManager(_db, _db.episodeFileLists);
  $$SeasonEpisodeListsTableTableManager get seasonEpisodeLists =>
      $$SeasonEpisodeListsTableTableManager(_db, _db.seasonEpisodeLists);
  $$HomeSnapshotsTableTableManager get homeSnapshots =>
      $$HomeSnapshotsTableTableManager(_db, _db.homeSnapshots);
  $$WatchedEpisodesTableTableManager get watchedEpisodes =>
      $$WatchedEpisodesTableTableManager(_db, _db.watchedEpisodes);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
}
