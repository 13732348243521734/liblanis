import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:intl/intl.dart';

import '../applet_context.dart';

/// The `k` (class) / `e` (entry) values the school portal resolves for a
/// given date's `stundenplan.php?a=detail_klasse` request (plan 4.6/5.3).
class TimetableNavigationTarget {
  final String k;
  final String e;

  const TimetableNavigationTarget({required this.k, required this.e});

  @override
  bool operator ==(Object other) =>
      other is TimetableNavigationTarget && other.k == k && other.e == e;

  @override
  int get hashCode => Object.hash(k, e);

  @override
  String toString() => 'TimetableNavigationTarget(k: $k, e: $e)';
}

/// A structural failure while following the portal's own `detail_klasse`
/// redirect -- too many hops, a redirect with no `Location`, or (via the
/// caller checking a `null` target) a final URL missing `k`/`e`. Plan 5.3
/// is explicit that this must be a clean, logged abort for that one date,
/// never a guess -- callers should catch this specifically and fall back
/// (e.g. to `timetable_history`) rather than let it propagate as a crash.
class TimetableRedirectException implements Exception {
  final String message;

  const TimetableRedirectException(this.message);

  @override
  String toString() => 'TimetableRedirectException: $message';
}

/// One HTTP hop's worth of information the redirect walker needs -- kept
/// separate from [Response]/[Dio] on purpose (see [resolveTimetableRedirect]).
typedef TimetableRedirectStep = ({int statusCode, String? location, String body});

/// Walks a `302` redirect chain starting at [startUrl] and resolves it to
/// a parsed [Document] plus whatever `k`/`e` the final URL carries (plan
/// 5.3: "Request ohne k/e schicken, dem Redirect folgen, k/e aus der
/// finalen URL lesen").
///
/// Deliberately takes [fetch] as a plain function instead of a [Dio]
/// instance: the algorithm itself (hop counting, relative/absolute
/// `Location` resolution, query-parameter extraction) has nothing to do
/// with HTTP and is fully testable without mocking a client -- only
/// [fetchTimetableFor] below supplies the real network call. The school
/// portal only ever uses status `302` for this kind of redirect (matching
/// `LanisSession`'s own `validateStatus`, which doesn't even accept the
/// other 3xx codes) -- anything else is treated as the final page.
///
/// Returns a `null` [TimetableNavigationTarget] (not a thrown exception)
/// when the final URL is simply missing `k` or `e` -- plan 5.3 explicitly
/// wants that treated as "feature disabled for this date", with the
/// caller deciding whether to still look at [Document] (e.g. its own
/// `#all`/`#own` structure) or just give up. Genuinely unrecoverable hops
/// (no `Location` on a redirect, or too many of them) throw
/// [TimetableRedirectException] instead, since there's no document to
/// return in those cases at all.
Future<(Document, TimetableNavigationTarget?)> resolveTimetableRedirect({
  required Uri startUrl,
  required Future<TimetableRedirectStep> Function(Uri url) fetch,
  int maxHops = 10,
}) async {
  var currentUrl = startUrl;
  var hops = 0;
  late TimetableRedirectStep step;

  while (true) {
    step = await fetch(currentUrl);
    if (step.statusCode != 302) break;

    hops++;
    if (hops > maxHops) {
      throw const TimetableRedirectException(
        'too many redirect hops resolving detail_klasse',
      );
    }
    final location = step.location;
    if (location == null) {
      throw const TimetableRedirectException(
        'redirect response had no Location header',
      );
    }
    // Uri.resolve handles both a relative reference (path+query only) and
    // an already-absolute one correctly per RFC 3986 -- no need to branch
    // on it ourselves.
    currentUrl = currentUrl.resolve(location);
  }

  final document = parse(step.body);
  final target = _parseNavigationTarget(currentUrl);
  return (document, target);
}

TimetableNavigationTarget? _parseNavigationTarget(Uri url) {
  final k = url.queryParameters['k'];
  final e = url.queryParameters['e'];
  if (k == null || k.isEmpty || e == null || e.isEmpty) return null;
  return TimetableNavigationTarget(k: k, e: e);
}

/// Live entry point (plan 5.3): resolves and fetches the timetable for
/// [date] by asking the portal's own `detail_klasse` redirect where to
/// look, rather than scraping/guessing `k`/`e` ourselves. Intended for
/// dates `timetable_history` doesn't have a snapshot for yet -- the
/// future, and any gap in the past history hasn't covered. See
/// [resolveTimetableRedirect] for the underlying algorithm and error
/// contract; this just wires it up to [ctx]'s real HTTP session.
Future<(Document, TimetableNavigationTarget?)> fetchTimetableFor({
  required AppletContext ctx,
  required DateTime date,
}) {
  final iso = DateFormat('yyyy-MM-dd').format(date);
  final startUrl = Uri.https(
    'start.schulportal.hessen.de',
    '/stundenplan.php',
    {'a': 'detail_klasse', 'date': iso},
  );

  return resolveTimetableRedirect(
    startUrl: startUrl,
    fetch: (url) async {
      final response = await ctx.session.dio.getUri(
        url,
        options: Options(followRedirects: false),
      );
      return (
        statusCode: response.statusCode ?? 0,
        location: response.headers.value('location'),
        body: response.data.toString(),
      );
    },
  );
}
