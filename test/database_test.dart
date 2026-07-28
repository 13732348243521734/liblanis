import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

void main() {
  group('LanisDatabase', () {
    late LanisDatabase db;

    setUp(() {
      db = LanisDatabase.open();
    });

    tearDown(() {
      db.dispose();
    });

    test('file DB requires SecretStore', () {
      expect(
        () => LanisDatabase.open(path: '/tmp/liblanis_test.db'),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('add, list, get, delete account', () async {
      final id = await db.addAccount(
        schoolId: 1234,
        schoolName: 'Test School',
        username: 'user',
        password: 'secret',
        accountType: AccountType.student,
      );

      final list = await db.listAccounts();
      expect(list, hasLength(1));
      expect(list.first.localId, id);
      expect(list.first.schoolName, 'Test School');

      final account = await db.getAccount(id);
      expect(account, isNotNull);
      expect(account!.password, 'secret');
      expect(account.accountType, AccountType.student);
      expect(account.firstLogin, isTrue);

      await db.updateLastLogin(id);
      final again = await db.getAccount(id);
      expect(again!.firstLogin, isFalse);

      await db.deleteAccount(id);
      expect(await db.listAccounts(), isEmpty);
    });

    test('rejects duplicate school+username', () async {
      await db.addAccount(
        schoolId: 1,
        schoolName: 'A',
        username: 'u',
        password: 'p',
      );
      expect(
        () => db.addAccount(
          schoolId: 1,
          schoolName: 'A',
          username: 'u',
          password: 'p',
        ),
        throwsA(isA<AccountAlreadyExistsException>()),
      );
    });

    test('shared and account settings typed helpers', () async {
      final shared = TypedSettings.shared(db);
      shared.setString('theme', 'dark');
      shared.setBool('notifications-allow', true);
      shared.setInt('interval', 15);
      expect(shared.getString('theme'), 'dark');
      expect(shared.getBool('notifications-allow'), isTrue);
      expect(shared.getInt('interval'), 15);
      expect(shared.getBool('theme'), isNull);
      shared.setString('legacy-false', 'false');
      expect(shared.getBool('legacy-false'), isFalse);

      final id = await db.addAccount(
        schoolId: 2,
        schoolName: 'B',
        username: 'x',
        password: 'y',
      );
      final account = TypedSettings.account(db, id);
      account.setJsonMap('vertretungsplan.php/filter', {
        'Klasse': {
          'filter': ['10a'],
          'strict': true,
        },
      });
      final filter = account.getJsonMap('vertretungsplan.php/filter');
      expect(filter!['Klasse']['filter'], ['10a']);
    });

    test('applet offline data upsert and read', () async {
      final id = await db.addAccount(
        schoolId: 3,
        schoolName: 'C',
        username: 'z',
        password: 'pw',
      );
      db.setAppletOfflineData(
        accountId: id,
        appletId: 'vertretungsplan.php',
        json: '{"days":[],"lastUpdated":"2026-01-01T00:00:00.000"}',
      );
      final data = db.getAppletOfflineData(
        accountId: id,
        appletId: 'vertretungsplan.php',
      );
      expect(data, isNotNull);
      expect(data!.json, contains('days'));

      final listed = db.listAppletOfflineData(accountId: id);
      expect(listed, hasLength(1));
      expect(listed.first.appletId, 'vertretungsplan.php');
    });

    test('delete offline data and clear setting keys', () async {
      final id = await db.addAccount(
        schoolId: 4,
        schoolName: 'D',
        username: 'w',
        password: 'pw',
      );
      db.setAppletOfflineData(
        accountId: id,
        appletId: 'kalender.php',
        json: '{"events":[]}',
      );
      db.deleteAppletOfflineData(accountId: id, appletId: 'kalender.php');
      expect(
        db.getAppletOfflineData(accountId: id, appletId: 'kalender.php'),
        isNull,
      );

      final shared = TypedSettings.shared(db);
      shared.setString('tmp', 'x');
      shared.setString('tmp', null);
      expect(shared.getString('tmp'), isNull);
    });

    test('listAppletOfflineData across accounts', () async {
      final a = await db.addAccount(
        schoolId: 5,
        schoolName: 'E',
        username: 'a',
        password: 'pw',
      );
      final b = await db.addAccount(
        schoolId: 6,
        schoolName: 'F',
        username: 'b',
        password: 'pw',
      );
      db.setAppletOfflineData(
        accountId: a,
        appletId: 'vertretungsplan.php',
        json: '{}',
      );
      db.setAppletOfflineData(
        accountId: b,
        appletId: 'nachrichten.php',
        json: '{}',
      );
      expect(db.listAppletOfflineData(), hasLength(2));
      expect(db.listAppletOfflineData(accountId: a), hasLength(1));
    });
  });
}
