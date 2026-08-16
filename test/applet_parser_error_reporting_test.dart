import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

import 'support/offline_http_adapter.dart';

class _ThrowingParser extends AppletParser<String> {
  final Object toThrow;

  _ThrowingParser({
    required AppletContext ctx,
    required this.toThrow,
  }) : super(
          ctx,
          const AppletMeta(
            appletPhpUrl: 'test.php',
            supportedAccountTypes: [AccountType.student],
            refreshInterval: Duration(hours: 1),
          ),
          isConnected: () async => true,
        );

  @override
  Future<String> getHome() async => throw toThrow;
}

AppletContext _testContext(LanisConfig config) {
  final db = LanisDatabase.open(
    path: config.databasePath,
    secretStore: config.secretStore,
  );
  final account = ClearTextAccount(
    localId: 1,
    schoolID: 1,
    username: 'u',
    password: 'p',
    schoolName: 'S',
    accountType: AccountType.student,
  );
  final session = LanisSession(
    account: account,
    config: config,
    connectionChecker: ConnectionChecker(httpAdapter: OfflineHttpAdapter()),
  );
  return AppletContext(
    session: session,
    database: db,
    account: account,
    accountSettings: TypedSettings.account(db, account.localId),
  );
}

void main() {
  tearDown(LanisClient.reset);

  group('isUnexpectedParserError', () {
    test('true for UnknownException and non-LanisException', () {
      expect(isUnexpectedParserError(UnknownException()), isTrue);
      expect(isUnexpectedParserError(FormatException('bad html')), isTrue);
      expect(isUnexpectedParserError(StateError('null check')), isTrue);
    });

    test('false for expected typed LanisExceptions', () {
      expect(isUnexpectedParserError(NetworkException()), isFalse);
      expect(isUnexpectedParserError(NoConnectionException()), isFalse);
      expect(isUnexpectedParserError(WrongCredentialsException()), isFalse);
      expect(isUnexpectedParserError(LanisDownException()), isFalse);
      expect(isUnexpectedParserError(UnauthorizedException()), isFalse);
      expect(isUnexpectedParserError(LoginTimeoutException('1h')), isFalse);
    });
  });

  group('AppletParser.fetchData unexpected reporting', () {
    test('reports UnknownException once after final retry', () async {
      final reported = <Object>[];
      String? reportedApplet;
      final overrides = LanisClient.configure(
        httpAdapter: OfflineHttpAdapter(),
        onUnexpectedError: (error, stackTrace, {required appletPhpUrl}) {
          reported.add(error);
          reportedApplet = appletPhpUrl;
        },
      );
      expect(overrides, isNotEmpty);

      final ctx = _testContext(LanisClient.config!);
      addTearDown(ctx.database.dispose);

      final parser = _ThrowingParser(
        ctx: ctx,
        toThrow: UnknownException('parse failed'),
      );
      addTearDown(parser.dispose);

      await parser.fetchData(forceRefresh: true, secondTry: true);

      expect(reported, hasLength(1));
      expect(reported.single, isA<UnknownException>());
      expect(reportedApplet, 'test.php');
      expect(parser.latestResponse?.status, FetcherStatus.error);
    });

    test('reports FormatException', () async {
      final reported = <Object>[];
      LanisClient.configure(
        httpAdapter: OfflineHttpAdapter(),
        onUnexpectedError: (error, stackTrace, {required appletPhpUrl}) {
          reported.add(error);
        },
      );

      final ctx = _testContext(LanisClient.config!);
      addTearDown(ctx.database.dispose);

      final parser = _ThrowingParser(
        ctx: ctx,
        toThrow: FormatException('unexpected token'),
      );
      addTearDown(parser.dispose);

      await parser.fetchData(forceRefresh: true, secondTry: true);

      expect(reported, hasLength(1));
      expect(reported.single, isA<FormatException>());
    });

    test('does not report NetworkException', () async {
      final reported = <Object>[];
      LanisClient.configure(
        httpAdapter: OfflineHttpAdapter(),
        onUnexpectedError: (error, stackTrace, {required appletPhpUrl}) {
          reported.add(error);
        },
      );

      final ctx = _testContext(LanisClient.config!);
      addTearDown(ctx.database.dispose);

      final parser = _ThrowingParser(
        ctx: ctx,
        toThrow: NetworkException(),
      );
      addTearDown(parser.dispose);

      await parser.fetchData(forceRefresh: true, secondTry: true);

      expect(reported, isEmpty);
      expect(parser.latestResponse?.status, FetcherStatus.error);
    });

    test('broken reporter does not break error response', () async {
      LanisClient.configure(
        httpAdapter: OfflineHttpAdapter(),
        onUnexpectedError: (error, stackTrace, {required appletPhpUrl}) {
          throw StateError('reporter exploded');
        },
      );

      final ctx = _testContext(LanisClient.config!);
      addTearDown(ctx.database.dispose);

      final parser = _ThrowingParser(
        ctx: ctx,
        toThrow: UnknownException(),
      );
      addTearDown(parser.dispose);

      await parser.fetchData(forceRefresh: true, secondTry: true);

      expect(parser.latestResponse?.status, FetcherStatus.error);
      expect(
        parser.latestResponse?.error?.exception,
        isA<UnknownException>(),
      );
    });

    test('no callback configured is a no-op', () async {
      LanisClient.configure(httpAdapter: OfflineHttpAdapter());

      final ctx = _testContext(LanisClient.config!);
      addTearDown(ctx.database.dispose);

      final parser = _ThrowingParser(
        ctx: ctx,
        toThrow: UnknownException(),
      );
      addTearDown(parser.dispose);

      await parser.fetchData(forceRefresh: true, secondTry: true);

      expect(parser.latestResponse?.status, FetcherStatus.error);
    });
  });
}
