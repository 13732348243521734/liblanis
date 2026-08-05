/// Remove byte-identical page HTML fixtures under test/fixtures/substitutions.
///
/// Keeps lexicographically first name per SHA-256. Also drops orphaned ajax
/// files whose page was removed. Rewrites manifest.json + dedupe_report.json.
///
/// ```sh
/// dart run tool/substitutions/dedupe_fixtures.dart --dry-run
/// dart run tool/substitutions/dedupe_fixtures.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  var fixtureDir = 'test/fixtures/substitutions';
  var dryRun = false;
  for (final arg in args) {
    if (arg.startsWith('--fixture-dir=')) {
      fixtureDir = arg.substring('--fixture-dir='.length);
    } else if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg == '--help' || arg == '-h') {
      stdout.writeln(
        'Usage: dart run tool/substitutions/dedupe_fixtures.dart [--dry-run]',
      );
      return;
    }
  }

  final dir = Directory(fixtureDir);
  if (!dir.existsSync()) {
    stderr.writeln('Missing $fixtureDir');
    exitCode = 1;
    return;
  }

  final pages = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('__page.html'))
      .toList()
    ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

  final byHash = <String, List<File>>{};
  for (final f in pages) {
    final h = sha256.convert(await f.readAsBytes()).toString();
    (byHash[h] ??= []).add(f);
  }

  final kept = <String>[];
  final removed = <String>[];
  final groups = <Map<String, Object?>>[];

  for (final hash in byHash.keys.toList()..sort()) {
    final files = byHash[hash]!
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    final keep = p.basename(files.first.path);
    kept.add(keep);
    final dups = [for (final f in files.skip(1)) p.basename(f.path)];
    removed.addAll(dups);
    groups.add({'sha256': hash, 'kept': keep, 'removed': dups});
    if (!dryRun) {
      for (final f in files.skip(1)) {
        final base = p.basename(f.path).replaceAll('__page.html', '');
        f.deleteSync();
        final ajax = File(p.join(dir.path, '${base}__ajax.txt'));
        if (ajax.existsSync()) ajax.deleteSync();
      }
    }
  }

  stdout.writeln(
    'pages=${pages.length} unique=${byHash.length} removed=${removed.length}',
  );

  final report = {
    'fixtureDir': fixtureDir,
    'dryRun': dryRun,
    'scanned': pages.length,
    'unique': byHash.length,
    'removedCount': removed.length,
    'keptCount': kept.length,
    'groups': groups,
  };
  if (!dryRun) {
    await File(p.join(dir.path, 'dedupe_report.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    final keptSet = kept.toSet();
    final manifestPath = File(p.join(dir.path, 'manifest.json'));
    if (manifestPath.existsSync()) {
      final m = jsonDecode(manifestPath.readAsStringSync()) as Map<String, dynamic>;
      final files = (m['files'] as List? ?? [])
          .whereType<Map>()
          .where((f) => keptSet.contains(f['page']))
          .toList();
      m['files'] = files;
      m['deduped'] = true;
      m['keptPages'] = kept.length;
      await manifestPath.writeAsString(
        const JsonEncoder.withIndent('  ').convert(m),
      );
    }
  } else {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'wouldRemove': removed.take(20).toList(),
      'removedCount': removed.length,
    }));
  }
}
