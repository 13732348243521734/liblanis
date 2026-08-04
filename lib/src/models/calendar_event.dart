import 'package:intl/intl.dart';

class CalendarEvent {
  DateTime startTime;
  DateTime endTime;
  dynamic fremdUID;
  dynamic lerngruppe;
  bool secret;
  String id;
  String? schoolID;
  DateTime? lastModified;
  bool isNew;
  bool public;
  String? place;
  bool private;
  String? responsibleID;
  bool allDay;
  CalendarEventCategory? category;
  String description;
  String title;

  CalendarEvent({
    required this.startTime,
    required this.endTime,
    this.fremdUID,
    this.lerngruppe,
    required this.secret,
    required this.id,
    this.schoolID,
    this.lastModified,
    required this.isNew,
    required this.public,
    this.place,
    required this.private,
    this.responsibleID,
    required this.allDay,
    this.category,
    required this.description,
    required this.title,
  });

  /// ARGB color from category, or default blue.
  int get colorArgb => category?.colorArgb ?? 0xFF4242FC;

  /// Parses the response of the AJAX SPH events and returns a CalendarEvent.
  factory CalendarEvent.fromLanisJson(
    Map<String, dynamic> json,
    List<CalendarEventCategory> categories,
  ) {
    final int? categoryId = int.tryParse('${json['category']}');
    final CalendarEventCategory? parsedCategory = categories
        .where((element) => element.id == categoryId)
        .firstOrNull;

    // Prefer SPH's German fields; fall back to FullCalendar ISO `start`/`end`
    // which the same payload already includes.
    final startTime =
        _parseSphDate(json['Anfang']) ?? _parseSphDate(json['start']);
    final endTime =
        _parseSphDate(json['Ende']) ?? _parseSphDate(json['end']);
    if (startTime == null || endTime == null) {
      throw FormatException(
        'Calendar event missing parseable start/end',
        json['Id'],
      );
    }

    return CalendarEvent(
      startTime: startTime,
      endTime: endTime,
      fremdUID: json['FremdUID'],
      lerngruppe: json['Lerngruppe'],
      secret: json['Geheim'] != 'nein',
      id: '${json['Id'] ?? ''}',
      schoolID: json['Institution']?.toString(),
      lastModified: _parseSphDate(json['LetzteAenderung']),
      isNew: json['Neu'] != 'nein',
      public: json['Oeffentlich'] != 'nein',
      place: json['Ort']?.toString(),
      private: json['Privat'] != 'nein',
      responsibleID: json['Verantwortlich']?.toString(),
      allDay: json['allDay'] == true || json['allDay'] == 'true',
      category: parsedCategory,
      description: '${json['description'] ?? ''}',
      title: '${json['title'] ?? ''}',
    );
  }

  static DateTime? _parseSphDate(dynamic value) {
    if (value == null) return null;
    final raw = '$value'.trim();
    if (raw.isEmpty || raw == 'null') return null;

    final formats = <DateFormat>[
      DateFormat('yyyy-MM-dd HH:mm:ss'),
      DateFormat('dd.MM.yyyy HH:mm:ss'),
      DateFormat('dd.MM.yyyy HH:mm'),
      DateFormat('yyyy-MM-dd'),
    ];
    for (final format in formats) {
      try {
        return format.parse(raw);
      } catch (_) {}
    }

    // FullCalendar ISO timestamps, e.g. 2026-08-08T10:00:00+02:00
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }
}

class CalendarEventCategory {
  final int id;

  /// ARGB color value (no Flutter [Color]).
  final int colorArgb;
  final String name;

  CalendarEventCategory({
    required this.id,
    required this.colorArgb,
    required this.name,
  });
}
