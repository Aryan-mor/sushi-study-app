// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sushi_media_issue_context.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sushiMediaIssueContextHash() =>
    r'd9065b65c1baf71f49e50f02b8a238eb51f475f0';

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

/// Seerr-backed media issues removed — always unavailable.
///
/// Copied from [sushiMediaIssueContext].
@ProviderFor(sushiMediaIssueContext)
const sushiMediaIssueContextProvider = SushiMediaIssueContextFamily();

/// Seerr-backed media issues removed — always unavailable.
///
/// Copied from [sushiMediaIssueContext].
class SushiMediaIssueContextFamily
    extends Family<AsyncValue<SushiMediaIssueContext>> {
  /// Seerr-backed media issues removed — always unavailable.
  ///
  /// Copied from [sushiMediaIssueContext].
  const SushiMediaIssueContextFamily();

  /// Seerr-backed media issues removed — always unavailable.
  ///
  /// Copied from [sushiMediaIssueContext].
  SushiMediaIssueContextProvider call(
    SushiMediaIssueTarget target,
  ) {
    return SushiMediaIssueContextProvider(
      target,
    );
  }

  @override
  SushiMediaIssueContextProvider getProviderOverride(
    covariant SushiMediaIssueContextProvider provider,
  ) {
    return call(
      provider.target,
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
  String? get name => r'sushiMediaIssueContextProvider';
}

/// Seerr-backed media issues removed — always unavailable.
///
/// Copied from [sushiMediaIssueContext].
class SushiMediaIssueContextProvider
    extends AutoDisposeFutureProvider<SushiMediaIssueContext> {
  /// Seerr-backed media issues removed — always unavailable.
  ///
  /// Copied from [sushiMediaIssueContext].
  SushiMediaIssueContextProvider(
    SushiMediaIssueTarget target,
  ) : this._internal(
          (ref) => sushiMediaIssueContext(
            ref as SushiMediaIssueContextRef,
            target,
          ),
          from: sushiMediaIssueContextProvider,
          name: r'sushiMediaIssueContextProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$sushiMediaIssueContextHash,
          dependencies: SushiMediaIssueContextFamily._dependencies,
          allTransitiveDependencies:
              SushiMediaIssueContextFamily._allTransitiveDependencies,
          target: target,
        );

  SushiMediaIssueContextProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.target,
  }) : super.internal();

  final SushiMediaIssueTarget target;

  @override
  Override overrideWith(
    FutureOr<SushiMediaIssueContext> Function(
            SushiMediaIssueContextRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SushiMediaIssueContextProvider._internal(
        (ref) => create(ref as SushiMediaIssueContextRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        target: target,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<SushiMediaIssueContext> createElement() {
    return _SushiMediaIssueContextProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SushiMediaIssueContextProvider && other.target == target;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, target.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin SushiMediaIssueContextRef
    on AutoDisposeFutureProviderRef<SushiMediaIssueContext> {
  /// The parameter `target` of this provider.
  SushiMediaIssueTarget get target;
}

class _SushiMediaIssueContextProviderElement
    extends AutoDisposeFutureProviderElement<SushiMediaIssueContext>
    with SushiMediaIssueContextRef {
  _SushiMediaIssueContextProviderElement(super.provider);

  @override
  SushiMediaIssueTarget get target =>
      (origin as SushiMediaIssueContextProvider).target;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
