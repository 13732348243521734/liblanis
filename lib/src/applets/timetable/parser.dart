import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:uuid/uuid.dart';

import '../../exceptions.dart';
import '../../models/time_of_day.dart';
import '../../models/timetable.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';
import 'history.dart';
import 'redirect.dart';

class TimetableStudentParser extends AppletParser<TimeTable> {
  TimetableStudentParser(
    AppletContext ctx, {
    Future<bool> Function()? isConnected,
  }) : super(
         ctx,
         Applets.timetable,
         isConnected:
             isConnected ?? () => ctx.session.connectionChecker.connected,
       );

  @override
  Future<TimeTable> getHome() async {
    final Document? document = await getTimetableDocument();
    if (document == null) throw NetworkException();
    final timetable = parseDocument(document);

    // Feature 2.5 (Stundenplanhistorie, plan 7.5): record this fetch as a
    // new history snapshot if -- and only if -- it actually differs from
    // the last one on file. Deliberately non-fatal: a history-write
    // failure (e.g. a locked DB) must never take down the main timetable
    // fetch, which is why this is wrapped separately rather than left to
    // propagate.
    try {
      runTimetableHistoryDiff(
        database: ctx.database,
        accountId: ctx.accountId,
        current: timetable,
        capturedAt: DateTime.now(),
      );
    } catch (_) {
      // Swallowed deliberately -- see comment above.
    }

    return timetable;
  }

  /// Live lookup for a week `timetable_history` doesn't have a snapshot
  /// for -- the future, or a gap in the past that predates the app's own
  /// tracking (plan 5.3 + 7.5's closing note: "Zukunft/Lücken werden live
  /// per Redirect-Request nachgeladen und zusätzlich in timetable_history
  /// gecacht"). [weekMonday] should be the Monday of the week wanted;
  /// results are cached under that same week so a later lookup for it is
  /// a synchronous [loadTimetableForWeek] instead of another network
  /// round-trip.
  ///
  /// Throws [TimetableRedirectException] when the portal's own redirect
  /// doesn't resolve cleanly for [weekMonday] (no k/e in the final URL,
  /// too many hops, a redirect with no Location -- see
  /// [fetchTimetableFor]'s doc comment for the full contract). Callers
  /// should treat that the same as "no data for this week" rather than
  /// letting it surface as a crash -- there's deliberately no fallback
  /// guess here, per plan 5.3.
  Future<TimeTable> fetchAndCacheTimetableForWeek(DateTime weekMonday) async {
    final (document, target, finalUrl) = await fetchTimetableFor(
      ctx: ctx,
      date: weekMonday,
    );
    if (target == null) {
      throw TimetableRedirectException(
        'final URL is missing k and/or e for the requested week '
        '(landed on: $finalUrl, page title: '
        '${document.querySelector('title')?.text.trim()})',
      );
    }
    final timetable = parseDocument(document);
    try {
      runTimetableHistoryDiff(
        database: ctx.database,
        accountId: ctx.accountId,
        current: timetable,
        capturedAt: weekMonday,
      );
    } catch (_) {
      // Non-fatal, same reasoning as the getHome() hook above: a
      // history-write failure must never take down a lookup the person
      // is actively waiting on.
    }
    return timetable;
  }

  /// Offline/fixture entry point used by tests and [getHome].
  TimeTable parseDocument(Document document) => parseDocumentHtml(document);

  /// Parse a raw `stundenplan.php` HTML body (fixtures / offline).
  TimeTable parseHtml(String html) => parseDocumentHtml(parse(html));

  /// Static HTML parse path for unit tests (no session required).
  static TimeTable parseDocumentHtml(Document document) {
    final tbodyAll = document.querySelector('#all tbody');
    final tbodyOwn = document.querySelector('#own tbody');
    final String? weekBadge = document
        .querySelector('#aktuelleWoche')
        ?.text
        .trim();

    // Missing full plan table: return empty rather than crashing (LANIS-MOBILE-I).
    if (tbodyAll == null) {
      return TimeTable(
        planForAll: const [],
        planForOwn: tbodyOwn == null ? null : parseRoomPlan(tbodyOwn),
        hours: const [],
        weekBadge: weekBadge,
      );
    }

    return TimeTable(
      planForAll: parseRoomPlan(tbodyAll),
      planForOwn: tbodyOwn == null ? null : parseRoomPlan(tbodyOwn),
      hours: parseRows(tbodyAll),
      weekBadge: weekBadge,
    );
  }

  @override
  TimeTable typeFromJson(String json) {
    return TimeTable.fromJson(jsonDecode(json));
  }

  Future<Document?> getTimetableDocument() async {
    // On the website, the user is redirected every time, if they do not have the query parameter set.
    // However, the data is still loaded correctly without redirection, so we avoid it here to save traffic.

    final response1 = await ctx.session.dio.get(
      'https://start.schulportal.hessen.de/stundenplan.php',
    );

    if (response1.data.toString().trim().isNotEmpty) {
      final document = parse(response1.data);
      if (document.getElementById('all') != null) {
        return document;
      }
    }

    if (response1.headers['location'] == null) {
      return null;
    }

    final response2 = await ctx.session.dio.get(
      'https://start.schulportal.hessen.de/${response1.headers['location']?[0]}',
    );
    return parse(response2.data);
  }

  Future<Element?> getTableBody(
    Document document, {
    TimeTableType timeTableType = TimeTableType.all,
  }) async {
    switch (timeTableType) {
      case TimeTableType.all:
        return document.querySelector('#all tbody');
      case TimeTableType.own:
        return document.querySelector('#own tbody');
    }
  }

