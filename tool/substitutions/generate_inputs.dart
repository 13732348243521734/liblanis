/// Build Vertretungsplan CSV upload variants (csv-kuerzel) for school 5690.
///
/// Header order from SPH KB 477 attachment. Uses Klassen/Lehrer from
/// tool/timetable/discovery/summary.json when present.
///
/// ```sh
/// dart run tool/substitutions/generate_inputs.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

const csvHeader =
    'Tag;Lehrer;Stunde;Klasse;Art;Vertreter;Fach;Raum;Hinweis;Raum_alt;Fach_alt;Klasse_alt;Hinweis2';

String row({
  required String tag,
  required String lehrer,
  required String stunde,
  required String klasse,
  required String art,
  String vertreter = '',
  required String fach,
  required String raum,
  required String hinweis,
  String raumAlt = '',
  String fachAlt = '',
  String klasseAlt = '',
  String hinweis2 = '',
}) {
  return [
    tag,
    lehrer,
    stunde,
    klasse,
    art,
    vertreter,
    fach,
    raum,
    hinweis,
    raumAlt,
    fachAlt,
    klasseAlt,
    hinweis2,
  ].join(';');
}

Future<void> main() async {
  final out = Directory('tool/substitutions/inputs')..createSync(recursive: true);

  var classes = <String>['1', '2', '3', 'G1', 'G2'];
  var teachers = <String>['lernsys'];
  var subjects = <String>['M', 'D', 'E', 'Bio'];
  final summaryFile = File('tool/timetable/discovery/summary.json');
  if (summaryFile.existsSync()) {
    final s = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
    classes = (s['classes'] as List?)?.map((e) => '$e').toList() ?? classes;
    teachers = (s['teachers'] as List?)?.map((e) => '$e').toList() ?? teachers;
    subjects = (s['subjects'] as List?)?.map((e) => '$e').toList() ?? subjects;
  }

  final t = teachers.first;
  final day0 = DateTime.now();
  final day1 = day0.add(const Duration(days: 1));
  final day2 = day0.add(const Duration(days: 2));
  String iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  final variants = <Map<String, Object?>>[];

  void writeCsv(String name, String description, List<String> lines) {
    final body = '$csvHeader\n${lines.join('\n')}\n';
    final file = 'tool/substitutions/inputs/$name.csv';
    File(p.join(out.path, '$name.csv')).writeAsStringSync(body);
    variants.add({
      'name': name,
      'description': description,
      'file': file,
      'format': 'csv-kuerzel',
      'rows': lines.length,
      'fingerprintPrefix': 'RM$name',
    });
    stdout.writeln('$name: ${lines.length} rows -> $file');
  }

  // 01 — minimal single cancellation tomorrow
  writeCsv('01_single_entfall', 'One Entfall tomorrow for Klasse 1', [
    row(
      tag: iso(day1),
      lehrer: t,
      stunde: '1',
      klasse: classes[0],
      art: 'Entfall',
      fach: subjects.contains('M') ? 'M' : subjects.first,
      raum: 'R101',
      hinweis: 'RM01_single_entfall',
    ),
  ]);

  // 02 — room change with _alt columns
  writeCsv('02_raumvertretung_alts', 'Raumvertretung with Raum_alt/Fach_alt', [
    row(
      tag: iso(day1),
      lehrer: t,
      stunde: '2',
      klasse: classes.length > 1 ? classes[1] : classes[0],
      art: 'Raumvertretung',
      vertreter: t,
      fach: subjects.contains('E') ? 'E' : subjects.first,
      raum: 'R202',
      hinweis: 'RM02_raumvertretung',
      raumAlt: 'R101',
      fachAlt: subjects.contains('D') ? 'D' : subjects.first,
      klasseAlt: classes[0],
    ),
  ]);

  // 03 — hour range + multi-class
  writeCsv('03_range_multiclass', 'Hour range and multi-class cell', [
    row(
      tag: iso(day1),
      lehrer: t,
      stunde: '3-4',
      klasse: classes.take(3).join(', '),
      art: 'Betreuung',
      vertreter: t,
      fach: subjects.contains('D') ? 'D' : subjects.first,
      raum: 'R303',
      hinweis: 'RM03_range_multiclass',
    ),
  ]);

  // 04 — pause / aufsicht style hour
  writeCsv('04_pausenaufsicht', 'Pause between hours as 2/3', [
    row(
      tag: iso(day1),
      lehrer: t,
      stunde: '2/3',
      klasse: '',
      art: 'Pausenaufsichtsvertretung',
      vertreter: t,
      fach: 'Pause',
      raum: 'Hof',
      hinweis: 'RM04_pausenaufsicht',
    ),
  ]);

  // 05 — infos-heavy day: only Entfall rows (SPH may build info blocks)
  writeCsv('05_entfall_block', 'Several Entfall rows for info-block formation', [
    for (final k in classes.take(4))
      row(
        tag: iso(day1),
        lehrer: t,
        stunde: '1',
        klasse: k,
        art: 'Entfall',
        fach: 'M',
        raum: 'R1',
        hinweis: 'RM05_entfall_$k',
      ),
  ]);

  // 06 — two days
  writeCsv('06_two_days', 'Rows on tomorrow and day+2', [
    row(
      tag: iso(day1),
      lehrer: t,
      stunde: '1',
      klasse: classes[0],
      art: 'Tausch',
      vertreter: t,
      fach: 'M',
      raum: 'R1',
      hinweis: 'RM06_day1',
    ),
    row(
      tag: iso(day2),
      lehrer: t,
      stunde: '5',
      klasse: classes.length > 2 ? classes[2] : classes[0],
      art: 'Sondereinsatz',
      vertreter: t,
      fach: 'Bio',
      raum: 'R5',
      hinweis: 'RM06_day2',
    ),
  ]);

  // 07 — kitchen sink for settings probes (diverse arts + alts)
  writeCsv('07_settings_probe_sink', 'Dense plan for settings A/B captures', [
    row(
      tag: iso(day1),
      lehrer: t,
      stunde: '1',
      klasse: classes[0],
      art: 'Entfall',
      fach: 'M',
      raum: 'R101',
      hinweis: 'RM07_sink_entfall',
    ),
    row(
      tag: iso(day1),
      lehrer: t,
      stunde: '2',
      klasse: classes.length > 1 ? classes[1] : classes[0],
      art: 'Raumvertretung',
      vertreter: t,
      fach: 'E',
      raum: 'R202',
      hinweis: 'RM07_sink_raum',
      raumAlt: 'R100',
      fachAlt: 'D',
    ),
    row(
      tag: iso(day1),
      lehrer: t,
      stunde: '3-4',
      klasse: classes.length > 3 ? classes[3] : classes[0],
      art: 'Vertretung',
      vertreter: t,
      fach: 'D',
      raum: 'R303',
      hinweis: 'RM07_sink_vtr',
    ),
    row(
      tag: iso(day1),
      lehrer: t,
      stunde: '5',
      klasse: classes.length > 4 ? classes[4] : classes[0],
      art: 'Betreuung',
      fach: 'Sp',
      raum: 'Halle',
      hinweis: 'RM07_sink_betreuung',
    ),
    row(
      tag: iso(day1),
      lehrer: t,
      stunde: '6',
      klasse: classes[0],
      art: 'Sondereinsatz',
      vertreter: t,
      fach: 'Ku',
      raum: 'R6',
      hinweis: 'RM07_sink_sonder',
    ),
    row(
      tag: iso(day2),
      lehrer: t,
      stunde: '1-2',
      klasse: classes[0],
      art: 'Freisetzung',
      fach: 'M',
      raum: 'R1',
      hinweis: 'RM07_sink_day2',
    ),
  ]);

  // 08 — today (must be >= today per SPH)
  writeCsv('08_today', 'Single row for today', [
    row(
      tag: iso(day0),
      lehrer: t,
      stunde: '8',
      klasse: classes[0],
      art: 'Klausur/Arbeit',
      fach: 'M',
      raum: 'R8',
      hinweis: 'RM08_today',
    ),
  ]);

  final index = {
    'generatedAt': DateTime.now().toIso8601String(),
    'format': 'csv-kuerzel',
    'header': csvHeader,
    'classesUsed': classes,
    'teachersUsed': teachers,
    'variants': variants,
  };
  await File(p.join(out.path, 'index.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(index),
  );
  stdout.writeln('Wrote ${variants.length} CSVs + index.json');
}
