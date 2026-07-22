import 'dart:async';

import 'package:dio/dio.dart';

enum ConnectionStatus { connected, disconnected }

/// Probes SPH reachability and tracks session Dio outcomes.
class ConnectionChecker {
  ConnectionStatus _status = ConnectionStatus.disconnected;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  late final Dio dio;
  DateTime lastRequest = DateTime.now().subtract(const Duration(seconds: 5));

  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  ConnectionChecker({HttpClientAdapter? httpAdapter}) {
    dio = Dio(BaseOptions(validateStatus: (status) => status != null));
    if (httpAdapter != null) {
      dio.httpClientAdapter = httpAdapter;
    }
    unawaited(testConnection());
  }

  set status(ConnectionStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
    lastRequest = DateTime.now();
  }

  ConnectionStatus get status => _status;

  Future<bool> get connected async {
    if (DateTime.now().difference(lastRequest) > const Duration(seconds: 1)) {
      await testConnection();
    }
    return _status == ConnectionStatus.connected;
  }

  Future<bool> testConnection() async {
    try {
      await dio.post('https://start.schulportal.hessen.de/ajax_login.php');
      status = ConnectionStatus.connected;
      return true;
    } catch (_) {
      status = ConnectionStatus.disconnected;
      return false;
    }
  }

  void dispose() {
    _statusController.close();
    dio.close(force: true);
  }
}
