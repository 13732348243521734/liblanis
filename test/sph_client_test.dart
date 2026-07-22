import 'package:liblanis/liblanis.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

void main() {
  tearDown(SPHClient.reset);

  test('configure requires secretStore for file path', () {
    expect(
      () => SPHClient.configure(databasePath: '/tmp/x.db'),
      throwsA(isA<ConfigurationException>()),
    );
  });

  test('configure in-memory and wire providers', () async {
    final overrides = SPHClient.configure();
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    final db = container.read(lanisDatabaseProvider);
    expect(db.isInMemory, isTrue);

    final id = await container
        .read(accountsProvider.notifier)
        .add(
          schoolId: 99,
          schoolName: 'School',
          username: 'alice',
          password: 'pw',
        );

    final accounts = await container.read(accountsProvider.future);
    expect(accounts, hasLength(1));

    await container.read(activeAccountProvider.notifier).select(id);
    final active = container.read(activeAccountProvider);
    expect(active?.username, 'alice');

    final shared = container.read(sharedOverAccountSettingsProvider);
    shared.setString('color', 'blue');
    expect(shared.getString('color'), 'blue');

    final accountSettings = container.read(accountSpecificSettingsProvider);
    accountSettings.setBool('notifications-allow', false);
    expect(accountSettings.getBool('notifications-allow'), isFalse);

    expect(container.read(connectionCheckerProvider), isA<ConnectionChecker>());
    expect(container.read(storageManagerProvider), isNull);
  });

  test('storage manager available when cache dir configured', () async {
    final overrides = SPHClient.configure(
      documentCacheDirectory: '/tmp/liblanis_cache_test',
    );
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    final id = await container
        .read(accountsProvider.notifier)
        .add(
          schoolId: 1,
          schoolName: 'S',
          username: 'u',
          password: 'p',
        );
    await container.read(activeAccountProvider.notifier).select(id);
    // Session prepares Dio; storage manager needs session value.
    await container.read(sessionProvider.future);
    final storage = container.read(storageManagerProvider);
    expect(storage, isNotNull);
  });
}
