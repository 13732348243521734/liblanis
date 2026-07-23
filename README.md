# liblanis

Pure Dart client for [Schulportal Hessen (SPH / Lanis)](https://start.schulportal.hessen.de).

Riverpod-backed multi-account API, optional unified `sqlite3` persistence, injectable secrets, and configurable document caching. **No Flutter dependency.**

> This package is developed as a submodule of [lanis-mobile/lanis](https://github.com/lanis-mobile/lanis). It is designed to be pub.dev-compatible but is **not published yet**.

## Features

- Full SPH session stack (login, cookies, RSA/AES cryptor, HTML/JSON applet parsers)
- Multi-account registry with active-account selection
- Optional single SQLite database (file or in-memory)
- `sharedOverAccountSettings` and `accountSpecificSettings` with typed helpers
- Offline applet snapshots table (substitutions & timetable write in v1; API is generic)
- `connectionStatusProvider` for SPH reachability
- Configurable `StorageManager` (caller supplies cache directory)

## Install

Path (app / submodule):

```yaml
dependencies:
  liblanis:
    path: liblanis
  flutter_riverpod: ^3.0.0
  sqlite3_flutter_libs: ^0.5.0 # load native sqlite on mobile
```

On Flutter mobile hosts, initialize sqlite before runApp:

```dart
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  // ...
}
```

## Quick start

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liblanis/liblanis.dart';

Future<void> main() async {
  final overrides = LanisClient.configure(
    databasePath: '/path/to/lanis.db', // null => in-memory
    secretStore: MySecureStore(),      // required when databasePath != null
    documentCacheDirectory: '/path/to/cache', // required for downloads
    // httpAdapter: cronetAdapter,     // optional
    userAgent: 'Lanis-Mobile/v3.7.2+83',
  );

  runApp(
    ProviderScope(
      overrides: overrides,
      child: const MyApp(),
    ),
  );
}

class MySecureStore implements SecretStore {
  // e.g. FlutterSecureStorage
  @override
  Future<void> write(String key, String value) async { /* ... */ }
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async { /* ... */ }
}
```

### Accounts & session

```dart
final id = await ref.read(accountsProvider.notifier).add(
  schoolId: 5151,
  schoolName: 'Example',
  username: 'user',
  password: 'pass',
);

await ref.read(activeAccountProvider.notifier).select(id);
await ref.read(sessionProvider.notifier).authenticate();

ref.listen(connectionStatusProvider, (prev, next) {
  // ConnectionStatus.connected / disconnected
});
```

### Settings

```dart
final shared = ref.read(sharedOverAccountSettingsProvider);
shared.setString('theme', 'dark');

final account = ref.read(accountSpecificSettingsProvider);
account.setJsonMap('vertretungsplan.php/filter', {/* ... */});
```

### Applets

```dart
final response = await ref.read(substitutionsProvider.future);
if (response.contentStatus == ContentStatus.offline) {
  // cached SubstitutionPlan
}
final plan = response.content;

// Or use the long-lived parser + stream:
final parser = ref.read(substitutionsParserProvider);
await parser.fetchData();
parser.stream.listen(/* FetcherResponse<SubstitutionPlan> */);
```

### Document downloads

```dart
final storage = ref.read(storageManagerProvider);
if (storage != null) {
  final path = await storage.downloadFile(url, filename);
}
```

Calling download APIs without `documentCacheDirectory` throws `StorageNotConfiguredException`.

## Configuration rules

| Option | Behavior |
|--------|----------|
| `databasePath: null` | In-memory sqlite; `SecretStore` optional |
| `databasePath: set` | File DB; **`secretStore` required** |
| `documentCacheDirectory: null` | Downloads disabled |
| `httpAdapter` | Optional Dio adapter injection |

## Development

```bash
cd liblanis
dart pub get
dart run build_runner build
dart test
dart analyze
```

## License

GPL-3.0 — see [LICENSE](LICENSE).
