// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sushi_catalog_interest.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sushiCatalogInterestHash() =>
    r'a0a8cd2022eb6520f649079aa6f7fe7231f5769e';

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

abstract class _$SushiCatalogInterest
    extends BuildlessAutoDisposeAsyncNotifier<SushiCatalogInterestState> {
  late final String catalogId;

  FutureOr<SushiCatalogInterestState> build(
    String catalogId,
  );
}

/// See also [SushiCatalogInterest].
@ProviderFor(SushiCatalogInterest)
const sushiCatalogInterestProvider = SushiCatalogInterestFamily();

/// See also [SushiCatalogInterest].
class SushiCatalogInterestFamily
    extends Family<AsyncValue<SushiCatalogInterestState>> {
  /// See also [SushiCatalogInterest].
  const SushiCatalogInterestFamily();

  /// See also [SushiCatalogInterest].
  SushiCatalogInterestProvider call(
    String catalogId,
  ) {
    return SushiCatalogInterestProvider(
      catalogId,
    );
  }

  @override
  SushiCatalogInterestProvider getProviderOverride(
    covariant SushiCatalogInterestProvider provider,
  ) {
    return call(
      provider.catalogId,
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
  String? get name => r'sushiCatalogInterestProvider';
}

/// See also [SushiCatalogInterest].
class SushiCatalogInterestProvider extends AutoDisposeAsyncNotifierProviderImpl<
    SushiCatalogInterest, SushiCatalogInterestState> {
  /// See also [SushiCatalogInterest].
  SushiCatalogInterestProvider(
    String catalogId,
  ) : this._internal(
          () => SushiCatalogInterest()..catalogId = catalogId,
          from: sushiCatalogInterestProvider,
          name: r'sushiCatalogInterestProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$sushiCatalogInterestHash,
          dependencies: SushiCatalogInterestFamily._dependencies,
          allTransitiveDependencies:
              SushiCatalogInterestFamily._allTransitiveDependencies,
          catalogId: catalogId,
        );

  SushiCatalogInterestProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.catalogId,
  }) : super.internal();

  final String catalogId;

  @override
  FutureOr<SushiCatalogInterestState> runNotifierBuild(
    covariant SushiCatalogInterest notifier,
  ) {
    return notifier.build(
      catalogId,
    );
  }

  @override
  Override overrideWith(SushiCatalogInterest Function() create) {
    return ProviderOverride(
      origin: this,
      override: SushiCatalogInterestProvider._internal(
        () => create()..catalogId = catalogId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        catalogId: catalogId,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<SushiCatalogInterest,
      SushiCatalogInterestState> createElement() {
    return _SushiCatalogInterestProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SushiCatalogInterestProvider &&
        other.catalogId == catalogId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, catalogId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin SushiCatalogInterestRef
    on AutoDisposeAsyncNotifierProviderRef<SushiCatalogInterestState> {
  /// The parameter `catalogId` of this provider.
  String get catalogId;
}

class _SushiCatalogInterestProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<SushiCatalogInterest,
        SushiCatalogInterestState> with SushiCatalogInterestRef {
  _SushiCatalogInterestProviderElement(super.provider);

  @override
  String get catalogId => (origin as SushiCatalogInterestProvider).catalogId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
