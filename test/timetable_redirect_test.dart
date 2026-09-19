import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

/// Builds a scripted `fetch` for [resolveTimetableRedirect] out of a plain
/// list of steps, in order -- one entry per HTTP hop the test wants to
/// simulate. No Dio/mocking involved (see the doc comment on
/// [resolveTimetableRedirect] for why the algorithm is factored to allow
/// this).
Future<TimetableRedirectStep> Function(Uri url) scripted(
  List<TimetableRedirectStep> steps,
) {
  var i = 0;
  return (Uri url) async {
    if (i >= steps.length) {
      fail('fetch() called more times than the test scripted (url: $url)');
    }
    return steps[i++];
  };
}

const finalPageBody = '<html><body>plan</body></html>';

void main() {
  final startUrl = Uri.parse(
    'https://start.schulportal.hessen.de/stundenplan.php'
    '?a=detail_klasse&date=2026-09-21',
  );

  group('resolveTimetableRedirect', () {
    test('single 302 with an absolute Location -> resolves k/e', () async {
      final (document, target) = await resolveTimetableRedirect(
        startUrl: startUrl,
        fetch: scripted([
          (
            statusCode: 302,
            location:
                'https://start.schulportal.hessen.de/stundenplan.php'
                '?a=detail_klasse&k=Ec&e=42&date=2026-09-21',
            body: '',
          ),
          (statusCode: 200, location: null, body: finalPageBody),
        ]),
      );
      expect(target, TimetableNavigationTarget(k: 'Ec', e: '42'));
      expect(document.body?.text, 'plan');
    });

    test('single 302 with a relative Location -> resolved against the '
        'previous URL', () async {
      final (_, target) = await resolveTimetableRedirect(
        startUrl: startUrl,
        fetch: scripted([
          (
            statusCode: 302,
            location: 'stundenplan.php?a=detail_klasse&k=1&e=7&date=2026-09-21',
            body: '',
          ),
          (statusCode: 200, location: null, body: finalPageBody),
        ]),
      );
      expect(target, TimetableNavigationTarget(k: '1', e: '7'));
    });

    test('multiple 302s in a row -> follows through to the final k/e', () async {
      final (_, target) = await resolveTimetableRedirect(
        startUrl: startUrl,
        fetch: scripted([
          (
            statusCode: 302,
            location: '/stundenplan.php?a=detail_klasse&date=2026-09-21',
            body: '',
          ),
          (
            statusCode: 302,
            location:
                '/stundenplan.php?a=detail_klasse&k=9&e=3&date=2026-09-21',
            body: '',
          ),
          (statusCode: 200, location: null, body: finalPageBody),
        ]),
      );
      expect(target, TimetableNavigationTarget(k: '9', e: '3'));
    });

    test('no redirect at all -> document returned, target null (no k/e '
        'in the query we sent)', () async {
      final (document, target) = await resolveTimetableRedirect(
        startUrl: startUrl,
        fetch: scripted([
          (statusCode: 200, location: null, body: finalPageBody),
        ]),
      );
      expect(target, isNull);
      expect(document.body?.text, 'plan');
    });

    test('final URL missing e -> target is null, not a guess', () async {
      final (_, target) = await resolveTimetableRedirect(
        startUrl: startUrl,
        fetch: scripted([
          (
            statusCode: 302,
            location: '/stundenplan.php?a=detail_klasse&k=1&date=2026-09-21',
            body: '',
          ),
          (statusCode: 200, location: null, body: finalPageBody),
        ]),
      );
      expect(target, isNull);
    });

    test('final URL missing k -> target is null, not a guess', () async {
      final (_, target) = await resolveTimetableRedirect(
        startUrl: startUrl,
        fetch: scripted([
          (
            statusCode: 302,
            location: '/stundenplan.php?a=detail_klasse&e=5&date=2026-09-21',
            body: '',
          ),
          (statusCode: 200, location: null, body: finalPageBody),
        ]),
      );
      expect(target, isNull);
    });

    test('302 with no Location header -> clean abort via exception', () async {
      expect(
        () => resolveTimetableRedirect(
          startUrl: startUrl,
          fetch: scripted([(statusCode: 302, location: null, body: '')]),
        ),
        throwsA(isA<TimetableRedirectException>()),
      );
    });

    test('too many hops -> clean abort via exception, never an infinite '
        'loop', () async {
      final infiniteSteps = List.generate(
        50,
        (_) => (
          statusCode: 302,
          location: '/stundenplan.php?a=detail_klasse&date=2026-09-21',
          body: '',
        ),
      );
      expect(
        () => resolveTimetableRedirect(
          startUrl: startUrl,
          fetch: scripted(infiniteSteps),
          maxHops: 5,
        ),
        throwsA(isA<TimetableRedirectException>()),
      );
    });

    test('a non-302 3xx status is treated as final, not followed', () async {
      // LanisSession's own dio only ever accepts 200/302/503 -- 303/307
      // etc. never actually occur here, but resolveTimetableRedirect
      // should still degrade safely (target null) rather than trying to
      // follow a Location it has no contract to expect.
      final (_, target) = await resolveTimetableRedirect(
        startUrl: startUrl,
        fetch: scripted([
          (
            statusCode: 303,
            location:
                '/stundenplan.php?a=detail_klasse&k=1&e=1&date=2026-09-21',
            body: finalPageBody,
          ),
        ]),
      );
      expect(target, isNull);
    });
  });
}
