/// Admin discovery + Stundenplan CSV generator for timetable parser fixtures.
///
/// Loads credentials from `.adminaccount.env` (or `--env=path`) itself so the
/// shell `USERNAME` variable cannot collide. Never prints secret values.
///
/// ```sh
/// dart run tool/timetable/generate_csvs.dart
/// dart run tool/timetable/generate_csvs.dart --env=.adminaccount.env
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:liblanis/easy_client.dart';
import 'package:path/path.dart' as p;

const _header =
    'Id;Art;Lehrkraftkürzel;Fach;Kurs;Raum;Wochentag;Stunde;Woche;Klassen';

Map<String, String> _loadDotEnv(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('Env file not found: $path');
  }
  final map = <String, String>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    map[key] = value;
  }
  return map;
}

Future<void> main(List<String> args) async {
  var envPath = '.adminaccount.env';
  for (final arg in args) {
    if (arg.startsWith('--env=')) envPath = arg.substring('--env='.length);
  }

  final env = _loadDotEnv(envPath);
  final schoolId = int.tryParse(env['SCHOOLID'] ?? '');
  final username = env['USERNAME'];
  final password = env['PASSWORD'];
  if (schoolId == null ||
      username == null ||
      username.isEmpty ||
      password == null ||
      password.isEmpty) {
    stderr.writeln(
      'Missing SCHOOLID, USERNAME, or PASSWORD in $envPath.',
    );
    exitCode = 64;
    return;
  }

  final root = Directory.current.path;
  final csvDir = Directory(p.join(root, 'tool', 'timetable', 'csvs'));
  final discoveryDir = Directory(p.join(root, 'tool', 'timetable', 'discovery'));
  await csvDir.create(recursive: true);
  await discoveryDir.create(recursive: true);

  final client = EasyLanisClient.ephemeral(
    schoolId: schoolId,
    username: username,
    password: password,
    userAgent: 'liblanis-timetable-tool/0.1.0',
  );

  stdout.writeln('Logging in as admin (schoolId=$schoolId)...');
  await client.login();
  final session = client.session!;
  stdout.writeln(
    'Logged in. accountType=${session.accountTypeOrNull} '
    'applets=${client.supportedApplets.length}',
  );

  final discovery = await _discover(session, discoveryDir);
  await File(p.join(discoveryDir.path, 'summary.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(discovery.toJson()),
  );
  stdout.writeln(
    'Discovery: classes=${discovery.classes.length} '
    'courses=${discovery.courses.length} '
    'teachers=${discovery.teachers.length} '
    'subjects=${discovery.subjects.length} '
    'hours=${discovery.hourLabels}',
  );

  final plans = _buildPlans(discovery);
  if (plans.length < 20) {
    stderr.writeln('Expected >=20 plans, got ${plans.length}');
    exitCode = 1;
  }

  // Clear previous generated CSVs (keep directory).
  for (final entity in csvDir.listSync()) {
    if (entity is File && entity.path.endsWith('.csv')) {
      await entity.delete();
    }
  }

  final index = <Map<String, Object?>>[];
  for (final plan in plans) {
    final file = File(p.join(csvDir.path, '${plan.name}.csv'));
    await file.writeAsString('${plan.toCsv()}\n', encoding: utf8);
    index.add({
      'name': plan.name,
      'description': plan.description,
      'rows': plan.rows.length,
      'file': p.relative(file.path, from: root),
    });
    stdout.writeln('Wrote ${plan.name}.csv (${plan.rows.length} rows)');
  }

  await File(p.join(csvDir.path, 'index.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(index),
  );

  await client.logout();
  await client.dispose();
  stdout.writeln('Done. ${plans.length} CSV plans in ${csvDir.path}');
}

class Discovery {
  Discovery({
    required this.classes,
    required this.courses,
    required this.teachers,
    required this.subjects,
    required this.hourLabels,
    required this.weekModes,
  });

  final List<String> classes;
  final List<String> courses;
  final List<String> teachers;
  final List<String> subjects;
  final List<String> hourLabels;
  final List<String> weekModes;

  Map<String, Object?> toJson() => {
        'classes': classes,
        'courses': courses,
        'teachers': teachers,
        'subjects': subjects,
        'hourLabels': hourLabels,
        'weekModes': weekModes,
      };

  String classAt(int i) =>
      classes.isEmpty ? 'Klasse1' : classes[i % classes.length];

  String courseAt(int i, {String? klasse}) {
    if (courses.isNotEmpty) return courses[i % courses.length];
    final k = klasse ?? classAt(i);
    return '$k-';
  }

  String teacherAt(int i) =>
      teachers.isEmpty ? 'AAA' : teachers[i % teachers.length];

  String subjectAt(int i) =>
      subjects.isEmpty ? 'Mathe' : subjects[i % subjects.length];
}

class CsvRow {
  CsvRow({
    required this.id,
    this.art = 'Stunde',
    required this.teacher,
    required this.fach,
    required this.kurs,
    required this.raum,
    required this.wochentag,
    required this.stunde,
    this.woche = '',
    required this.klassen,
  });

  final String id;
  final String art;
  final String teacher;
  final String fach;
  final String kurs;
  final String raum;
  final int wochentag;
  final String stunde;
  final String woche;
  final String klassen;

  String toCsvLine() => [
        id,
        art,
        teacher,
        fach,
        kurs,
        raum,
        '$wochentag',
        stunde,
        woche,
        klassen,
      ].join(';');
}

class PlanVariant {
  PlanVariant({
    required this.name,
    required this.description,
    required this.rows,
  });

  final String name;
  final String description;
  final List<CsvRow> rows;

  String toCsv() => '$_header\n${rows.map((r) => r.toCsvLine()).join('\n')}';
}

Future<Discovery> _discover(LanisSession session, Directory out) async {
  final classes = <String>{};
  final courses = <String>{};
  final teachers = <String>{};
  final subjects = <String>{};
  var hourLabels = <String>[];
  final weekModes = <String>{'', 'A', 'B', 'G', 'U'};

  Future<Document?> fetch(String url, String saveAs) async {
    try {
      final response = await session.dio.get(url);
      final html = response.data.toString();
      await File(p.join(out.path, saveAs)).writeAsString(html);
      stdout.writeln('Saved discovery/$saveAs (${html.length} bytes)');
      return parse(html);
    } catch (e) {
      stderr.writeln('Failed GET $url: $e');
      return null;
    }
  }

  // Student-style Lerngruppen (may work for admin too).
  final lg = await fetch(
    'https://start.schulportal.hessen.de/lerngruppen.php',
    'lerngruppen.html',
  );
  if (lg != null) {
    _extractStudyGroups(lg, classes, courses, teachers, subjects);
  }

  // Admin Stundenplan pages — scrape forms / tables for raster & classes.
  for (final entry in [
    ('https://start.schulportal.hessen.de/stundenplan.php', 'stundenplan.html'),
    (
      'https://start.schulportal.hessen.de/stundenplan.php?e=1&a=upload',
      'stundenplan_upload.html',
    ),
    (
      'https://start.schulportal.hessen.de/stundenplan.php?a=raster',
      'stundenplan_raster.html',
    ),
    (
      'https://start.schulportal.hessen.de/stundenplan.php?a=schulwochen',
      'stundenplan_schulwochen.html',
    ),
    (
      'https://start.schulportal.hessen.de/benutzerverwaltung.php?a=userList&t=l',
      'benutzer_lehrer.html',
    ),
    (
      'https://start.schulportal.hessen.de/benutzerverwaltung.php?a=userList&t=s',
      'benutzer_schueler.html',
    ),
  ]) {
    final doc = await fetch(entry.$1, entry.$2);
    if (doc == null) continue;
    if (entry.$2.contains('raster')) {
      hourLabels = _extractHourLabels(doc);
    }
    if (entry.$2.contains('lehrer')) {
      teachers.addAll(_extractTeacherCodes(doc));
    }
    if (entry.$2.contains('schueler')) {
      classes.addAll(_extractStudentClasses(doc));
    }
    if (entry.$2.startsWith('stundenplan')) {
      classes.addAll(_extractSelectOptions(doc, keywords: ['klasse', 'class']));
      courses.addAll(_extractSelectOptions(doc, keywords: ['kurs', 'lg']));
      teachers.addAll(_extractTeacherCodes(doc));
      subjects.addAll(
        _extractSelectOptions(doc, keywords: ['fach', 'subject']),
      );
      weekModes.addAll(_extractWeekModes(doc));
    }
  }

  // Prefer codes scraped from Stundenplan navigation links / selects.
  for (final fileName in [
    'stundenplan.html',
    'stundenplan_upload.html',
    'lerngruppen.html',
  ]) {
    final f = File(p.join(out.path, fileName));
    if (!f.existsSync()) continue;
    final html = f.readAsStringSync();
    for (final m in RegExp(r'detail_klasse&k=([^&"\x27]+)').allMatches(html)) {
      classes.add(Uri.decodeComponent(m.group(1)!));
    }
    for (final m in RegExp(r'detail&e=1&t=([^&"\x27]+)').allMatches(html)) {
      teachers.add(Uri.decodeComponent(m.group(1)!));
    }
    final klasseSelect = RegExp(
      r'<select[^>]*id="klasse"[^>]*>(.*?)</select>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (klasseSelect != null) {
      for (final m in RegExp(
        r'<option[^>]*>([^<]+)</option>',
        caseSensitive: false,
      ).allMatches(klasseSelect.group(1)!)) {
        final v = m.group(1)!.trim();
        if (v.isNotEmpty) classes.add(v);
      }
    }
  }

  // Drop UI chrome mistaken for teacher codes.
  const uiNoise = {
    'Apps',
    'FAQ',
    'Foto',
    'Start',
    'Support',
    'Logout',
    'Pin',
    'PIN',
    'Admin',
  };
  teachers.removeWhere(uiNoise.contains);

  // Fallbacks for sparse test instances.
  if (classes.isEmpty) {
    classes.addAll(['1', '2', '3', 'G1', 'L1']);
  }
  if (teachers.isEmpty) {
    teachers.addAll(['AAA', 'BBB', 'CCC']);
  }
  if (subjects.isEmpty) {
    subjects.addAll(['M', 'D', 'E', 'Bio', 'Ch', 'Ph', 'Sp', 'Ku', 'Mu', 'Ge']);
  }
  if (hourLabels.isEmpty) {
    hourLabels = List.generate(11, (i) => '${i + 1}');
  }
  // Synthetic Kurs labels matching KB 621 ("Kursname-" / "Kursname-Zweig").
  if (courses.isEmpty) {
    for (final klasse in classes) {
      courses.add('$klasse-');
      courses.add('$klasse-M');
      courses.add('$klasse-D');
    }
  }

  return Discovery(
    classes: classes.toList()..sort(),
    courses: courses.toList()..sort(),
    teachers: teachers.toList()..sort(),
    subjects: subjects.toList()..sort(),
    hourLabels: hourLabels,
    weekModes: weekModes.toList(),
  );
}

void _extractStudyGroups(
  Document doc,
  Set<String> classes,
  Set<String> courses,
  Set<String> teachers,
  Set<String> subjects,
) {
  final table = doc.getElementById('LGs');
  if (table == null) {
    // Admin UI may use different markup — harvest any data-* / table cells.
    for (final row in doc.querySelectorAll('tr[data-id], tr[data-lerngruppe]')) {
      final name = row.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (name.isNotEmpty && name.length < 80) courses.add(name.split(' ').first);
    }
    return;
  }

  final heads = table
      .querySelectorAll('thead tr th')
      .map((e) => e.text.trim())
      .toList();
  for (final row in table.querySelectorAll('tbody tr')) {
    Element? cell(String key) {
      final i = heads.indexOf(key);
      if (i < 0 || i >= row.children.length) return null;
      return row.children[i];
    }

    final kurs = cell('Kurs')?.text.trim() ?? cell('Name')?.text.trim();
    if (kurs != null && kurs.isNotEmpty) {
      courses.add(kurs.split('\n').first.trim());
      // Kurs often encodes class prefix like "05a-M" or "M-05a".
      final m = RegExp(r'(\d{2}[a-zA-Z]?)').firstMatch(kurs);
      if (m != null) classes.add(m.group(1)!);
    }
    final klasse = cell('Klasse')?.text.trim() ?? cell('Klassen')?.text.trim();
    if (klasse != null && klasse.isNotEmpty) {
      for (final part in klasse.split(RegExp(r'[,;/]'))) {
        final t = part.trim();
        if (t.isNotEmpty) classes.add(t);
      }
    }
    final fach = cell('Fach')?.text.trim();
    if (fach != null && fach.isNotEmpty) subjects.add(fach);
    final lehrer = cell('Lehrkraft')?.text.trim();
    if (lehrer != null) {
      for (final token in lehrer.split(RegExp(r'\s+'))) {
        if (RegExp(r'^[A-Za-zÄÖÜäöüß]{2,5}$').hasMatch(token)) {
          teachers.add(token);
        }
      }
    }
  }
}

List<String> _extractHourLabels(Document doc) {
  final labels = <String>[];
  for (final row in doc.querySelectorAll('table tr')) {
    final first = row.children.isEmpty ? '' : row.children.first.text.trim();
    final m = RegExp(r'^(\d{1,2})$').firstMatch(first);
    if (m != null) labels.add(m.group(1)!);
  }
  for (final input in doc.querySelectorAll('input, td, th')) {
    final t = input.text.trim();
    if (RegExp(r'^\d{1,2}\.?$').hasMatch(t)) {
      labels.add(t.replaceAll('.', ''));
    }
  }
  final unique = labels.toSet().toList()
    ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  return unique;
}

Iterable<String> _extractTeacherCodes(Document doc) {
  final codes = <String>{};
  for (final el in doc.querySelectorAll(
    'td, th, option, span.badge, a, button',
  )) {
    final t = el.text.trim();
    if (RegExp(r'^[A-ZÄÖÜ][a-zäöüß]{1,3}$').hasMatch(t) ||
        RegExp(r'^[A-ZÄÖÜ]{2,4}$').hasMatch(t)) {
      codes.add(t);
    }
  }
  // Prefer data attributes if present.
  for (final el in doc.querySelectorAll('[data-kuerzel], [data-lehrer]')) {
    final v =
        el.attributes['data-kuerzel'] ?? el.attributes['data-lehrer'] ?? '';
    if (v.trim().isNotEmpty) codes.add(v.trim());
  }
  return codes;
}

Iterable<String> _extractStudentClasses(Document doc) {
  final classes = <String>{};
  for (final el in doc.querySelectorAll('td, option, span')) {
    final t = el.text.trim();
    if (RegExp(r'^\d{1,2}[a-zA-Z]$').hasMatch(t) ||
        RegExp(r'^[EQeq]\d{1,2}$').hasMatch(t)) {
      classes.add(t);
    }
  }
  return classes;
}

Iterable<String> _extractSelectOptions(
  Document doc, {
  required List<String> keywords,
}) {
  final values = <String>{};
  for (final select in doc.querySelectorAll('select')) {
    final meta =
        '${select.id} ${select.attributes['name'] ?? ''} ${select.className}'
            .toLowerCase();
    if (!keywords.any(meta.contains)) continue;
    for (final opt in select.querySelectorAll('option')) {
      final v = (opt.attributes['value'] ?? opt.text).trim();
      if (v.isNotEmpty && v != '-' && v.toLowerCase() != 'bitte wählen') {
        values.add(v);
      }
    }
  }
  return values;
}

Iterable<String> _extractWeekModes(Document doc) {
  final weeks = <String>{'', 'A', 'B', 'G', 'U'};
  final text = doc.body?.text ?? '';
  if (text.contains('gerade') || text.contains('ungerade')) {
    weeks.addAll(['G', 'U']);
  }
  if (RegExp(r'\bA-Woche\b|\bB-Woche\b').hasMatch(text)) {
    weeks.addAll(['A', 'B']);
  }
  return weeks;
}

List<PlanVariant> _buildPlans(Discovery d) {
  final maxHour = d.hourLabels.isEmpty ? 11 : int.parse(d.hourLabels.last);
  final k0 = d.classAt(0);
  final k1 = d.classAt(1);
  final k2 = d.classAt(2);
  final c0 = d.courseAt(0, klasse: k0);
  final c1 = d.courseAt(1, klasse: k1);
  final t0 = d.teacherAt(0);
  final t1 = d.teacherAt(1);
  final t2 = d.teacherAt(2);
  final s0 = d.subjectAt(0);
  final s1 = d.subjectAt(1);
  final s2 = d.subjectAt(2);
  final s3 = d.subjectAt(3);

  int id = 1;
  String nextId() => 'P${id++}';

  CsvRow hour({
    String? teacher,
    String? fach,
    String? kurs,
    String raum = 'R101',
    required int day,
    required String stunde,
    String woche = '',
    String? klassen,
    String art = 'Stunde',
  }) {
    return CsvRow(
      id: nextId(),
      art: art,
      teacher: teacher ?? t0,
      fach: fach ?? s0,
      kurs: art == 'Pausenaufsicht' ? '' : (kurs ?? c0),
      raum: raum,
      wochentag: day,
      stunde: stunde,
      woche: woche,
      klassen: klassen ?? k0,
    );
  }

  final plans = <PlanVariant>[
    PlanVariant(
      name: '01_empty',
      description: 'Header only — empty plan / missing lessons',
      rows: const [],
    ),
    PlanVariant(
      name: '02_single_monday_lesson',
      description: 'Single weekday only (dayCount==1 crash path)',
      rows: [hour(day: 1, stunde: '1')],
    ),
    PlanVariant(
      name: '03_full_week_basic',
      description: 'Mon–Fri one lesson each, single hour',
      rows: [
        for (var day = 1; day <= 5; day++)
          hour(
            day: day,
            stunde: '1',
            fach: d.subjectAt(day),
            teacher: d.teacherAt(day),
            kurs: d.courseAt(day, klasse: k0),
            raum: 'R${100 + day}',
          ),
      ],
    ),
    PlanVariant(
      name: '04_double_lessons_plus',
      description: 'Doppelstunden via 1+2 syntax',
      rows: [
        hour(day: 1, stunde: '1+2', fach: s0),
        hour(day: 2, stunde: '3+4', fach: s1, teacher: t1, kurs: c1),
        hour(day: 3, stunde: '5+6', fach: s2, teacher: t2),
      ],
    ),
    PlanVariant(
      name: '05_hour_ranges',
      description: 'Stundenbereiche 1-4 and 3-6',
      rows: [
        hour(day: 1, stunde: '1-4', fach: s0),
        hour(day: 2, stunde: '3-6', fach: s1, teacher: t1),
        if (maxHour >= 8) hour(day: 3, stunde: '7-8', fach: s2, teacher: t2),
      ],
    ),
    PlanVariant(
      name: '06_hour_lists',
      description: 'Comma-separated non-contiguous hours',
      rows: [
        hour(day: 1, stunde: '1, 2', fach: s0),
        hour(day: 2, stunde: '3, 4, 5', fach: s1, teacher: t1),
        hour(day: 3, stunde: '1, 2, 5, 6', fach: s2, teacher: t2),
      ],
    ),
    PlanVariant(
      name: '07_week_ab_split',
      description: 'A/B week badges on same slots',
      rows: [
        hour(day: 1, stunde: '1', woche: 'A', fach: s0),
        hour(day: 1, stunde: '1', woche: 'B', fach: s1, teacher: t1, kurs: c1),
        hour(day: 2, stunde: '2', woche: 'A', fach: s2),
        hour(day: 2, stunde: '2', woche: 'B', fach: s3, teacher: t2),
      ],
    ),
    PlanVariant(
      name: '08_week_gu_split',
      description: 'G/U (gerade/ungerade) week badges',
      rows: [
        hour(day: 1, stunde: '1', woche: 'G', fach: s0),
        hour(day: 1, stunde: '1', woche: 'U', fach: s1, teacher: t1),
        hour(day: 3, stunde: '3+4', woche: 'G', fach: s2, teacher: t2),
        hour(day: 3, stunde: '3+4', woche: 'U', fach: s3, teacher: t0, kurs: c1),
      ],
    ),
    PlanVariant(
      name: '09_stacked_same_slot',
      description: 'Multiple subjects in the same day/hour cell',
      rows: [
        hour(day: 1, stunde: '1', fach: s0, teacher: t0, kurs: c0, raum: 'R1'),
        hour(day: 1, stunde: '1', fach: s1, teacher: t1, kurs: c1, raum: 'R2'),
        hour(
          day: 1,
          stunde: '1',
          fach: s2,
          teacher: t2,
          kurs: d.courseAt(2, klasse: k0),
          raum: 'R3',
          klassen: k0,
        ),
      ],
    ),
    PlanVariant(
      name: '10_rowspan_long_block',
      description: 'Long contiguous block spanning many hours (rowspan stress)',
      rows: [
        hour(day: 1, stunde: '1-$maxHour', fach: s0),
        hour(day: 2, stunde: '1-${maxHour >= 6 ? 6 : maxHour}', fach: s1, teacher: t1),
      ],
    ),
    PlanVariant(
      name: '11_dense_rowspan_grid',
      description: 'Overlapping rowspans across days to stress column walk',
      rows: [
        for (var day = 1; day <= 5; day++) ...[
          hour(
            day: day,
            stunde: '1+2',
            fach: d.subjectAt(day),
            teacher: d.teacherAt(day),
            raum: 'A$day',
          ),
          hour(
            day: day,
            stunde: '3',
            fach: d.subjectAt(day + 3),
            teacher: d.teacherAt(day + 2),
            raum: 'B$day',
          ),
          hour(
            day: day,
            stunde: '4+5',
            fach: d.subjectAt(day + 5),
            teacher: d.teacherAt(day + 4),
            raum: 'C$day',
          ),
        ],
      ],
    ),
    PlanVariant(
      name: '12_pausenaufsicht_mixed',
      description: 'Pausenaufsicht rows mixed with Stunde',
      rows: [
        hour(day: 1, stunde: '1', fach: s0),
        hour(
          day: 1,
          stunde: '2',
          art: 'Pausenaufsicht',
          fach: '',
          kurs: '',
          raum: 'Großer Hof 1',
          teacher: t1,
        ),
        hour(day: 1, stunde: '2', fach: s1, teacher: t0),
        hour(
          day: 2,
          stunde: '2/3',
          art: 'Pausenaufsicht',
          fach: '',
          kurs: '',
          raum: 'Großer Hof 2',
          teacher: t2,
        ),
        hour(day: 2, stunde: '3', fach: s2, teacher: t1),
      ],
    ),
    PlanVariant(
      name: '13_multi_class_same_lesson',
      description: 'One lesson assigned to multiple Klassen',
      rows: [
        hour(
          day: 1,
          stunde: '1',
          klassen: '$k0,$k1',
          fach: s0,
          kurs: '$k0-',
        ),
        hour(
          day: 2,
          stunde: '2+3',
          klassen: '$k0,$k1,$k2',
          fach: s1,
          teacher: t1,
          kurs: '$k1-',
        ),
      ],
    ),
    PlanVariant(
      name: '14_weekend_sunday',
      description: 'Sunday (Wochentag=7) plus Saturday if used',
      rows: [
        hour(day: 6, stunde: '1', fach: s0),
        hour(day: 7, stunde: '1', fach: s1, teacher: t1),
        hour(day: 7, stunde: '2+3', fach: s2, teacher: t2),
      ],
    ),
    PlanVariant(
      name: '15_last_hour_overflow',
      description: 'Lessons pinned to last raster hours (index overflow path)',
      rows: [
        hour(day: 1, stunde: '$maxHour', fach: s0),
        hour(
          day: 2,
          stunde: maxHour >= 2 ? '${maxHour - 1}+$maxHour' : '$maxHour',
          fach: s1,
          teacher: t1,
        ),
        hour(
          day: 3,
          stunde: maxHour >= 3 ? '${maxHour - 2}-$maxHour' : '$maxHour',
          fach: s2,
          teacher: t2,
        ),
      ],
    ),
    PlanVariant(
      name: '16_all_days_all_hours_sparse',
      description: 'Every weekday, alternating hours across full raster',
      rows: [
        for (var day = 1; day <= 5; day++)
          for (var h = 1; h <= maxHour; h += 2)
            hour(
              day: day,
              stunde: '$h',
              fach: d.subjectAt(day + h),
              teacher: d.teacherAt(day + h),
              kurs: d.courseAt(day + h, klasse: k0),
              raum: 'R${day * 10 + h}',
            ),
      ],
    ),
    PlanVariant(
      name: '17_two_classes_parallel',
      description: 'Parallel plans for two Klassen filling the grid',
      rows: [
        for (var day = 1; day <= 5; day++) ...[
          hour(
            day: day,
            stunde: '1+2',
            klassen: k0,
            kurs: d.courseAt(0, klasse: k0),
            fach: s0,
            teacher: t0,
            raum: 'K0-$day',
          ),
          hour(
            day: day,
            stunde: '1+2',
            klassen: k1,
            kurs: d.courseAt(1, klasse: k1),
            fach: s1,
            teacher: t1,
            raum: 'K1-$day',
          ),
          hour(
            day: day,
            stunde: '3',
            klassen: k0,
            kurs: d.courseAt(2, klasse: k0),
            fach: s2,
            teacher: t2,
          ),
          hour(
            day: day,
            stunde: '3',
            klassen: k1,
            kurs: d.courseAt(3, klasse: k1),
            fach: s3,
            teacher: t0,
          ),
        ],
      ],
    ),
    PlanVariant(
      name: '18_mixed_formats_kitchen_sink',
      description: 'Mix of +, ranges, lists, weeks, pause, multi-class',
      rows: [
        hour(day: 1, stunde: '1', woche: '', fach: s0),
        hour(day: 1, stunde: '2+3', woche: 'A', fach: s1, teacher: t1),
        hour(day: 1, stunde: '2+3', woche: 'B', fach: s2, teacher: t2),
        hour(day: 2, stunde: '1-3', fach: s3, teacher: t0, klassen: '$k0,$k1'),
        hour(day: 3, stunde: '4, 5', fach: s0, teacher: t1),
        hour(
          day: 3,
          stunde: '4',
          art: 'Pausenaufsicht',
          fach: '',
          kurs: '',
          raum: 'Hof',
          teacher: t2,
        ),
        hour(day: 4, stunde: '1+2', woche: 'G', fach: s1),
        hour(day: 4, stunde: '1+2', woche: 'U', fach: s2, teacher: t1),
        hour(day: 5, stunde: '$maxHour', fach: s3, teacher: t2),
      ],
    ),
    PlanVariant(
      name: '19_minimal_own_plan_signal',
      description: 'Kurs names matching Lerngruppen style for personal (#own) plan',
      rows: [
        hour(
          day: 1,
          stunde: '1',
          kurs: c0,
          klassen: k0,
          fach: s0,
          teacher: t0,
        ),
        hour(
          day: 1,
          stunde: '2',
          kurs: c0,
          klassen: k0,
          fach: s1,
          teacher: t1,
        ),
        hour(
          day: 2,
          stunde: '1+2',
          kurs: c0,
          klassen: k0,
          fach: s2,
          teacher: t2,
        ),
        hour(
          day: 3,
          stunde: '3',
          kurs: c1,
          klassen: k1,
          fach: s3,
          teacher: t0,
        ),
      ],
    ),
    PlanVariant(
      name: '20_collision_heavy',
      description: 'Many overlapping entries same day to stress alreadyParsed',
      rows: [
        for (var i = 0; i < 8; i++)
          hour(
            day: 1,
            stunde: i.isEven ? '1+2' : '2+3',
            fach: d.subjectAt(i),
            teacher: d.teacherAt(i),
            kurs: d.courseAt(i, klasse: k0),
            raum: 'X$i',
            woche: i % 3 == 0
                ? 'A'
                : i % 3 == 1
                    ? 'B'
                    : '',
          ),
        for (var day = 2; day <= 5; day++)
          hour(
            day: day,
            stunde: '1-4',
            fach: d.subjectAt(day),
            teacher: d.teacherAt(day),
            raum: 'Y$day',
          ),
      ],
    ),
    PlanVariant(
      name: '21_single_hour_midday',
      description: 'Only mid-day hour across week (sparse columns)',
      rows: [
        for (var day = 1; day <= 5; day++)
          hour(
            day: day,
            stunde: '${maxHour >= 5 ? 5 : 1}',
            fach: d.subjectAt(day),
            teacher: d.teacherAt(day),
          ),
      ],
    ),
    PlanVariant(
      name: '22_three_day_only',
      description: 'Tue/Thu/Fri only — irregular day set',
      rows: [
        hour(day: 2, stunde: '1+2', fach: s0),
        hour(day: 2, stunde: '3', fach: s1, teacher: t1),
        hour(day: 4, stunde: '1-3', fach: s2, teacher: t2),
        hour(day: 5, stunde: '4, 5, 6', fach: s3, teacher: t0),
      ],
    ),
    PlanVariant(
      name: '23_pause_before_each_hour',
      description: 'Pausenaufsicht before hours 2..N plus lessons',
      rows: [
        for (var h = 2; h <= (maxHour > 6 ? 6 : maxHour); h++)
          hour(
            day: 1,
            stunde: '$h',
            art: 'Pausenaufsicht',
            fach: '',
            kurs: '',
            raum: 'Hof $h',
            teacher: d.teacherAt(h),
          ),
        for (var h = 1; h <= (maxHour > 6 ? 6 : maxHour); h++)
          hour(day: 1, stunde: '$h', fach: d.subjectAt(h), teacher: d.teacherAt(h + 1)),
      ],
    ),
    PlanVariant(
      name: '24_full_grid_mon_fri',
      description: 'Complete Mon–Fri grid every hour for class 1 — max HTML complexity',
      rows: [
        for (var day = 1; day <= 5; day++)
          for (var h = 1; h <= maxHour; h++)
            hour(
              day: day,
              stunde: '$h',
              fach: d.subjectAt(day * 3 + h),
              teacher: d.teacherAt(day + h),
              kurs: d.courseAt(day + h, klasse: k0),
              klassen: k0,
              raum: 'R${day}${h.toString().padLeft(2, '0')}',
            ),
      ],
    ),
  ];

  // Unique ids + unique room tokens (RM<planNo><row>) for cachebreaker polling.
  return [
    for (final plan in plans)
      PlanVariant(
        name: plan.name,
        description: plan.description,
        rows: [
          for (var i = 0; i < plan.rows.length; i++)
            CsvRow(
              id: '${plan.name}-$i',
              art: plan.rows[i].art,
              teacher: plan.rows[i].teacher,
              fach: plan.rows[i].fach,
              kurs: plan.rows[i].kurs,
              raum: 'RM${plan.name.split('_').first}-$i',
              wochentag: plan.rows[i].wochentag,
              stunde: plan.rows[i].stunde,
              woche: plan.rows[i].woche,
              klassen: plan.rows[i].klassen,
            ),
        ],
      ),
  ];
}