  static List<TimetableDay> parseRoomPlan(Element tbody) {
    if (tbody.children.isEmpty) return const [];

    final dayCount = tbody.children[0].children.length - 1;
    if (dayCount <= 0) return const [];

    final List<TimetableDay> result = List.generate(dayCount, (_) => []);

    final List<(SphTimeOfDay, SphTimeOfDay)> timeSlots = tbody
        .querySelectorAll('.VonBis')
        .map(_parseVonBis)
        .whereType<(SphTimeOfDay, SphTimeOfDay)>()
        .toList();

    // Cover all table rows; + buffer for aggressive rowspan values.
    final List<List<bool>> alreadyParsed = List.generate(
      tbody.children.length + 32,
      (_) => List.generate(dayCount, (_) => false),
    );

    final bool timeslotOffsetFirstRow =
        tbody.children[0].children.isNotEmpty &&
        tbody.children[0].children[0].text.trim() != '';

    for (var (rowIndex, rowElement) in tbody.children.indexed) {
      if (rowIndex == 0) continue; // skip first empty/header row
      for (var (colIndex, colElement) in rowElement.children.indexed) {
        if (colIndex == 0) continue; // skip first column
        final int rowSpan = int.tryParse(
              colElement.attributes['rowspan'] ?? '1',
            ) ??
            1;

        var actualDay = colIndex - 1;
        while (actualDay < dayCount && alreadyParsed[rowIndex][actualDay]) {
          actualDay++;
        }
        // LANIS-MOBILE-3/7: rowspan layout walked past the last day column.
        if (actualDay >= dayCount) continue;

        // LANIS-MOBILE-M: rowspan extending past tracked rows.
        for (var i = 0; i < rowSpan; i++) {
          final r = rowIndex + i;
          if (r >= alreadyParsed.length) break;
          if (actualDay < alreadyParsed[r].length) {
            alreadyParsed[r][actualDay] = true;
          }
        }

        result[actualDay].addAll(
          parseSingeHour(
            colElement,
            rowIndex,
            timeSlots,
            timeslotOffsetFirstRow,
            actualDay,
          ),
        );
      }
    }
    return result;
  }

  static List<TimeTableRow> parseRows(Element tbody) {
    final List<TimeTableRow> result = [];
    for (var (rowIndex, rowElement) in tbody.children.indexed) {
      if (rowIndex == 0) continue;
      for (final colElement in rowElement.children) {
        final Element? e = colElement.querySelector('.VonBis');
        if (e == null) break;
        final Element? labelRoot = colElement.querySelector('.print-show');
        if (labelRoot == null) break;
        final label = labelRoot.querySelector('b') ?? labelRoot;
        final slot = _parseVonBis(e);
        if (slot == null) break;
        result.add(
          TimeTableRow(
            TimeTableRowType.lesson,
            slot.$1,
            slot.$2,
            label.text.trim(),
            rowIndex,
          ),
        );
        break;
      }
    }
    return result;
  }

  static List<TimetableSubject> parseSingeHour(
    Element cell,
    int y,
    List<(SphTimeOfDay, SphTimeOfDay)> timeSlots,
    bool timeslotOffsetFirstRow,
    int day,
  ) {
    final List<TimetableSubject> result = [];
    for (final row in cell.querySelectorAll('.stunde')) {
      final name = row.querySelector('b')?.text.trim();
      final raum = row.nodes
          .map((node) => node.nodeType == 3 ? node.text!.trim() : '')
          .join();
      final lehrer = row.querySelector('small')?.text.trim();
      final badge = row.querySelector('.badge')?.text.trim();
      final duration =
          int.tryParse(row.parent?.attributes['rowspan'] ?? '1') ?? 1;

      final startIndex = timeslotOffsetFirstRow ? y : y - 1;
      final endIndex = timeslotOffsetFirstRow
          ? y + duration - 1
          : y - 1 + duration - 1;

      // When VonBis is hidden (admin setting) or rowspan exceeds known slots,
      // still keep the lesson — clock times are best-effort / zeroed.
      final SphTimeOfDay startTime;
      final SphTimeOfDay endTime;
      if (timeSlots.isNotEmpty &&
          startIndex >= 0 &&
          endIndex >= 0 &&
          startIndex < timeSlots.length &&
          endIndex < timeSlots.length) {
        startTime = timeSlots[startIndex].$1;
        endTime = timeSlots[endIndex].$2;
      } else {
        startTime = const SphTimeOfDay(hour: 0, minute: 0);
        endTime = const SphTimeOfDay(hour: 0, minute: 0);
      }

      var id = row.attributes['data-mix'];
      if (id == null || id.isEmpty) {
        id = Uuid().v5(Namespace.url.value, name ?? raum).replaceAll('-', '');
      }

      result.add(
        TimetableSubject(
          id: '$id-$day-${startTime.hour}-${startTime.minute}',
          name: name,
          raum: raum,
          lehrer: lehrer,
          badge: badge,
          duration: duration,
          startTime: startTime,
          endTime: endTime,
          stunde: y,
        ),
      );
    }
    return result;
  }

  static (SphTimeOfDay, SphTimeOfDay)? _parseVonBis(Element e) {
    final timeString = e.text.trim();
    final s = timeString.split(' - ');
    if (s.length != 2) return null;
    final splitA = s[0].split(':');
    final splitB = s[1].split(':');
    if (splitA.length < 2 || splitB.length < 2) return null;
    final aHour = int.tryParse(splitA[0]);
    final aMin = int.tryParse(splitA[1]);
    final bHour = int.tryParse(splitB[0]);
    final bMin = int.tryParse(splitB[1]);
    if (aHour == null || aMin == null || bHour == null || bMin == null) {
      return null;
    }
    return (
      SphTimeOfDay(hour: aHour, minute: aMin),
      SphTimeOfDay(hour: bHour, minute: bMin),
    );
  }
}
