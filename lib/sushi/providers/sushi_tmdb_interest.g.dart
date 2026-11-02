// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sushi_tmdb_interest.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sushiTmdbInterestHash() => r'e52d403c9160bf5a8922f3bd3f4eac138ef044fc';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$SushiTmdbInterest
    extends BuildlessAutoDisposeAsyncNotifier<SushiTmdbInterestState> {
  late final int tmdbId;
  late final SushiTmdbMediaType mediaType;

  FutureOr<SushiTmdbInterestState> build(
    int tmdbId,
    SushiTmdbMediaType mediaType,
  );
}

/// See also [SushiTmdbInterest].
@ProviderFor(SushiTmdbInterest)
const sushiTmdbInterestProvider = SushiTmdbInterestFamily();

/// See also [SushiTmdbInterest].
class SushiTmdbInterestFamily
    extends Family<AsyncValue<SushiTmdbInterestState>> {
  /// See also [SushiTmdbInterest].
  const SushiTmdbInterestFamily();

  /// See also [SushiTmdbInterest].
  SushiTmdbInterestProvider call(
    int tmdbId,
    SushiTmdbMediaType mediaType,
  ) {
    return SushiTmdbInterestProvider(
      tmdbId,
      mediaType,
    );
  }

  @override
  SushiTmdbInterestProvider getProviderOverride(
    covariant SushiTmdbInterestProvider provider,
  ) {
    return call(
      provider.tmdbId,
      provider.mediaType,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'sushiTmdbInterestProvider';
}

/// See also [SushiTmdbInterest].
class SushiTmdbInterestProvider extends AutoDisposeAsyncNotifierProviderImpl<
    SushiTmdbInterest, SushiTmdbInterestState> {
  /// See also [SushiTmdbInterest].
  SushiTmdbInterestProvider(
    int tmdbId,
    SushiTmdbMediaType mediaType,
  ) : this._internal(
          () => SushiTmdbInterest()
            ..tmdbId = tmdbId
            ..mediaType = mediaType,
          from: sushiTmdbInterestProvider,
          name: r'sushiTmdbInterestProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$sushiTmdbInterestHash,
          dependencies: SushiTmdbInterestFamily._dependencies,
          allTransitiveDependencies:
              SushiTmdbInterestFamily._allTransitiveDependencies,
          tmdbId: tmdbId,
          mediaType: mediaType,
        );

  SushiTmdbInterestProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.tmdbId,
    required this.mediaType,
  }) : super.internal();

  final int tmdbId;
  final SushiTmdbMediaType mediaType;

  @override
  FutureOr<SushiTmdbInterestState> runNotifierBuild(
    covariant SushiTmdbInterest notifier,
  ) {
    return notifier.build(
      tmdbId,
      mediaType,
    );
  }

  @override
  Override overrideWith(SushiTmdbInterest Function() create) {
    return ProviderOverride(
      origin: this,
      override: SushiTmdbInterestProvider._internal(
        () => create()
          ..tmdbId = tmdbId
          ..mediaType = mediaType,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        tmdbId: tmdbId,
        mediaType: mediaType,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<SushiTmdbInterest,
      SushiTmdbInterestState> createElement() {
    return _SushiTmdbInterestProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SushiTmdbInterestProvider &&
        other.tmdbId == tmdbId &&
        other.mediaType == mediaType;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, tmdbId.hashCode);
    hash = _SystemHash.combine(hash, mediaType.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin SushiTmdbInterestRef
    on AutoDisposeAsyncNotifierProviderRef<SushiTmdbInterestState> {
  /// The parameter `tmdbId` of this provider.
  int get tmdbId;

  /// The parameter `mediaType` of this provider.
  SushiTmdbMediaType get mediaType;
}

class _SushiTmdbInterestProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<SushiTmdbInterest,
        SushiTmdbInterestState> with SushiTmdbInterestRef {
  _SushiTmdbInterestProviderElement(super.provider);

  @override
  int get tmdbId => (origin as SushiTmdbInterestProvider).tmdbId;
  @override
  SushiTmdbMediaType get mediaType =>
      (origin as SushiTmdbInterestProvider).mediaType;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
