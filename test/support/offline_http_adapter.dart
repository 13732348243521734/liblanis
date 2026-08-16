import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Fails every request immediately so unit tests never wait on SPH.
class OfflineHttpAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: 'offline test adapter',
      message: 'SPH is not contacted in unit tests',
    );
  }

  @override
  void close({bool force = false}) {}
}
