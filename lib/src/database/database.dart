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
    // NOTE for reviewers: this migration deliberately creates
    // substitution_history (Feature 1, implemented, see history.dart)
    // together with timetable_history and datastorage_backup below --
    // those two back Feature 2.5 (Stundenplanhistorie) and Feature 3
    // (Dateispeicher-Backup), which are NOT implemented yet at this point
    // in history. This is an intentional batched pre-migration (see the
    // project's feature plan, "Schritt 0"): all schema additions for the
    // three planned history/backup features were front-loaded into one
    // migration step before any of the features themselves landed, so
    // that adding Feature 2.5/3 later doesn't need its own schema change.
    // The trade-off -- unused tables with no access code sitting in main
    // until those features ship -- was accepted deliberately, not an
    // oversight.

    // Feature 1 (Vertretungshistorie): eine Zeile pro zuletzt gesehenem
    // Vertretungs-Eintrag (Schlüssel lehrer|fach|stunde), Bucket = Tag
    // (tag_en). Bestehende Zeile wird bei jedem Diff-Lauf per HistoryDiffer
    // aktualisiert/ersetzt, siehe lib/src/history/history_differ.dart.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS substitution_history (
        account_id INTEGER NOT NULL,
        entry_key TEXT NOT NULL,
        tag_en TEXT NOT NULL,
        stunde TEXT NOT NULL,
        snapshot_json TEXT NOT NULL,
        status TEXT NOT NULL,
        first_seen TEXT NOT NULL,
        last_seen TEXT NOT NULL,
        change_detected_at TEXT,
        PRIMARY KEY (account_id, tag_en, entry_key),
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
      );
    ''');
    // Feature 2.5 (Stundenplanhistorie): ein Snapshot pro Datum, ab dem er
    // gültig war. Wird sowohl für die Anzeige vergangener Wochen als auch
    // als Cache für live per Redirect nachgeladene Wochen genutzt (5.3).
    _db.execute('''
      CREATE TABLE IF NOT EXISTS timetable_history (
        account_id INTEGER NOT NULL,
        valid_from_date TEXT NOT NULL,
        timetable_json TEXT NOT NULL,
        captured_at TEXT NOT NULL,
        PRIMARY KEY (account_id, valid_from_date),
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
      );
    ''');
    // Feature 3 (Dateispeicher-Backup): ein Eintrag pro entdeckter
    // Serverdatei. last_seen_on_server wird bei fehlender Datei nur auf
    // false gesetzt (nicht gelöscht), taucht sie wieder auf -> zurück auf
    // true. Siehe lib/src/applets/data_storage/backup_service.dart.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS datastorage_backup (
        account_id INTEGER NOT NULL,
        remote_file_id TEXT NOT NULL,
        name TEXT NOT NULL,
        folder_path TEXT NOT NULL,
        local_path TEXT NOT NULL,
        size INTEGER,
        last_seen_on_server INTEGER NOT NULL DEFAULT 1,
        server_changed_at TEXT,
        first_downloaded_at TEXT NOT NULL,
        last_checked_at TEXT NOT NULL,
        PRIMARY KEY (account_id, remote_file_id),
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
      );
    ''');

    // Additive column migrations go here, after all CREATE TABLE
    // statements, using _ensureColumn (idempotent — safe to run against
    // both fresh and already-migrated databases, unlike a bare
    // ALTER TABLE ADD COLUMN, which errors on a second run).
    _ensureColumn(
      table: 'substitution_history',
      column: 'field_deltas_json',
      definition: 'TEXT',
    );
  }

  /// Adds [column] to [table] if it doesn't already exist. Existing
  /// `CREATE TABLE IF NOT EXISTS` statements only run once per table (they
  /// no-op if the table is already there), so a column added to a
  /// `CREATE TABLE` after it has already shipped needs this instead —
  /// `ALTER TABLE ... ADD COLUMN` isn't idempotent on its own and throws
  /// on a database that already has the column.
  void _ensureColumn({
    required String table,
    required String column,
    required String definition,
  }) {
    final columns = _db.select('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      _db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  void dispose() => _db.close();

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
      'SELECT * FROM accounts ORDER BY last_login IS NULL ASC, last_login DESC, id ASC',
    );
    return rows.map(_rowToSummary).toList();
  }

  Future<ClearTextAccount?> getPreferredStartupAccount() async {
    final rows = _db.select(
      'SELECT * FROM accounts ORDER BY last_login IS NULL ASC, last_login DESC, id ASC LIMIT 1',
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

  // —— Substitution history (Feature 1) ——
  //
  // One row per (account, tag_en/day-bucket, entry_key). `snapshot_json`
  // holds the last-seen Substitution as JSON so it can be diffed against
  // the next fetch without a second network request. `status` is the most
  // recently detected change type for that entry (see
  // SubstitutionChangeType); it is a display annotation, matching stays
  // keyed on entry_key alone.

  List<SubstitutionHistoryRow> getSubstitutionHistoryRows({
    required int accountId,
    required String tagEn,
  }) {
    final rows = _db.select(
      '''
      SELECT entry_key, tag_en, stunde, snapshot_json, status,
             first_seen, last_seen, change_detected_at, field_deltas_json
      FROM substitution_history
      WHERE account_id = ? AND tag_en = ?
      ''',
      [accountId, tagEn],
    );
    return rows.map(_rowToSubstitutionHistoryRow).toList();
  }

  /// All history rows for [accountId] across every day, most recently
  /// changed first (`change_detected_at`, falling back to `last_seen`).
  /// Backs the app's "Änderungsverlauf" screen (feature plan 6, point 4).
  List<SubstitutionHistoryRow> getAllSubstitutionHistoryRows({
    required int accountId,
    int limit = 200,
  }) {
    final rows = _db.select(
      '''
      SELECT entry_key, tag_en, stunde, snapshot_json, status,
             first_seen, last_seen, change_detected_at, field_deltas_json
      FROM substitution_history
      WHERE account_id = ?
      ORDER BY COALESCE(change_detected_at, last_seen) DESC, tag_en DESC
      LIMIT ?
      ''',
      [accountId, limit],
    );
    return rows.map(_rowToSubstitutionHistoryRow).toList();
  }

  void upsertSubstitutionHistoryEntry({
    required int accountId,
    required String entryKey,
    required String tagEn,
    required String stunde,
    required String snapshotJson,
    required String status,
    required DateTime firstSeen,
    required DateTime lastSeen,
    DateTime? changeDetectedAt,
    String? fieldDeltasJson,
  }) {
    _db.execute(
      '''
      INSERT INTO substitution_history (
        account_id, entry_key, tag_en, stunde, snapshot_json, status,
        first_seen, last_seen, change_detected_at, field_deltas_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(account_id, tag_en, entry_key) DO UPDATE SET
        stunde = excluded.stunde,
        snapshot_json = excluded.snapshot_json,
        status = excluded.status,
        last_seen = excluded.last_seen,
        change_detected_at = excluded.change_detected_at,
        field_deltas_json = excluded.field_deltas_json
      ''',
      [
        accountId,
        entryKey,
        tagEn,
        stunde,
        snapshotJson,
        status,
        firstSeen.toIso8601String(),
        lastSeen.toIso8601String(),
        changeDetectedAt?.toIso8601String(),
        fieldDeltasJson,
      ],
    );
  }

  void deleteSubstitutionHistoryEntry({
    required int accountId,
    required String entryKey,
    required String tagEn,
  }) {
    _db.execute(
      '''
      DELETE FROM substitution_history
      WHERE account_id = ? AND tag_en = ? AND entry_key = ?
      ''',
      [accountId, tagEn, entryKey],
    );
  }

  /// Deletes entries not seen for longer than [retention]. Default retention
  /// is 30 days (`substitution-history-retention-days` account setting).
  void pruneSubstitutionHistory({
    required int accountId,
    required Duration retention,
    DateTime? now,
  }) {
    final cutoff = (now ?? DateTime.now()).subtract(retention);
    _db.execute(
      '''
      DELETE FROM substitution_history
      WHERE account_id = ? AND last_seen < ?
      ''',
      [accountId, cutoff.toIso8601String()],
    );
  }

  SubstitutionHistoryRow _rowToSubstitutionHistoryRow(Row row) {
    final changeDetectedAtRaw = row['change_detected_at'] as String?;
    return (
      entryKey: row['entry_key'] as String,
      tagEn: row['tag_en'] as String,
      stunde: row['stunde'] as String,
      snapshotJson: row['snapshot_json'] as String,
      status: row['status'] as String,
      firstSeen: DateTime.parse(row['first_seen'] as String),
      lastSeen: DateTime.parse(row['last_seen'] as String),
      changeDetectedAt: changeDetectedAtRaw != null
          ? DateTime.parse(changeDetectedAtRaw)
          : null,
      fieldDeltasJson: row['field_deltas_json'] as String?,
    );
  }
}

/// Raw persisted row for a single substitution-history entry.
typedef SubstitutionHistoryRow = ({
  String entryKey,
  String tagEn,
  String stunde,
  String snapshotJson,
  String status,
  DateTime firstSeen,
  DateTime lastSeen,
  DateTime? changeDetectedAt,
  /// JSON-encoded `List<SubstitutionFieldDelta>` for the most recent
  /// [SubstitutionChangeType.modified] transition, or `null` if this entry
  /// has never been modified (only added/removed).
  String? fieldDeltasJson,
});
