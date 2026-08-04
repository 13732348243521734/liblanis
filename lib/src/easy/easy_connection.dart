import '../connection/connection_checker.dart';

/// Connection status wrapper for [EasyLanisClient].
class EasyConnection {
  final ConnectionChecker _checker;

  EasyConnection(this._checker);

  ConnectionStatus get status => _checker.status;

  Future<bool> get isConnected => _checker.connected;

  Stream<ConnectionStatus> get onStatusChanged => _checker.statusStream;
}
