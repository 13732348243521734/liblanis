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
  // Emit current status immediately, then follow the stream.
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
      ref.read(activeAccountProvider.notifier).clear();
    }
    ref.invalidateSelf();
  }

  Future<void> setAccountType(int id, AccountType type) async {
    await ref.read(lanisDatabaseProvider).setAccountType(id, type);
    ref.invalidateSelf();
    final active = ref.read(activeAccountProvider);
    if (active?.localId == id) {
      await ref.read(activeAccountProvider.notifier).select(id);
    }
  }

  Future<void> updatePassword(int id, String password) async {
    await ref.read(lanisDatabaseProvider).updatePassword(id, password);
  }
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
    // Dispose previous session if any.
    ref.invalidate(sessionProvider);
    state = account;
  }

  Future<void> selectPreferred() async {
    final db = ref.read(lanisDatabaseProvider);
    final account = await db.getPreferredStartupAccount();
    if (account == null) {
      state = null;
      return;
    }
    ref.invalidate(sessionProvider);
    state = account;
  }

  void clear() {
    ref.invalidate(sessionProvider);
    state = null;
  }
}

@Riverpod(keepAlive: true)
class Session extends _$Session {
  @override
  FutureOr<SessionHandler?> build() async {
    final account = ref.watch(activeAccountProvider);
    if (account == null) return null;

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

  Future<SessionHandler> authenticate({String? withLoginUrl}) async {
    final session = await future;
    if (session == null) {
      throw ConfigurationException('No active account selected');
    }
    await session.authenticate(withLoginUrl: withLoginUrl);
    final db = ref.read(lanisDatabaseProvider);
    await db.updateLastLogin(session.account.localId);
    if (session.account.accountType == null) {
      await db.setAccountType(session.account.localId, session.accountType);
      await ref
          .read(activeAccountProvider.notifier)
          .select(session.account.localId);
    }
    ref.invalidate(accountsProvider);
    return session;
  }

  Future<void> deAuthenticate() async {
    final session = await future;
    await session?.deAuthenticate();
  }
}

@Riverpod(keepAlive: true)
TypedSettings sharedOverAccountSettings(Ref ref) {
  final db = ref.watch(lanisDatabaseProvider);
  return TypedSettings.shared(db);
}

@Riverpod(keepAlive: true)
TypedSettings accountSpecificSettings(Ref ref) {
  final account = ref.watch(activeAccountProvider);
  if (account == null) {
    throw ConfigurationException(
      'accountSpecificSettings requires an active account',
    );
  }
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
