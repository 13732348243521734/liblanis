/// Capture the substitutions fixture matrix (plan: purge → ganzer → content → settings).
///
/// ```sh
/// dart run tool/substitutions/generate_inputs.dart
/// dart run tool/substitutions/capture_matrix.dart
/// dart run tool/substitutions/capture_matrix.dart --skip-content   # settings only
/// dart run tool/substitutions/capture_matrix.dart --restore-only
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'package:liblanis/easy_client.dart';
import 'package:path/path.dart' as p;

Map<String, String> loadDotEnv(String path) {
  final map = <String, String>{};
  for (final raw in File(path).readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue;
    final i = line.indexOf('=');
    var v = line.substring(i + 1).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    map[line.substring(0, i).trim()] = v;
  }
  return map;
}

String cb() => '_cachebreaker=${DateTime.now().millisecondsSinceEpoch}';

const ganzerSus = 'sus_x_Zugriff auf den gesamten Plan';
const ganzerLul = 'lul_x_Zugriff auf den gesamten Plan';

/// Full Weitere Einstellungen defaults (screenshot / school baseline).
const defaults = <String, String>{
  'strikeboard': 'nein',
  'lehrerklarBoard': 'nein',
  'stundenanzeigeBoard': 'kurz',
  'strike': 'nein',
  'lehrerklar': 'nein',
  'stundenanzeige': 'kurz',
  'vertretungsprotokoll': 'yes',
  'farbigeZeilen': 'no',
  'vergleichBeiSuS': 'klasse-stufe',
  'skipDays': 'no',
  'zeigeStand': 'nein',
  'zeigeStandLuL': 'nein',
};

/// One-factor non-default flips (field → value).
const oneFactorFlips = <({String field, String value})>[
  (field: 'strikeboard', value: 'ja'),
  (field: 'lehrerklarBoard', value: 'nachname'),
  (field: 'lehrerklarBoard', value: 'vorname'),
  (field: 'stundenanzeigeBoard', value: 'lang'),
  (field: 'strike', value: 'ja'),
  (field: 'lehrerklar', value: 'nachname'),
  (field: 'lehrerklar', value: 'vorname'),
  (field: 'stundenanzeige', value: 'lang'),
  (field: 'vertretungsprotokoll', value: 'no'),
  (field: 'farbigeZeilen', value: 'yes'),
  (field: 'vergleichBeiSuS', value: 'klasse-stufe-lerngruppe'),
  (field: 'vergleichBeiSuS', value: 'klasse-stufe-lerngruppe-stundenplan'),
  (field: 'skipDays', value: 'onlyInfos'),
  (field: 'zeigeStand', value: 'ja'),
  (field: 'zeigeStandLuL', value: 'ja'),
];

const contentCsvs = <String>[
  '01_single_entfall.csv',
  '02_raumvertretung_alts.csv',
  '03_range_multiclass.csv',
  '04_pausenaufsicht.csv',
  '06_two_days.csv',
  '08_today.csv',
];

Future<EasyLanisClient> login(String envPath, String ua) async {
  final env = loadDotEnv(envPath);
  final c = EasyLanisClient.ephemeral(
    schoolId: int.parse(env['SCHOOLID']!),
    username: env['USERNAME']!,
    password: env['PASSWORD']!,
    userAgent: ua,
  );
  await c.login();
  return c;
}

Future<void> saveSettings(Dio dio, Map<String, String> s) async {
  await dio.post(
    'https://start.schulportal.hessen.de/vertretungsplan.php?${cb()}',
    data: {'a': 'admin', 'b': 'more', ...s},
    options: Options(
      contentType: Headers.formUrlEncodedContentType,
      validateStatus: (_) => true,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 800));
}

