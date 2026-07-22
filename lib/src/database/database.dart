import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../exceptions.dart';
import '../models/account.dart';
import '../models/account_types.dart';
import '../secret_store.dart';

/// Unified SPH client database (file or in-memory).
class LanisDatabase {
  final Database _db;
  final SecretStore? secretStore;
  final bool isInMemory;

  LanisDatabase._(this._db, {this.secretStore, required this.isInMemory});

  /// Opens a file DB at [path], or an in-memory DB when [path] is null.
  ///
  /// [secretStore] is required for file databases.
  factory LanisDatabase.open({String? path, SecretStore? secretStore}) {
    final isInMemory = path == null;
    if (!isInMemory && secretStore == null) {
      throw ConfigurationException(
        'secretStore is required when databasePath is set',
      );
    }
    final db = isInMemory ? sqlite3.openInMemory() : sqlite3.open(path);
    final instance = LanisDatabase._(
      db,
      secretStore: secretStore ?? MemorySecretStore(),
      isInMemory: isInMemory,
    );
    instance._migrate();
    return instance;
  }

  void _migrate() {
    _db.execute('PRAGMA foreign_keys = ON;');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        school_id INTEGER NOT NULL,
        school_name TEXT NOT NULL,
        username TEXT NOT NULL,
        account_type TEXT,
        password_secret_key TEXT NOT NULL,
        last_login TEXT,
        creation_date TEXT NOT NULL,
        UNIQUE(school_id, username)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS shared_settings (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS account_settings (
        account_id INTEGER NOT NULL,
        key TEXT NOT NULL,
        value TEXT,
        PRIMARY KEY (account_id, key),
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS applet_offline_data (
        account_id INTEGER NOT NULL,
        applet_id TEXT NOT NULL,
        json TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        PRIMARY KEY (account_id, applet_id),
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
      );
    ''');
  }

  void dispose() => _db.dispose();

  // —— Accounts ——

  String _passwordKey(int accountId) => 'account_password_$accountId';

  Future<int> addAccount({
    required int schoolId,
    required String schoolName,
    required String username,
    required String password,
    AccountType? accountType,
  }) async {
    final existing = _db.select(
      'SELECT id FROM accounts WHERE school_id = ? AND username = ?',
      [schoolId, username],
    );
    if (existing.isNotEmpty) {
      throw AccountAlreadyExistsException();
    }

    final now = DateTime.now().toIso8601String();
    _db.execute(
      '''
      INSERT INTO accounts (
        school_id, school_name, username, account_type,
        password_secret_key, last_login, creation_date
      ) VALUES (?, ?, ?, ?, '', NULL, ?)
      ''',
      [schoolId, schoolName, username, accountType?.name, now],
    );
    final id = _db.lastInsertRowId;
    final secretKey = _passwordKey(id);
    await secretStore!.write(secretKey, password);
    _db.execute(
      'UPDATE accounts SET password_secret_key = ? WHERE id = ?',
      [secretKey, id],
    );
    return id;
  }

  Future<ClearTextAccount?> getAccount(int id) async {
    final rows = _db.select('SELECT * FROM accounts WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _rowToClearText(rows.first);
  }

  Future<List<AccountSummary>> listAccounts() async {
    final rows = _db.select(
      'SELECT * FROM accounts ORDER BY last_login IS NULL DESC, last_login DESC, id ASC',
    );
    return rows.map(_rowToSummary).toList();
  }

  Future<ClearTextAccount?> getPreferredStartupAccount() async {
    final rows = _db.select(
      'SELECT * FROM accounts ORDER BY last_login IS NULL DESC, last_login DESC, id ASC LIMIT 1',
    );
    if (rows.isEmpty) return null;
    return _rowToClearText(rows.first);
  }

  Future<void> updateLastLogin(int id, {DateTime? at}) async {
    _db.execute('UPDATE accounts SET last_login = ? WHERE id = ?', [
      (at ?? DateTime.now()).toIso8601String(),
      id,
    ]);
  }

  Future<void> clearLastLogin(int id) async {
    _db.execute('UPDATE accounts SET last_login = NULL WHERE id = ?', [id]);
  }

  Future<void> setAccountType(int id, AccountType type) async {
    _db.execute('UPDATE accounts SET account_type = ? WHERE id = ?', [
      type.name,
      id,
    ]);
  }

  Future<void> updatePassword(int id, String password) async {
    final key = _passwordKey(id);
    await secretStore!.write(key, password);
    _db.execute(
      'UPDATE accounts SET password_secret_key = ? WHERE id = ?',
      [key, id],
    );
  }

  Future<void> deleteAccount(int id) async {
    final key = _passwordKey(id);
    await secretStore?.delete(key);
    _db.execute('DELETE FROM accounts WHERE id = ?', [id]);
  }

  Future<ClearTextAccount> _rowToClearText(Row row) async {
    final id = row['id'] as int;
    final secretKey = row['password_secret_key'] as String;
    final password = await secretStore!.read(secretKey) ?? '';
    final accountTypeRaw = row['account_type'] as String?;
    return ClearTextAccount(
      localId: id,
      schoolID: row['school_id'] as int,
      username: row['username'] as String,
      password: password,
      schoolName: row['school_name'] as String,
      accountType: accountTypeRaw != null
          ? AccountTypeX.fromString(accountTypeRaw)
          : null,
      firstLogin: row['last_login'] == null,
      lastLogin: row['last_login'] != null
          ? DateTime.parse(row['last_login'] as String)
          : null,
      creationDate: DateTime.parse(row['creation_date'] as String),
    );
  }

  AccountSummary _rowToSummary(Row row) {
    final accountTypeRaw = row['account_type'] as String?;
    return AccountSummary(
      localId: row['id'] as int,
      schoolID: row['school_id'] as int,
      username: row['username'] as String,
      schoolName: row['school_name'] as String,
      accountType: accountTypeRaw != null
          ? AccountTypeX.fromString(accountTypeRaw)
          : null,
      lastLogin: row['last_login'] != null
          ? DateTime.parse(row['last_login'] as String)
          : null,
      creationDate: DateTime.parse(row['creation_date'] as String),
    );
  }

  // —— Settings ——

  String? getSharedSetting(String key) {
    final rows = _db.select(
      'SELECT value FROM shared_settings WHERE key = ?',
      [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  void setSharedSetting(String key, String? value) {
    _db.execute(
      '''
      INSERT INTO shared_settings (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      [key, value],
    );
  }

  void deleteSharedSetting(String key) {
    _db.execute('DELETE FROM shared_settings WHERE key = ?', [key]);
  }

  String? getAccountSetting(int accountId, String key) {
    final rows = _db.select(
      'SELECT value FROM account_settings WHERE account_id = ? AND key = ?',
      [accountId, key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  void setAccountSetting(int accountId, String key, String? value) {
    _db.execute(
      '''
      INSERT INTO account_settings (account_id, key, value) VALUES (?, ?, ?)
      ON CONFLICT(account_id, key) DO UPDATE SET value = excluded.value
      ''',
      [accountId, key, value],
    );
  }

  void deleteAccountSetting(int accountId, String key) {
    _db.execute(
      'DELETE FROM account_settings WHERE account_id = ? AND key = ?',
      [accountId, key],
    );
  }

  // —— Offline applet data ——

  void setAppletOfflineData({
    required int accountId,
    required String appletId,
    required String json,
    DateTime? timestamp,
  }) {
    _db.execute(
      '''
      INSERT INTO applet_offline_data (account_id, applet_id, json, timestamp)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(account_id, applet_id) DO UPDATE SET
        json = excluded.json,
        timestamp = excluded.timestamp
      ''',
      [
        accountId,
        appletId,
        json,
        (timestamp ?? DateTime.now()).toIso8601String(),
      ],
    );
  }

  ({String json, DateTime timestamp})? getAppletOfflineData({
    required int accountId,
    required String appletId,
  }) {
    final rows = _db.select(
      '''
      SELECT json, timestamp FROM applet_offline_data
      WHERE account_id = ? AND applet_id = ?
      ''',
      [accountId, appletId],
    );
    if (rows.isEmpty) return null;
    return (
      json: rows.first['json'] as String,
      timestamp: DateTime.parse(rows.first['timestamp'] as String),
    );
  }

  void deleteAppletOfflineData({
    required int accountId,
    required String appletId,
  }) {
    _db.execute(
      'DELETE FROM applet_offline_data WHERE account_id = ? AND applet_id = ?',
      [accountId, appletId],
    );
  }

  List<({int accountId, String appletId, DateTime timestamp})>
  listAppletOfflineData({int? accountId}) {
    final rows = accountId == null
        ? _db.select(
            'SELECT account_id, applet_id, timestamp FROM applet_offline_data',
          )
        : _db.select(
            '''
            SELECT account_id, applet_id, timestamp FROM applet_offline_data
            WHERE account_id = ?
            ''',
            [accountId],
          );
    return rows
        .map(
          (r) => (
            accountId: r['account_id'] as int,
            appletId: r['applet_id'] as String,
            timestamp: DateTime.parse(r['timestamp'] as String),
          ),
        )
        .toList();
  }

  /// Encodes a JSON-compatible value for settings storage.
  static String encodeValue(Object? value) => jsonEncode({'v': value});

  /// Decodes a value previously stored with [encodeValue].
  static Object? decodeValue(String? raw) {
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded.containsKey('v')) {
      return decoded['v'];
    }
    return decoded;
  }
}
