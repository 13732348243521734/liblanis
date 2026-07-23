import '../database/database.dart';
import '../models/account.dart';
import '../session/session.dart';
import '../settings/typed_settings.dart';

/// Runtime context for applet parsers (session + account-scoped settings).
class AppletContext {
  final LanisSession session;
  final LanisDatabase database;
  final ClearTextAccount account;
  final TypedSettings accountSettings;

  AppletContext({
    required this.session,
    required this.database,
    required this.account,
    required this.accountSettings,
  });

  int get accountId => account.localId;
}
