import 'dart:async';

import 'package:dio/dio.dart';
import 'package:kache/kache.dart';

Future<T> withDioCancellation<T>(
  KacheFetchContext context,
  Future<T> Function(CancelToken token) request,
) async {
  final token = CancelToken();
  unawaited(context.cancellation.whenCancelled.then(token.cancel));

  try {
    final value = await request(token);
    context.throwIfCancelled();
    return value;
  } on DioException catch (error) {
    if (CancelToken.isCancel(error) && context.isCancelled) {
      context.throwIfCancelled();
    }
    rethrow;
  }
}
