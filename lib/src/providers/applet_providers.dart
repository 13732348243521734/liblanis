import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../applets/applet_context.dart';
import '../applets/applet_parser.dart';
import '../applets/calendar/parser.dart';
import '../applets/conversations/parser.dart';
import '../applets/data_storage/parser.dart';
import '../applets/lessons/student_parser.dart';
import '../applets/lessons/teacher_parser.dart';
import '../applets/study_groups/parser.dart';
import '../applets/substitutions/parser.dart';
import '../applets/timetable/parser.dart';
import '../exceptions.dart';
import '../models/account_types.dart';
import '../models/calendar_event.dart';
import '../models/conversations.dart';
import '../models/datastorage.dart';
import '../models/lessons.dart';
import '../models/lessons_teacher.dart';
import '../models/study_groups.dart';
import '../models/substitution.dart';
import '../models/timetable.dart';
import '../settings/typed_settings.dart';
import 'core_providers.dart';

part 'applet_providers.g.dart';

@Riverpod(keepAlive: true)
AppletContext appletContext(Ref ref) {
  final account = ref.watch(activeAccountProvider);
  final sessionAsync = ref.watch(sessionProvider);
  final session = sessionAsync.asData?.value;
  if (account == null || session == null) {
    throw ConfigurationException(
      'AppletContext requires an active authenticated session',
    );
  }
  final db = ref.watch(lanisDatabaseProvider);
  return AppletContext(
    session: session,
    database: db,
    account: account,
    accountSettings: TypedSettings.account(db, account.localId),
  );
}

Future<bool> _connected(Ref ref) =>
    ref.read(connectionCheckerProvider).connected;

@Riverpod(keepAlive: true)
SubstitutionsParser substitutionsParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = SubstitutionsParser(
    ctx,
    isConnected: () => _connected(ref),
  );
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
TimetableStudentParser timetableParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = TimetableStudentParser(
    ctx,
    isConnected: () => _connected(ref),
  );
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
CalendarParser calendarParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = CalendarParser(ctx, isConnected: () => _connected(ref));
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
ConversationsParser conversationsParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = ConversationsParser(ctx, isConnected: () => _connected(ref));
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
LessonsStudentParser lessonsStudentParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = LessonsStudentParser(ctx, isConnected: () => _connected(ref));
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
LessonsTeacherParser lessonsTeacherParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = LessonsTeacherParser(ctx, isConnected: () => _connected(ref));
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
DataStorageParser dataStorageParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = DataStorageParser(ctx, isConnected: () => _connected(ref));
  ref.onDispose(parser.dispose);
  return parser;
}

@Riverpod(keepAlive: true)
StudyGroupsStudentParser studyGroupsParser(Ref ref) {
  final ctx = ref.watch(appletContextProvider);
  final parser = StudyGroupsStudentParser(
    ctx,
    isConnected: () => _connected(ref),
  );
  ref.onDispose(parser.dispose);
  return parser;
}

/// Convenience: fetch substitution plan (online or offline cache).
@riverpod
Future<FetcherResponse<SubstitutionPlan>> substitutions(Ref ref) async {
  final parser = ref.watch(substitutionsParserProvider);
  await parser.fetchData(forceRefresh: true);
  return parser.latestResponse!;
}

@riverpod
Future<FetcherResponse<TimeTable>> timetable(Ref ref) async {
  final parser = ref.watch(timetableParserProvider);
  await parser.fetchData(forceRefresh: true);
  return parser.latestResponse!;
}

@riverpod
Future<FetcherResponse<List<CalendarEvent>>> calendar(Ref ref) async {
  final parser = ref.watch(calendarParserProvider);
  await parser.fetchData(forceRefresh: true);
  return parser.latestResponse!;
}

@riverpod
Future<FetcherResponse<List<OverviewEntry>>> conversations(Ref ref) async {
  final parser = ref.watch(conversationsParserProvider);
  await parser.fetchData(forceRefresh: true);
  return parser.latestResponse!;
}

@riverpod
Future<FetcherResponse<Lessons>> lessonsStudent(Ref ref) async {
  final account = ref.watch(activeAccountProvider);
  if (account?.accountType == AccountType.teacher) {
    throw NotSupportedException('Use lessonsTeacher for teacher accounts');
  }
  final parser = ref.watch(lessonsStudentParserProvider);
  await parser.fetchData(forceRefresh: true);
  return parser.latestResponse!;
}

@riverpod
Future<FetcherResponse<LessonsTeacherHome>> lessonsTeacher(Ref ref) async {
  final parser = ref.watch(lessonsTeacherParserProvider);
  await parser.fetchData(forceRefresh: true);
  return parser.latestResponse!;
}

@riverpod
Future<FetcherResponse<(List<FileNode>, List<FolderNode>)>> dataStorage(
  Ref ref,
) async {
  final parser = ref.watch(dataStorageParserProvider);
  await parser.fetchData(forceRefresh: true);
  return parser.latestResponse!;
}

@riverpod
Future<FetcherResponse<StudentStudyGroups>> studyGroups(Ref ref) async {
  final parser = ref.watch(studyGroupsParserProvider);
  await parser.fetchData(forceRefresh: true);
  return parser.latestResponse!;
}
