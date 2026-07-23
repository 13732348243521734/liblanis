import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config.dart';
import '../connection/connection_checker.dart';
import '../database/database.dart';
import '../exceptions.dart';
import '../models/account.dart';
import '../models/account_types.dart';
import '../session/session.dart';
import '../settings/typed_settings.dart';
import '../storage/storage_manager.dart';
import '../applets/definition.dart';

part 'core_providers.g.dart';

@Riverpod(keepAlive: true)
SphClientConfig sphConfig(Ref ref) {
  throw ConfigurationException(
    'SPHClient is not configured. Call SPHClient.configure and apply overrides.',
  );
}

@Riverpod(keepAlive: true)
LanisDatabase lanisDatabase(Ref ref) {
  final config = ref.watch(sphConfigProvider);
  final db = LanisDatabase.open(
    path: config.databasePath,
    secretStore: config.secretStore,
  );
  ref.onDispose(db.dispose);
  return db;
}

@Riverpod(keepAlive: true)
ConnectionChecker connectionChecker(Ref ref) {
  final config = ref.watch(sphConfigProvider);
  final checker = ConnectionChecker(httpAdapter: config.httpAdapter);
  ref.onDispose(checker.dispose);
  return checker;
}

@Riverpod(keepAlive: true)
Stream<ConnectionStatus> connectionStatus(Ref ref) {
  final checker = ref.watch(connectionCheckerProvider);
  return Stream.multi((controller) async {
    controller.add(checker.status);
    final sub = checker.statusStream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    ref.onDispose(sub.cancel);
  });
}

@Riverpod(keepAlive: true)
class Accounts extends _$Accounts {
  @override
  Future<List<AccountSummary>> build() async {
    final db = ref.watch(lanisDatabaseProvider);
    return db.listAccounts();
  }

  Future<int> add({
    required int schoolId,
    required String schoolName,
    required String username,
    required String password,
    AccountType? accountType,
  }) async {
    final db = ref.read(lanisDatabaseProvider);
    final id = await db.addAccount(
      schoolId: schoolId,
      schoolName: schoolName,
      username: username,
      password: password,
      accountType: accountType,
    );
    ref.invalidateSelf();
    return id;
  }

  Future<void> remove(int id) async {
    final db = ref.read(lanisDatabaseProvider);
    final active = ref.read(activeAccountProvider);
    await db.deleteAccount(id);
    if (active?.localId == id) {
      await ref.read(activeAccountProvider.notifier).clear();
    }
    ref.invalidateSelf();
  }

  Future<void> setAccountType(int id, AccountType type) async {
    await ref.read(lanisDatabaseProvider).setAccountType(id, type);
    ref.invalidateSelf();
    final active = ref.read(activeAccountProvider);
    if (active?.localId == id) {
      final updated = await ref.read(lanisDatabaseProvider).getAccount(id);
      if (updated != null) {
        // replace keeps the live session; select() would tear it down.
        ref.read(activeAccountProvider.notifier).replace(updated);
      }
    }
  }

  Future<void> updatePassword(int id, String password) async {
    await ref.read(lanisDatabaseProvider).updatePassword(id, password);
  }
}

/// Identity of the active account. [Session] watches this (not the full
/// [ClearTextAccount]) so [ActiveAccount.replace] does not tear down dio.
@Riverpod(keepAlive: true)
class ActiveAccountId extends _$ActiveAccountId {
  @override
  int? build() => null;

  void setId(int? id) => state = id;
}

@Riverpod(keepAlive: true)
class ActiveAccount extends _$ActiveAccount {
  @override
  ClearTextAccount? build() => null;

  Future<void> select(int accountId) async {
    final db = ref.read(lanisDatabaseProvider);
    final account = await db.getAccount(accountId);
    if (account == null) {
      throw UnknownException('Account $accountId not found');
    }

    final previous = state;
    if (previous != null && previous.localId != accountId) {
      final oldSession = ref.read(sessionProvider).asData?.value;
      try {
        await oldSession?.deAuthenticate();
      } catch (_) {}
    }

    state = account;
    final previousId = ref.read(activeAccountIdProvider);
    ref.read(activeAccountIdProvider.notifier).setId(accountId);
    // Session watches [activeAccountIdProvider] and rebuilds on id change.
    // Only force-invalidate when re-selecting the same account.
    if (previousId == accountId) {
      ref.invalidate(sessionProvider);
    }
  }

  Future<void> selectPreferred() async {
    final db = ref.read(lanisDatabaseProvider);
    final account = await db.getPreferredStartupAccount();
    if (account == null) {
      await clear();
      return;
    }
    await select(account.localId);
  }

