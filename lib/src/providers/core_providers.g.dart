// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'core_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(sphConfig)
const sphConfigProvider = SphConfigProvider._();

final class SphConfigProvider
    extends
        $FunctionalProvider<SphClientConfig, SphClientConfig, SphClientConfig>
    with $Provider<SphClientConfig> {
  const SphConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sphConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sphConfigHash();

  @$internal
  @override
  $ProviderElement<SphClientConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SphClientConfig create(Ref ref) {
    return sphConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SphClientConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SphClientConfig>(value),
    );
  }
}

String _$sphConfigHash() => r'c729573fdefe799e6608f810904cdeba30372270';

@ProviderFor(lanisDatabase)
const lanisDatabaseProvider = LanisDatabaseProvider._();

final class LanisDatabaseProvider
    extends $FunctionalProvider<LanisDatabase, LanisDatabase, LanisDatabase>
    with $Provider<LanisDatabase> {
  const LanisDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lanisDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lanisDatabaseHash();

  @$internal
  @override
  $ProviderElement<LanisDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LanisDatabase create(Ref ref) {
    return lanisDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LanisDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LanisDatabase>(value),
    );
  }
}

String _$lanisDatabaseHash() => r'63f3cf94df11a2ebe8fbde7dedc3052766f87606';

@ProviderFor(connectionChecker)
const connectionCheckerProvider = ConnectionCheckerProvider._();

final class ConnectionCheckerProvider
    extends
        $FunctionalProvider<
          ConnectionChecker,
          ConnectionChecker,
          ConnectionChecker
        >
    with $Provider<ConnectionChecker> {
  const ConnectionCheckerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionCheckerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionCheckerHash();

  @$internal
  @override
  $ProviderElement<ConnectionChecker> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConnectionChecker create(Ref ref) {
    return connectionChecker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionChecker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionChecker>(value),
    );
  }
}

String _$connectionCheckerHash() => r'b7d4f9b3f17d58858958037dbb433bbbc0ecdbb1';

@ProviderFor(connectionStatus)
const connectionStatusProvider = ConnectionStatusProvider._();

final class ConnectionStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConnectionStatus>,
          ConnectionStatus,
          Stream<ConnectionStatus>
        >
    with $FutureModifier<ConnectionStatus>, $StreamProvider<ConnectionStatus> {
  const ConnectionStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionStatusHash();

  @$internal
  @override
  $StreamProviderElement<ConnectionStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ConnectionStatus> create(Ref ref) {
    return connectionStatus(ref);
  }
}

String _$connectionStatusHash() => r'd5e2383da9553faa3b8db642e81da9d846ac56ce';

@ProviderFor(Accounts)
const accountsProvider = AccountsProvider._();

final class AccountsProvider
    extends $AsyncNotifierProvider<Accounts, List<AccountSummary>> {
  const AccountsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountsHash();

  @$internal
  @override
  Accounts create() => Accounts();
}

String _$accountsHash() => r'3cf8519e5d30a8031578ab408d741607b2a7ad43';

abstract class _$Accounts extends $AsyncNotifier<List<AccountSummary>> {
  FutureOr<List<AccountSummary>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref
            as $Ref<AsyncValue<List<AccountSummary>>, List<AccountSummary>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<AccountSummary>>,
                List<AccountSummary>
              >,
              AsyncValue<List<AccountSummary>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Identity of the active account. [Session] watches this (not the full
/// [ClearTextAccount]) so [ActiveAccount.replace] does not tear down dio.

@ProviderFor(ActiveAccountId)
const activeAccountIdProvider = ActiveAccountIdProvider._();

/// Identity of the active account. [Session] watches this (not the full
/// [ClearTextAccount]) so [ActiveAccount.replace] does not tear down dio.
final class ActiveAccountIdProvider
    extends $NotifierProvider<ActiveAccountId, int?> {
  /// Identity of the active account. [Session] watches this (not the full
  /// [ClearTextAccount]) so [ActiveAccount.replace] does not tear down dio.
  const ActiveAccountIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeAccountIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeAccountIdHash();

  @$internal
  @override
  ActiveAccountId create() => ActiveAccountId();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }
}

String _$activeAccountIdHash() => r'8010b04405e01d08389999c6a262d7708d89180b';

/// Identity of the active account. [Session] watches this (not the full
/// [ClearTextAccount]) so [ActiveAccount.replace] does not tear down dio.

abstract class _$ActiveAccountId extends $Notifier<int?> {
  int? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<int?, int?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int?, int?>,
              int?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(ActiveAccount)
const activeAccountProvider = ActiveAccountProvider._();

final class ActiveAccountProvider
    extends $NotifierProvider<ActiveAccount, ClearTextAccount?> {
  const ActiveAccountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeAccountProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeAccountHash();

  @$internal
  @override
  ActiveAccount create() => ActiveAccount();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClearTextAccount? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClearTextAccount?>(value),
    );
  }
}

