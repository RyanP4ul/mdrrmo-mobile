import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../services/auth_service.dart';

final String _baseUrl = dotenv.get(
  'API_URL',
  fallback: 'http://10.0.2.2:8000/api',
);

final dio =
    Dio(
        BaseOptions(
          baseUrl: _baseUrl,
			connectTimeout: const Duration(seconds: 15),
			receiveTimeout: const Duration(seconds: 30),
			sendTimeout: const Duration(seconds: 15),
          headers: {'Accept': 'application/json'},
        ),
      )
      ..interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) async {
            if (error.response?.statusCode == 401) {
              final authorization = error
                  .requestOptions
                  .headers['Authorization']
                  ?.toString();
              try {
                await AuthService().clearSession(
                  notify: true,
                  expectedToken: authorization?.replaceFirst('Bearer ', ''),
                );
              } catch (_) {
                // Preserve the original request failure if local storage is unavailable.
              }
            }
            handler.next(error);
          },
          onRequest: (options, handler) async {
            try {
              final token = await AuthService().getToken();
              options.headers['Authorization'] = 'Bearer $token';
              handler.next(options);
            } catch (error) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  error: error,
                  message: 'Failed to retrieve authentication token.',
                ),
              );
            }
          },
        ),
      );
