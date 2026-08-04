/// Remove byte-identical HTML fixtures under test/fixtures/timetable by SHA-256.
///
/// For each unique hash, keeps the lexicographically first filename and deletes
/// the rest. Rewrites `manifest.json` to kept entries only and writes
/// `dedupe_report.json` documenting kept/removed groups.
///
/// ```sh
/// dart run tool/timetable/dedupe_fixtures.dart --dry-run
/// dart run tool/timetable/dedupe_fixtures.dart
/// dart run tool/timetable/dedupe_fixtures.dart --fixture-dir=test/fixtures/timetable
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  var fixtureDir = 'test/fixtures/timetable';
  var dryRun = false;

  for (final arg in args) {
    if (arg.startsWith('--fixture-dir=')) {
      fixtureDir = arg.substring('--fixture-dir='.length);
    } else if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg == '--help' || arg == '-h') {
      stdout.writeln('''
Usage: dart run tool/timetable/dedupe_fixtures.dart [options]

  --dry-run              Report only; do not delete or rewrite files
  --fixture-dir=PATH     Directory with *.html + manifest.json
                         (default: test/fixtures/timetable)
''');
      return;
    } else {
      stderr.writeln('Unknown argument: $arg');
      exitCode = 1;
      return;
    }
  }

  final root = Directory.current.path;
  final dir = Directory(p.join(root, fixtureDir));
  if (!dir.existsSync()) {
    stderr.writeln('Fixture directory not found: ${dir.path}');
    exitCode = 1;
    return;
  }

  final htmlFiles = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.html'))
      .toList()
    ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

  if (htmlFiles.isEmpty) {
    stderr.writeln('No *.html files in ${dir.path}');
    exitCode = 1;
    return;
  }

  final byHash = <String, List<File>>{};
  for (final file in htmlFiles) {
    final digest = sha256.convert(await file.readAsBytes()).toString();
    (byHash[digest] ??= []).add(file);
  }

  final kept = <String>[];
  final removed = <String>[];
  final groups = <Map<String, Object?>>[];

  final sortedHashes = byHash.keys.toList()..sort();
  for (final hash in sortedHashes) {
    final files = byHash[hash]!
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    final keepFile = files.first;
    final keepName = p.basename(keepFile.path);
    final dupNames = [
      for (final f in files.skip(1)) p.basename(f.path),
    ];
    kept.add(keepName);
    removed.addAll(dupNames);
    groups.add({
      'sha256': hash,
      'bytes': await keepFile.length(),
      'kept': keepName,
      'removed': dupNames,
    });
  }

  kept.sort();
  removed.sort();

  stdout.writeln(
    'Scanned ${htmlFiles.length} HTML files → ${byHash.length} unique hashes '
    '(${removed.length} duplicates).',
  );
  if (removed.isEmpty) {
    stdout.writeln('Nothing to remove.');
  } else {
    final preview = removed.take(12).join('\n  ');
    final verb = dryRun ? 'Would remove' : 'Removing';
    stdout.writeln('$verb ${removed.length} files:');
    stdout.writeln('  $preview');
    if (removed.length > 12) {
      stdout.writeln('  … +${removed.length - 12} more');
    }
  }

  final report = {
    'fixtureDir': fixtureDir,
    'dryRun': dryRun,
    'scanned': htmlFiles.length,
    'unique': byHash.length,
    'removedCount': removed.length,
    'keptCount': kept.length,
    'groups': groups,
  };

  final reportPath = p.join(dir.path, 'dedupe_report.json');
  final manifestPath = p.join(dir.path, 'manifest.json');

  if (dryRun) {
    stdout.writeln('Dry run — no files deleted; report not written.');
    stdout.writeln(
      'Summary: keep ${kept.length}, delete ${removed.length}.',
    );
    // Still print a compact JSON summary to stdout for scripting.
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'scanned': htmlFiles.length,
      'unique': byHash.length,
      'removedCount': removed.length,
      'keptCount': kept.length,
    }));
    return;
  }

  for (final name in removed) {
    final file = File(p.join(dir.path, name));
    if (file.existsSync()) {
      await file.delete();
    }
  }

  // Rewrite manifest: keep entries whose fixture basename is still present,
  // attach sha256 for the kept file.
  final hashByBasename = <String, String>{
    for (final g in groups) g['kept']! as String: g['sha256']! as String,
  };

  List<Map<String, dynamic>> manifestEntries = [];
  final manifestFile = File(manifestPath);
  if (manifestFile.existsSync()) {
    final raw = jsonDecode(await manifestFile.readAsString());
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final fixture = map['fixture'] as String?;
        if (fixture == null) continue;
        final base = p.basename(fixture);
        if (!hashByBasename.containsKey(base)) continue;
        map['sha256'] = hashByBasename[base];
        map['deduped'] = true;
        manifestEntries.add(map);
      }
    }
  } else {
    // No prior manifest — synthesize minimal entries for kept files.
    for (final name in kept) {
      manifestEntries.add({
        'id': p.basenameWithoutExtension(name),
        'fixture': p.join(fixtureDir, name),
        'sha256': hashByBasename[name],
        'deduped': true,
      });
    }
  }

  manifestEntries.sort((a, b) {
    final ai = a['id'] as String? ?? '';
    final bi = b['id'] as String? ?? '';
    return ai.compareTo(bi);
  });

  await manifestFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifestEntries),
  );
  await File(reportPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );

  stdout.writeln('Deleted ${removed.length} duplicate HTML files.');
  stdout.writeln('Kept ${kept.length} unique fixtures.');
  stdout.writeln('Wrote $manifestPath (${manifestEntries.length} entries).');
  stdout.writeln('Wrote $reportPath');
}