  /// Clears the active account. Awaits logout HTTP before dropping the session.
  Future<void> clear({bool skipDeauthenticate = false}) async {
    final oldSession = ref.read(sessionProvider).asData?.value;
    if (!skipDeauthenticate && oldSession != null) {
      try {
        await oldSession.deAuthenticate();
      } catch (_) {}
    }
    state = null;
    // Session watches [activeAccountIdProvider]; do not invalidate session in
    // the same turn (CircularDependencyError risk).
    ref.read(activeAccountIdProvider.notifier).setId(null);
  }

  /// Replace the in-memory account snapshot (e.g. after accountType is known).
  /// Does not change [activeAccountIdProvider], so the live session stays.
  void replace(ClearTextAccount account) {
    state = account;
  }
}

@Riverpod(keepAlive: true)
class Session extends _$Session {
  @override
  FutureOr<SessionHandler?> build() async {
    final accountId = ref.watch(activeAccountIdProvider);
    if (accountId == null) return null;
    final account = ref.read(activeAccountProvider);
    if (account == null || account.localId != accountId) return null;

    final config = ref.watch(sphConfigProvider);
    final checker = ref.watch(connectionCheckerProvider);
    final session = SessionHandler(
      account: account,
      config: config,
      connectionChecker: checker,
    );
    await session.prepareDio();
    ref.onDispose(session.dispose);
    return session;
  }

  Future<SessionHandler> authenticate({
    String? withLoginUrl,
    bool withoutData = false,
  }) async {
    final session = await future;
    if (session == null) {
      throw ConfigurationException('No active account selected');
    }
    await session.authenticate(
      withLoginUrl: withLoginUrl,
      withoutData: withoutData,
    );
    final db = ref.read(lanisDatabaseProvider);
    await db.updateLastLogin(session.account.localId);
    if (session.account.accountType == null) {
      final detectedType = session.accountTypeOrNull;
      if (detectedType != null) {
        await db.setAccountType(session.account.localId, detectedType);
        // Refresh active account snapshot so accountType is visible to UI.
        // Safe: Session.build watches localId only, so this does not rebuild.
        final updated = await db.getAccount(session.account.localId);
        if (updated != null) {
          ref.read(activeAccountProvider.notifier).replace(updated);
        }
      }
    }
    // Notify listeners: travelMenu / accountType are mutated on [session].
    // Same SessionHandler instance may already be in [state], so AsyncData
    // equality would skip notifications — bump the feature epoch instead.
    // Never invalidate supportedAppletPhpUrlsProvider in this turn (circular).
    state = AsyncData(session);
    ref.read(sessionFeatureEpochProvider.notifier).bump();
    ref.invalidate(accountsProvider);
    return session;
  }

  Future<void> deAuthenticate() async {
    final session = await future;
    await session?.deAuthenticate();
    if (session != null) {
      state = AsyncData(session);
    }
  }
}

@Riverpod(keepAlive: true)
TypedSettings sharedOverAccountSettings(Ref ref) {
  final db = ref.watch(lanisDatabaseProvider);
  return TypedSettings.shared(db);
}

@Riverpod(keepAlive: true)
TypedSettings? accountSpecificSettings(Ref ref) {
  final account = ref.watch(activeAccountProvider);
  if (account == null) return null;
  final db = ref.watch(lanisDatabaseProvider);
  return TypedSettings.account(db, account.localId);
}

@Riverpod(keepAlive: true)
StorageManager? storageManager(Ref ref) {
  final config = ref.watch(sphConfigProvider);
  final account = ref.watch(activeAccountProvider);
  final sessionAsync = ref.watch(sessionProvider);
  final session = sessionAsync.asData?.value;
  if (account == null || session == null) return null;
  if (config.documentCacheDirectory == null) return null;
  return StorageManager(
    session: session,
    config: config,
    accountId: account.localId,
  );
}

/// Bumped after [Session.authenticate] mutates travelMenu in place so
/// [supportedAppletPhpUrls] refreshes without invalidating mid-rebuild.
@Riverpod(keepAlive: true)
class SessionFeatureEpoch extends _$SessionFeatureEpoch {
  @override
  int build() => 0;

  void bump() => state++;
}

/// PHP applet URLs supported by the current authenticated session + account type.
@Riverpod(keepAlive: true)
Set<String> supportedAppletPhpUrls(Ref ref) {
  ref.watch(sessionFeatureEpochProvider);
  final session = ref.watch(sessionProvider).asData?.value;
  final account = ref.watch(activeAccountProvider);
  if (session == null || account == null) return const {};

  final type = account.accountType ?? session.accountTypeOrNull;
  if (type == null) return const {};
  return {
    for (final applet in Applets.all)
      if (session.doesSupportFeature(applet, overrideAccountType: type))
        applet.appletPhpUrl,
  };
}
