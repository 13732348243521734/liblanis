import 'dart:async';
import 'dart:convert';

import 'applet_context.dart';
import 'definition.dart';

enum FetcherStatus { fetching, done, error }

enum ContentStatus { online, offline }

class ExceptionWithStackTrace {
  final Object exception;
  final StackTrace stackTrace;

  ExceptionWithStackTrace({required this.exception, required this.stackTrace});
}

class FetcherResponse<T> {
  final FetcherStatus status;
  final T? content;
  final ContentStatus contentStatus;
  final DateTime fetchedAt;
  final ExceptionWithStackTrace? error;

  FetcherResponse({
    required this.status,
    this.contentStatus = ContentStatus.online,
    required this.error,
    this.content,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();
}

class AppletResponseStream<T> extends StreamView<FetcherResponse<T>> {
  final FetcherResponse<T>? Function() _valueGetter;

  AppletResponseStream(super.stream, this._valueGetter);

  FetcherResponse<T> get value => _valueGetter()!;
}

/// Base class for SPH applet parsers (Dart-only, no Flutter).
class AppletParser<T> {
  final AppletContext ctx;
  final AppletMeta appletMeta;
  final Future<bool> Function() isConnected;

  final StreamController<FetcherResponse<T>> _controller =
      StreamController<FetcherResponse<T>>.broadcast();
  FetcherResponse<T> _latestResponse = FetcherResponse(
    status: FetcherStatus.fetching,
    error: null,
  );
  late final AppletResponseStream<T> _stream = AppletResponseStream<T>(
    _controller.stream,
    () => _latestResponse,
  );
  bool isEmpty = true;
  Timer? _refreshTimer;

  AppletResponseStream<T> get stream => _stream;

  FetcherResponse<T>? get latestResponse => _latestResponse;

  AppletParser(
    this.ctx,
    this.appletMeta, {
    required this.isConnected,
  }) {
    _refreshTimer = Timer.periodic(appletMeta.refreshInterval, timerCallback);
  }

  void timerCallback(Timer timer) async {
    if (await isConnected()) {
      await fetchData(forceRefresh: true);
    }
  }

  void addResponse(final FetcherResponse<T> data) {
    _latestResponse = data;
    if (!_controller.isClosed) {
      _controller.add(data);
    }
  }

  void dispose() {
    _refreshTimer?.cancel();
    _controller.close();
  }

  Future<void> fetchData({
    bool forceRefresh = false,
    bool secondTry = false,
  }) async {
    if (!(await isConnected())) {
      if (isEmpty) {
        final offlineData = ctx.database.getAppletOfflineData(
          accountId: ctx.accountId,
          appletId: appletMeta.appletPhpUrl,
        );
        if (offlineData != null) {
          addResponse(
            FetcherResponse(
              status: FetcherStatus.done,
              contentStatus: ContentStatus.offline,
              content: typeFromJson(offlineData.json),
              fetchedAt: offlineData.timestamp,
              error: null,
            ),
          );
        } else {
          addResponse(
            FetcherResponse(
              status: FetcherStatus.error,
              contentStatus: ContentStatus.offline,
              error: null,
            ),
          );
        }
      }

      return;
    }

    if (isEmpty || forceRefresh) {
      addResponse(FetcherResponse(status: FetcherStatus.fetching, error: null));

      try {
        final data = await _getHome();
        addResponse(
          FetcherResponse<T>(
            status: FetcherStatus.done,
            content: data,
            error: null,
          ),
        );
        isEmpty = false;
      } catch (ex, stack) {
        if (!secondTry) {
          await ctx.session.authenticate();
          await fetchData(forceRefresh: true, secondTry: true);
          return;
        }
        addResponse(
          FetcherResponse<T>(
            status: FetcherStatus.error,
            error: ExceptionWithStackTrace(
              exception: ex,
              stackTrace: stack,
            ),
          ),
        );
      }
    }
  }

  Future<T> _getHome() async {
    final T value = await getHome();
    if (appletMeta.allowOffline) {
      ctx.database.setAppletOfflineData(
        accountId: ctx.accountId,
        appletId: appletMeta.appletPhpUrl,
        json: jsonEncode(value),
      );
    }
    return value;
  }

  T typeFromJson(String json) {
    throw UnimplementedError('Please add the required overrides in the parser');
  }

  Future<T> getHome() {
    throw UnimplementedError();
  }
}
