import 'package:dio/dio.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:riverpod/riverpod.dart';

import 'config.dart';
import 'exceptions.dart';
import 'providers/core_providers.dart';
import 'secret_store.dart';

/// Thin bootstrap for the liblanis Riverpod graph.
///
/// Hosts create a [ProviderScope] / [ProviderContainer] and apply
/// [LanisClient.overrides] from [configure].
class LanisClient {
  LanisClient._();

  static LanisConfig? _config;
  static List<Override>? _overrides;

  /// Last configuration produced by [configure], if any.
  static LanisConfig? get config => _config;

  /// Riverpod overrides to pass into [ProviderScope] / [ProviderContainer].
  static List<Override> get overrides {
    final o = _overrides;
    if (o == null) {
      throw ConfigurationException(
        'LanisClient.configure must be called before reading overrides',
      );
    }
    return o;
  }

  /// Configure persistence, secrets, storage, and HTTP.
  ///
  /// - [databasePath] null → in-memory sqlite
  /// - [secretStore] required when [databasePath] is set
  /// - [documentCacheDirectory] required to use downloads
  /// - [httpAdapter] optional (e.g. Cronet from Flutter)
  /// - [onUnexpectedError] optional host reporter for unexpected applet fetch failures
  static List<Override> configure({
    String? databasePath,
    SecretStore? secretStore,
    String? documentCacheDirectory,
    HttpClientAdapter? httpAdapter,
    String userAgent = 'liblanis/0.1.0',
    bool storageEnabled = true,
    Duration? storageMaxAge,
    int? storageMaxBytes,
    UnexpectedErrorHandler? onUnexpectedError,
  }) {
    if (databasePath != null && secretStore == null) {
      throw ConfigurationException(
        'secretStore is required when databasePath is set',
      );
    }

    final cfg = LanisConfig(
      databasePath: databasePath,
      secretStore: secretStore ?? (databasePath == null ? MemorySecretStore() : null),
      documentCacheDirectory: documentCacheDirectory,
      httpAdapter: httpAdapter,
      userAgent: userAgent,
      storageEnabled: storageEnabled,
      storageMaxAge: storageMaxAge,
      storageMaxBytes: storageMaxBytes,
      onUnexpectedError: onUnexpectedError,
    );

    _config = cfg;
    _overrides = [
      lanisConfigProvider.overrideWithValue(cfg),
    ];
    return _overrides!;
  }

  /// Clears static configuration (useful in tests).
  static void reset() {
    _config = null;
    _overrides = null;
  }
}