String _$activeAccountHash() => r'f91dcc92a5ca20417d18b147719e2a70a77297da';

abstract class _$ActiveAccount extends $Notifier<ClearTextAccount?> {
  ClearTextAccount? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ClearTextAccount?, ClearTextAccount?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ClearTextAccount?, ClearTextAccount?>,
              ClearTextAccount?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(Session)
const sessionProvider = SessionProvider._();

final class SessionProvider
    extends $AsyncNotifierProvider<Session, SessionHandler?> {
  const SessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionHash();

  @$internal
  @override
  Session create() => Session();
}

String _$sessionHash() => r'214e4ea129b6ece0ba47bea857d946fdb122f7b8';

abstract class _$Session extends $AsyncNotifier<SessionHandler?> {
  FutureOr<SessionHandler?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<SessionHandler?>, SessionHandler?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SessionHandler?>, SessionHandler?>,
              AsyncValue<SessionHandler?>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(sharedOverAccountSettings)
const sharedOverAccountSettingsProvider = SharedOverAccountSettingsProvider._();

final class SharedOverAccountSettingsProvider
    extends $FunctionalProvider<TypedSettings, TypedSettings, TypedSettings>
    with $Provider<TypedSettings> {
  const SharedOverAccountSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sharedOverAccountSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sharedOverAccountSettingsHash();

  @$internal
  @override
  $ProviderElement<TypedSettings> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TypedSettings create(Ref ref) {
    return sharedOverAccountSettings(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TypedSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TypedSettings>(value),
    );
  }
}

String _$sharedOverAccountSettingsHash() =>
    r'21a0615830a1f7e00765e02c10f42a1fa27ec910';

@ProviderFor(accountSpecificSettings)
const accountSpecificSettingsProvider = AccountSpecificSettingsProvider._();

final class AccountSpecificSettingsProvider
    extends $FunctionalProvider<TypedSettings?, TypedSettings?, TypedSettings?>
    with $Provider<TypedSettings?> {
  const AccountSpecificSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountSpecificSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountSpecificSettingsHash();

  @$internal
  @override
  $ProviderElement<TypedSettings?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TypedSettings? create(Ref ref) {
    return accountSpecificSettings(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TypedSettings? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TypedSettings?>(value),
    );
  }
}

String _$accountSpecificSettingsHash() =>
    r'2d45be0868664822fc72e1c92af6f22327522a26';

@ProviderFor(storageManager)
const storageManagerProvider = StorageManagerProvider._();

final class StorageManagerProvider
    extends
        $FunctionalProvider<StorageManager?, StorageManager?, StorageManager?>
    with $Provider<StorageManager?> {
  const StorageManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'storageManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$storageManagerHash();

  @$internal
  @override
  $ProviderElement<StorageManager?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  StorageManager? create(Ref ref) {
    return storageManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StorageManager? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StorageManager?>(value),
    );
  }
}

String _$storageManagerHash() => r'73ba613f27ceb2b371cc567e7375e5f17f0cf6d5';

/// PHP applet URLs supported by the current authenticated session + account type.

@ProviderFor(supportedAppletPhpUrls)
const supportedAppletPhpUrlsProvider = SupportedAppletPhpUrlsProvider._();

/// PHP applet URLs supported by the current authenticated session + account type.

final class SupportedAppletPhpUrlsProvider
    extends $FunctionalProvider<Set<String>, Set<String>, Set<String>>
    with $Provider<Set<String>> {
  /// PHP applet URLs supported by the current authenticated session + account type.
  const SupportedAppletPhpUrlsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'supportedAppletPhpUrlsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$supportedAppletPhpUrlsHash();

  @$internal
  @override
  $ProviderElement<Set<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Set<String> create(Ref ref) {
    return supportedAppletPhpUrls(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$supportedAppletPhpUrlsHash() =>
    r'd65ee5482a8db7e2ed9ca9134fc9bcb32fb32484';