Future<void> uploadCsv(Dio dio, String csvPath) async {
  const art = 'csv-kuerzel';
  const url = 'https://start.schulportal.hessen.de/vertretungsplan.php';

  Future<String> step(Map<String, dynamic> data) async {
    final r = await dio.post(
      '$url?${cb()}',
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (_) => true,
      ),
    );
    return '${r.data}'.trim();
  }

  final reset = await step({
    'a': 'upload',
    'manuell': '1',
    'reset': '1',
    'art': art,
    'upload': '1',
  });
  final upload = await dio.post(
    '$url?${cb()}',
    data: FormData.fromMap({
      'a': 'upload',
      'manuell': '1',
      'art': art,
      'd': await MultipartFile.fromFile(
        csvPath,
        filename: p.basename(csvPath),
      ),
    }),
    options: Options(validateStatus: (_) => true),
  );
  final unlock = await step({
    'a': 'upload',
    'manuell': '1',
    'unlock': '1',
    'art': art,
    'upload': '1',
  });
  stdout.writeln(
    '  upload ${p.basename(csvPath)} reset=$reset file=${upload.data} unlock=$unlock',
  );
  if (reset != '1' || '${upload.data}'.trim() != '1' || unlock != '1') {
    throw StateError('upload failed for $csvPath');
  }
  // Let SPH index the plan.
  await Future<void>.delayed(const Duration(seconds: 2));
}

Future<Map<String, bool>> readAnsicht(Dio dio) async {
  final r = await dio.get(
    'https://start.schulportal.hessen.de/vertretungsplan.php?a=admin&${cb()}',
    options: Options(validateStatus: (_) => true),
  );
  final doc = parse(r.data.toString());
  final out = <String, bool>{};
  for (final td in doc.querySelectorAll(
    'table#ansicht td[id^="sus"], table#ansicht td[id^="lul"], '
    'table#ansicht td[id^="boardsus"], table#ansicht td[id^="boardlul"], '
    'table#ansicht td[id^="block"]',
  )) {
    final id = td.id;
    if (id.isEmpty) continue;
    if (id.startsWith('block')) {
      out[id] = td.attributes['blockdel'] != '1';
    } else {
      out[id] = td.querySelector('span.glyphicon-ok') != null;
    }
  }
  return out;
}

Future<String> saveAnsicht(Dio dio, Map<String, bool> flags) async {
  final fields = <String, dynamic>{'ansicht': 'true', 'data[ansicht]': 'true'};
  for (final e in flags.entries) {
    fields['data[${e.key}]'] = e.value ? 'true' : 'false';
  }
  final r = await dio.post(
    'https://start.schulportal.hessen.de/vertretungsplan.php?a=admin&${cb()}',
    data: fields,
    options: Options(
      contentType: Headers.formUrlEncodedContentType,
      validateStatus: (_) => true,
      headers: {'X-Requested-With': 'XMLHttpRequest', 'Accept': '*/*'},
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 800));
  return r.data.toString().trim();
}

String pickTag(String html) {
  final dataTags = RegExp(r'data-tag="(\d{2}\.\d{2}\.\d{4})"')
      .allMatches(html)
      .map((m) => m.group(1)!)
      .toSet();
  if (dataTags.isNotEmpty) return dataTags.first;
  final panel = RegExp(r'id="tag(\d{2})_(\d{2})_(\d{4})"').firstMatch(html);
  if (panel != null) {
    return '${panel.group(1)}.${panel.group(2)}.${panel.group(3)}';
  }
  return DateFormat('dd.MM.yyyy')
      .format(DateTime.now().add(const Duration(days: 1)));
}

Future<Map<String, Object?>> captureRole({
  required Dio dio,
  required String role,
  required String outDir,
  required String label,
}) async {
  const url = 'https://start.schulportal.hessen.de/vertretungsplan.php';
  final pageResp = await dio.get(
    '$url?a=my&${cb()}',
    options: Options(validateStatus: (_) => true),
  );
  final html = pageResp.data.toString();
  final pagePath = p.join(outDir, '${label}__${role}__page.html');
  await File(pagePath).writeAsString(html);

  final tag = pickTag(html);
  final ajaxResp = await dio.post(
    '$url?a=my&${cb()}',
    data: {'tag': tag, 'kuerzel': '', 'ganzerPlan': 'true'},
    options: Options(
      contentType: Headers.formUrlEncodedContentType,
      validateStatus: (_) => true,
      headers: {'X-Requested-With': 'XMLHttpRequest', 'Accept': '*/*'},
    ),
  );
  final ajaxBody = ajaxResp.data.toString();
  final ajaxPath = p.join(outDir, '${label}__${role}__ajax.txt');
  await File(ajaxPath).writeAsString(ajaxBody);

  final looksJson =
      ajaxBody.trim().startsWith('[') || ajaxBody.trim().startsWith('{');
  int? jsonLen;
  if (looksJson) {
    try {
      final d = jsonDecode(ajaxBody);
      if (d is List) jsonLen = d.length;
    } catch (_) {}
  }

  final summary = <String, Object?>{
    'role': role,
    'label': label,
    'pageBytes': html.length,
    'hasBtnGanzer': html.contains('btn-ganzerplan'),
    'hasVtable': html.contains('id="vtable'),
    'dataTags': RegExp(r'data-tag="([^"]+)"')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toSet()
        .toList(),
    'ajaxTag': tag,
    'ajaxBytes': ajaxBody.length,
    'ajaxNeg1': ajaxBody.trim() == '-1',
    'ajaxLooksJson': looksJson,
    'ajaxJsonLen': jsonLen,
  };
  stdout.writeln(
    '  [$role] $label page=${html.length}b ganzerBtn=${summary['hasBtnGanzer']} '
    'ajax=${ajaxBody.length}b json=$looksJson len=$jsonLen neg1=${summary['ajaxNeg1']}',
  );
  return summary;
}

