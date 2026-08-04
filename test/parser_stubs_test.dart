import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

void main() {
  // Parser HTTP fixture tests are deferred: the current test account does not
  // have stable/non-empty data for every applet. Generate anonymized fixtures
  // with `dart run tool/record_fixtures.dart` (local `.credentials.env` only),
  // then replace these stubs.

  group('substitutions parser', () {
    // TODO: Add anonymized fixture-based parser tests once this account
    // has stable substitution data (or commit empty-state fixtures).
  });

  group('calendar parser', () {
    // TODO: Add anonymized fixture-based parser tests once this account
    // has stable calendar data (or commit empty-state fixtures).
  });

  group('timetable parser', () {
    // Covered by test/timetable_parser_test.dart (raw HTML fixtures).
  });

  group('conversations parser', () {
    // TODO: Add anonymized fixture-based parser tests once this account
    // has stable conversation data (or commit empty-state fixtures).
  });

  group('lessons parser', () {
    // TODO: Add anonymized fixture-based parser tests once this account
    // has stable lesson data (or commit empty-state fixtures).
  });

  group('data_storage parser', () {
    // TODO: Add anonymized fixture-based parser tests once this account
    // has stable file-storage data (or commit empty-state fixtures).
  });

  group('study_groups parser', () {
    // TODO: Add anonymized fixture-based parser tests once this account
    // has stable study-group data (or commit empty-state fixtures).
  });

  // Keep the import used so the suite stays wired to liblanis.
  test('liblanis export is available for future parser tests', () {
    expect(AccountType.student, isNotNull);
  });
}
