import 'package:dio/dio.dart';

import 'secret_store.dart';

/// Immutable configuration produced by [LanisClient.configure].
class LanisConfig {
  /// Absolute path to the sqlite DB file, or null for in-memory.
  final String? databasePath;

  /// Required when [databasePath] is non-null.
  final SecretStore? secretStore;

  /// Root directory for document downloads. Required to use [StorageManager] downloads.
  final String? documentCacheDirectory;

  /// Optional Dio HTTP adapter (e.g. Cronet from a Flutter host).
  final HttpClientAdapter? httpAdapter;

  /// User-Agent product name fragment, e.g. `Lanis-Mobile/v3.7.2+83`.
  final String userAgent;

  /// When true, StorageManager caching/downloads are enabled (still needs a directory).
  final bool storageEnabled;

  /// Optional max age for cached files; null means no TTL eviction.
  final Duration? storageMaxAge;

  /// Optional max total cache size in bytes; null means unlimited.
  final int? storageMaxBytes;

  const LanisConfig({
    this.databasePath,
    this.secretStore,
    this.documentCacheDirectory,
    this.httpAdapter,
    this.userAgent = 'liblanis/0.1.0',
    this.storageEnabled = true,
    this.storageMaxAge,
    this.storageMaxBytes,
  });

  LanisConfig copyWith({
    String? databasePath,
    SecretStore? secretStore,
    String? documentCacheDirectory,
    HttpClientAdapter? httpAdapter,
    String? userAgent,
    bool? storageEnabled,
    Duration? storageMaxAge,
    int? storageMaxBytes,
  }) {
    return LanisConfig(
      databasePath: databasePath ?? this.databasePath,
      secretStore: secretStore ?? this.secretStore,
      documentCacheDirectory:
          documentCacheDirectory ?? this.documentCacheDirectory,
      httpAdapter: httpAdapter ?? this.httpAdapter,
      userAgent: userAgent ?? this.userAgent,
      storageEnabled: storageEnabled ?? this.storageEnabled,
      storageMaxAge: storageMaxAge ?? this.storageMaxAge,
      storageMaxBytes: storageMaxBytes ?? this.storageMaxBytes,
    );
  }
}
