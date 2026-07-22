/// Dart-only replacement for Flutter's [TimeOfDay].
class SphTimeOfDay implements Comparable<SphTimeOfDay> {
  final int hour;
  final int minute;

  const SphTimeOfDay({required this.hour, required this.minute});

  factory SphTimeOfDay.fromList(List<dynamic> parts) {
    return SphTimeOfDay(hour: parts[0] as int, minute: parts[1] as int);
  }

  List<int> toList() => [hour, minute];

  @override
  int compareTo(SphTimeOfDay other) {
    final h = hour.compareTo(other.hour);
    if (h != 0) return h;
    return minute.compareTo(other.minute);
  }

  /// Minutes from this time until [other] (can be negative).
  int differenceInMinutes(SphTimeOfDay other) {
    return (other.hour - hour) * 60 + other.minute - minute;
  }

  bool operator <=(SphTimeOfDay other) =>
      hour < other.hour || (hour == other.hour && minute <= other.minute);

  bool operator >=(SphTimeOfDay other) =>
      hour > other.hour || (hour == other.hour && minute >= other.minute);

  bool operator <(SphTimeOfDay other) =>
      hour < other.hour || (hour == other.hour && minute < other.minute);

  bool operator >(SphTimeOfDay other) =>
      hour > other.hour || (hour == other.hour && minute > other.minute);

  @override
  bool operator ==(Object other) =>
      other is SphTimeOfDay && hour == other.hour && minute == other.minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
