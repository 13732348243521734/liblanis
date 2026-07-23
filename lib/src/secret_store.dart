/// Host-provided secure storage for account secrets (passwords).
///
/// Required when [LanisClient.configure] is given a non-null [databasePath].
/// Unused for in-memory databases (secrets may stay in process memory).
abstract class SecretStore {
  Future<void> write(String key, String value);

  Future<String?> read(String key);

  Future<void> delete(String key);
}

/// In-process [SecretStore] for tests and in-memory database mode.
class MemorySecretStore implements SecretStore {
  final Map<String, String> _data = {};

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  void clear() => _data.clear();
}
