/// Shared conversions between the `tag_en` day-bucket key (`yyyy-MM-dd`,
/// used as the history-table bucket for Feature 1/2.5) and the
/// `dd.MM.yyyy` display format used elsewhere in this package (e.g.
/// [Substitution.tag], [SubstitutionDay.parsedDate]).
///
/// Kept in one place and exported from `liblanis.dart` so both this
/// package's own history code and downstream apps (which need to render
/// `tag_en` as a weekday/date) share one implementation instead of each
/// reimplementing the same parsing.
library;

/// Converts a `tag_en` bucket key (`yyyy-MM-dd`) to a [DateTime]. Returns
/// `null` if [tagEn] isn't in that shape (wrong segment count or
/// non-numeric segments) rather than throwing.
DateTime? tagEnToDateTime(String tagEn) {
  final parts = tagEn.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

/// Converts a `tag_en` bucket key (`yyyy-MM-dd`) to the `dd.MM.yyyy`
/// display format. Returns [tagEn] unchanged if it can't be parsed, so
/// callers always get a displayable string instead of having to handle
/// `null`.
String tagEnToParsedDate(String tagEn) {
  final date = tagEnToDateTime(tagEn);
  if (date == null) return tagEn;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year}';
}

/// Converts a `dd.MM.yyyy` display date to a `tag_en` bucket key
/// (`yyyy-MM-dd`). Returns `null` if [parsedDate] isn't in that shape.
String? parsedDateToTagEn(String parsedDate) {
  final parts = parsedDate.split('.');
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '$year-${two(month)}-${two(day)}';
}
