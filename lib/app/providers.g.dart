// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(appRuntime)
final appRuntimeProvider = AppRuntimeProvider._();

final class AppRuntimeProvider
    extends $FunctionalProvider<AppRuntime, AppRuntime, AppRuntime>
    with $Provider<AppRuntime> {
  AppRuntimeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appRuntimeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appRuntimeHash();

  @$internal
  @override
  $ProviderElement<AppRuntime> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppRuntime create(Ref ref) {
    return appRuntime(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppRuntime value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppRuntime>(value),
    );
  }
}

String _$appRuntimeHash() => r'd5a9777b6d1e24f79e15e5b368ce743362d9a6a4';

@ProviderFor(AppLanguage)
final appLanguageProvider = AppLanguageProvider._();

final class AppLanguageProvider extends $NotifierProvider<AppLanguage, Locale> {
  AppLanguageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appLanguageProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appLanguageHash();

  @$internal
  @override
  AppLanguage create() => AppLanguage();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Locale value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Locale>(value),
    );
  }
}

String _$appLanguageHash() => r'4070279d0fe33d604c5874da930ea1dcd86ca998';

abstract class _$AppLanguage extends $Notifier<Locale> {
  Locale build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Locale, Locale>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Locale, Locale>,
              Locale,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
