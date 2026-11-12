import 'package:dio/dio.dart';

String apiErrorMessage(Object error) {
  if (error is FormatException || error is TypeError) {
    return 'The server returned unsupported or incomplete data. Refresh or contact MDRRMO.';
  }
  if (error is DioException) {
    if ((error.response?.statusCode ?? 0) >= 500) {
      return 'MDRRMO is temporarily unavailable. Refresh to check the latest status before trying again.';
    }
    final data = error.response?.data;
    if (data is Map) {
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
      if (data['message'] is String) return data['message'] as String;
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        'The request timed out. Please try again.',
      DioExceptionType.connectionError =>
        'Could not connect to MDRRMO. Check your connection and try again.',
      _ => 'Could not complete the request. Please try again.',
    };
  }
  return error.toString().replaceFirst(RegExp(r'^(Exception|Bad state): '), '');
}
