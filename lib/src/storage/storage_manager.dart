import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import '../exceptions.dart';
import '../session/session.dart';

typedef StoragePathLayout =
    String Function({
      required String cacheRoot,
      required int accountId,
      required String urlHash,
      required String filename,
    });

/// Configurable document/file cache backed by the session Dio client.
class StorageManager {
  final LanisSession session;
  final LanisConfig config;
  final int accountId;

  /// Override how cache relative paths are built.
  final StoragePathLayout? pathLayout;

  /// Optional hook after a successful download.
  final Future<void> Function(String path)? onDownloaded;

  /// Optional existence check override.
  final Future<bool> Function(String path)? existsOverride;

  StorageManager({
    required this.session,
    required this.config,
    required this.accountId,
    this.pathLayout,
    this.onDownloaded,
    this.existsOverride,
  });

  String get _cacheRoot {
    final root = config.documentCacheDirectory;
    if (root == null || root.isEmpty) {
      throw StorageNotConfiguredException();
    }
    return root;
  }

  Directory getDocumentCacheDirectory() {
    if (!config.storageEnabled) {
      throw StorageNotConfiguredException('Document storage is disabled');
    }
    final dir = Directory(p.join(_cacheRoot, '$accountId', 'document_cache'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  String generateUniqueHash(String source) {
    final digest = sha256.convert(utf8.encode(source));
    return digest
        .toString()
        .replaceAll(RegExp(r'[^A-z0-9]'), '')
        .substring(0, 12);
  }

  String resolvePath(String url, String filename) {
    final urlHash = generateUniqueHash(url);
    if (pathLayout != null) {
      return pathLayout!(
        cacheRoot: getDocumentCacheDirectory().path,
        accountId: accountId,
        urlHash: urlHash,
        filename: filename,
      );
    }
    return p.join(getDocumentCacheDirectory().path, urlHash, filename);
  }

  Future<bool> doesFileExist(String url, String filename) async {
    final filePath = resolvePath(url, filename);
    if (existsOverride != null) {
      return existsOverride!(filePath);
    }
    return File(filePath).existsSync();
  }

  Future<String> downloadFile(
    String url,
    String filename, {
    bool followRedirects = false,
  }) async {
    if (!config.storageEnabled) {
      throw StorageNotConfiguredException('Document storage is disabled');
    }

    final savePath = resolvePath(url, filename);
    final folder = Directory(p.dirname(savePath));
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }

    if (await doesFileExist(url, filename)) {
      return savePath;
    }

    var response = await session.dio.get(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        validateStatus: (status) =>
            status != null && (status == 200 || status == 302),
      ),
    );

    var currentUrl = url;
    if (response.statusCode == 302 && followRedirects) {
      final location = response.headers.value('location');
      if (location != null) {
        if (location.startsWith('https')) {
          currentUrl = location;
        } else {
          final originalUrl = Uri.parse(url);
          currentUrl = 'https://${originalUrl.host}/$location';
        }
        response = await session.dio.get(
          currentUrl,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: false,
            validateStatus: (status) => status == 200,
          ),
        );
      }
    }

    if (response.statusCode != 200 || response.data is! List<int>) {
      throw NetworkException(
        'Download failed with status ${response.statusCode}',
      );
    }

    final file = File(savePath);
    final raf = file.openSync(mode: FileMode.write);
    raf.writeFromSync(response.data as List<int>);
    await raf.close();

    await _enforceLimits();
    if (onDownloaded != null) {
      await onDownloaded!(savePath);
    }
    return savePath;
  }

  Future<void> deleteFilesOlderThan(Duration duration) async {
    final tempDir = getDocumentCacheDirectory();
    for (final entity in tempDir.listSync(recursive: true)) {
      if (entity is File) {
        final stat = entity.statSync();
        if (DateTime.now().difference(stat.modified) > duration) {
          entity.deleteSync();
        }
      }
    }
  }

  Future<void> clear() async {
    final dir = getDocumentCacheDirectory();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  Future<void> _enforceLimits() async {
    if (config.storageMaxAge != null) {
      await deleteFilesOlderThan(config.storageMaxAge!);
    }
    final maxBytes = config.storageMaxBytes;
    if (maxBytes == null) return;

    final dir = getDocumentCacheDirectory();
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => (file: f, modified: f.statSync().modified))
        .toList()
      ..sort((a, b) => a.modified.compareTo(b.modified));

    var total = files.fold<int>(0, (sum, e) => sum + e.file.lengthSync());
    for (final entry in files) {
      if (total <= maxBytes) break;
      total -= entry.file.lengthSync();
      entry.file.deleteSync();
    }
  }
}