Future<List<Map<String, Object?>>> captureBoth({
  required Dio adminDio,
  required Dio studentDio,
  required String outDir,
  required String label,
}) async {
  final a = await captureRole(
    dio: adminDio,
    role: 'admin',
    outDir: outDir,
    label: label,
  );
  final s = await captureRole(
    dio: studentDio,
    role: 'student',
    outDir: outDir,
    label: label,
  );
  return [a, s];
}

Future<void> main(List<String> args) async {
  final restoreOnly = args.contains('--restore-only');
  final skipContent = args.contains('--skip-content');
  final skipSettings = args.contains('--skip-settings');

  final rawDir = 'tool/substitutions/discovery/capture_raw';
  Directory(rawDir).createSync(recursive: true);

  final admin = await login('.adminaccount.env', 'liblanis-vp-capture/0.1.0');
  final student =
      await login('.studentaccount.env', 'liblanis-vp-capture/0.1.0');
  final adminDio = admin.session!.dio;
  final studentDio = student.session!.dio;

  Future<void> restoreAll() async {
    stdout.writeln('=== restore settings + ganzer off');
    await saveSettings(adminDio, defaults);
    final ansicht = await readAnsicht(adminDio);
    ansicht[ganzerSus] = false;
    ansicht[ganzerLul] = false;
    final resp = await saveAnsicht(adminDio, ansicht);
    stdout.writeln('  ansicht save=$resp ganzer off');
  }

  if (restoreOnly) {
    await restoreAll();
    await admin.dispose();
    await student.dispose();
    return;
  }

  final report = <String, Object?>{
    'startedAt': DateTime.now().toIso8601String(),
    'captures': <Map<String, Object?>>[],
  };

  // --- A: enable ganzer plan ---
  stdout.writeln('=== enable Zugriff auf den gesamten Plan (sus+lul)');
  await saveSettings(adminDio, defaults);
  final before = await readAnsicht(adminDio);
  stdout.writeln(
    '  before $ganzerSus=${before[ganzerSus]} $ganzerLul=${before[ganzerLul]}',
  );
  await File(p.join(rawDir, 'ansicht_before.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(before),
  );
  final enabled = Map<String, bool>.from(before)
    ..[ganzerSus] = true
    ..[ganzerLul] = true;
  final saveResp = await saveAnsicht(adminDio, enabled);
  stdout.writeln('  saveAnsicht=$saveResp');
  final after = await readAnsicht(adminDio);
  stdout.writeln(
    '  after $ganzerSus=${after[ganzerSus]} $ganzerLul=${after[ganzerLul]}',
  );
  report['ganzer'] = {
    'saveResp': saveResp,
    'beforeSus': before[ganzerSus],
    'beforeLul': before[ganzerLul],
    'afterSus': after[ganzerSus],
    'afterLul': after[ganzerLul],
  };

  if (after[ganzerSus] != true || after[ganzerLul] != true) {
    stderr.writeln('WARN: ganzer-plan flags did not stick — continuing anyway');
  }

  // Sentinel: briefly capture with ganzer off mid-run? Plan wants 2 sentinels.
  // Capture sentinel_ganzer_off after we have content uploaded, then re-enable.
  // For now upload sink first so sentinel AJAX has a meaningful tag.

  final sink = 'tool/substitutions/inputs/07_settings_probe_sink.csv';
  if (!File(sink).existsSync()) {
    stderr.writeln('Missing $sink — run generate_inputs.dart');
    exitCode = 1;
    await admin.dispose();
    await student.dispose();
    return;
  }

  stdout.writeln('=== upload settings sink');
  await uploadCsv(adminDio, sink);

  // Verify AJAX works with ganzer on
  stdout.writeln('=== verify AJAX with ganzer on (baseline)');
  final verify = await captureBoth(
    adminDio: adminDio,
    studentDio: studentDio,
    outDir: rawDir,
    label: 'settings_baseline',
  );
  (report['captures'] as List).addAll(verify);

  // Sentinel: ganzer off
  stdout.writeln('=== sentinel: ganzer off');
  final off = Map<String, bool>.from(await readAnsicht(adminDio))
    ..[ganzerSus] = false
    ..[ganzerLul] = false;
  await saveAnsicht(adminDio, off);
  final sentOff = await captureBoth(
    adminDio: adminDio,
    studentDio: studentDio,
    outDir: rawDir,
    label: 'sentinel_ganzer_off',
  );
  (report['captures'] as List).addAll(sentOff);

  // Re-enable ganzer for the rest
  final onAgain = Map<String, bool>.from(await readAnsicht(adminDio))
    ..[ganzerSus] = true
    ..[ganzerLul] = true;
  await saveAnsicht(adminDio, onAgain);
  await saveSettings(adminDio, defaults);

  // --- C: content CSVs ---
  if (!skipContent) {
    stdout.writeln('=== content CSVs');
    for (final name in contentCsvs) {
      final path = p.join('tool/substitutions/inputs', name);
      if (!File(path).existsSync()) {
        stderr.writeln('skip missing $path');
        continue;
      }
      await saveSettings(adminDio, defaults);
      await uploadCsv(adminDio, path);
      final label = 'content_${p.basenameWithoutExtension(name)}';
      final caps = await captureBoth(
        adminDio: adminDio,
        studentDio: studentDio,
        outDir: rawDir,
        label: label,
      );
      (report['captures'] as List).addAll(caps);
    }
    // Re-upload sink for settings axis
    stdout.writeln('=== re-upload sink for settings');
    await uploadCsv(adminDio, sink);
  }

  // --- B: one-factor settings ---
  if (!skipSettings) {
    stdout.writeln('=== one-factor Weitere Einstellungen');
    for (final flip in oneFactorFlips) {
      final s = Map<String, String>.from(defaults);
      s[flip.field] = flip.value;
      await saveSettings(adminDio, s);
      final label =
          'set_${flip.field}_${flip.value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')}';
      final caps = await captureBoth(
        adminDio: adminDio,
        studentDio: studentDio,
        outDir: rawDir,
        label: label,
      );
      (report['captures'] as List).addAll(caps);
    }
  }

  // Sentinel: no_ganzer param (POST without ganzerPlan) — may return HTML
  stdout.writeln('=== sentinel: ajax missing ganzerPlan');
  await saveSettings(adminDio, defaults);
  final page = await adminDio.get(
    'https://start.schulportal.hessen.de/vertretungsplan.php?a=my&${cb()}',
  );
  final tag = pickTag(page.data.toString());
  final htmlBody = await adminDio.post(
    'https://start.schulportal.hessen.de/vertretungsplan.php?a=my&${cb()}',
    data: {'tag': tag},
    options: Options(
      contentType: Headers.formUrlEncodedContentType,
      validateStatus: (_) => true,
      headers: {'X-Requested-With': 'XMLHttpRequest'},
    ),
  );
  await File(p.join(rawDir, 'sentinel_no_ganzer_param__admin__page.html'))
      .writeAsString(page.data.toString());
  await File(p.join(rawDir, 'sentinel_no_ganzer_param__admin__ajax.txt'))
      .writeAsString(htmlBody.data.toString());
  (report['captures'] as List).add({
    'role': 'admin',
    'label': 'sentinel_no_ganzer_param',
    'ajaxBytes': htmlBody.data.toString().length,
    'ajaxIsHtml': htmlBody.data.toString().contains('<html'),
  });

  await restoreAll();

  report['finishedAt'] = DateTime.now().toIso8601String();
  await File(p.join(rawDir, 'capture_report.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  stdout.writeln('done → $rawDir/capture_report.json');

  await admin.dispose();
  await student.dispose();
}
