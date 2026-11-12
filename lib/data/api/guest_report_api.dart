import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../resident_models.dart';
import '../../services/pending_submissions.dart';

class GuestReportApi {
  GuestReportApi([Dio? client])
    : _client =
          client ??
          Dio(
            BaseOptions(
              baseUrl: dotenv.get(
                'API_URL',
                fallback: 'http://10.0.2.2:8000/api',
              ),
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
              headers: {'Accept': 'application/json'},
            ),
          );

  final Dio _client;
  final _requests = CancelToken();
  final _submissionKeys = <String, String>{};

  void dispose() => _requests.cancel();

  Future<Map<IncidentType, int>> fetchTypes() async {
    final response = await _client.get(
      '/guest/incident-types',
      cancelToken: _requests,
    );
    final types = response.data['incident_types'];
    if (types is! List) {
      throw const FormatException('Invalid incident categories.');
    }
    return {
      for (final type in types)
        IncidentType.fromJson(Map<String, dynamic>.from(type as Map)):
            type['id'] as int,
    };
  }

  Future<String> submitReport(Map<String, dynamic> payload) async {
    final fingerprint = jsonEncode(payload);
    final key = _submissionKeys.putIfAbsent(fingerprint, newSubmissionKey);
    final response = await _client.post(
      '/guest/reports',
      data: payload,
      options: Options(headers: {'Idempotency-Key': key}),
      cancelToken: _requests,
    );
    final reference = response.data['reference'];
    if (reference is! String || reference.isEmpty) {
      throw const FormatException(
        'The server did not confirm your report. Retry with the same details.',
      );
    }
    return reference;
  }
}
