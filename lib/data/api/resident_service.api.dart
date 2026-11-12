import 'package:dio/dio.dart';

import '../api_client.dart';
import '../paged_records.dart';
import '../resident_models.dart';
import '../../services/pending_submissions.dart';

class ResidentApi {
  ResidentApi([Dio? client]) : _client = client ?? dio;

  final Dio _client;
  final CancelToken _requests = CancelToken();
  void dispose() => _requests.cancel();

  Future<Map<String, dynamic>> fetchBootstrap() async {
    final response = await _client.get(
      '/resident/bootstrap',
      cancelToken: _requests,
    );
    final data = response.data;
    if (data is! Map) {
      throw const FormatException('Invalid resident data from the server.');
    }

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> submitReport({
    required int incidentTypeId,
    required String reporterType,
    required String location,
    required double latitude,
    required double longitude,
    required String description,
  }) async {
    final data = await PendingSubmissions.send(
      _client,
      '/resident/reports',
      {
        'incident_type_id': incidentTypeId,
        'reporter_type': reporterType,
        'location': location,
        'lat': latitude,
        'lng': longitude,
        'description': description,
      },
      validate: _validateReport,
      cancelToken: _requests,
    );
    if (data['report'] is! Map) {
      throw const FormatException('Invalid report response from the server.');
    }

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> submitSchedule({
    required String serviceType,
    required DateTime date,
    required String time,
    required String address,
    String notes = '',
  }) async {
    final data = await PendingSubmissions.send(
      _client,
      '/resident/schedules',
      {
        'service_type': serviceType,
        'preferred_date':
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'preferred_time': time,
        'address': address,
        'notes': notes,
      },
      validate: _validateSchedule,
      cancelToken: _requests,
    );
    if (data['schedule'] is! Map) {
      throw const FormatException('Invalid schedule response from the server.');
    }

    return Map<String, dynamic>.from(data);
  }

  Future<void> markRead(int id) async {
    await _client.patch(
      '/resident/notifications/$id/read',
      cancelToken: _requests,
    );
  }

  Future<Map<String, dynamic>> cancelSchedule(int id) async {
    final response = await _client.patch(
      '/resident/schedules/$id/cancel',
      cancelToken: _requests,
    );
    final data = response.data;
    if (data is! Map || data['schedule'] is! Map) {
      throw const FormatException(
        'Invalid cancellation response from the server.',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> markAllRead() async {
    await _client.patch('/resident/notifications/read', cancelToken: _requests);
  }

  Future<RecordPage> fetchPage(String resource, int before) async {
    if (!['reports', 'schedules', 'notifications'].contains(resource)) {
      throw ArgumentError('Unknown resource');
    }
    final response = await _client.get(
      '/resident/$resource',
      queryParameters: {'before': before},
      cancelToken: _requests,
    );
    final page = RecordPage.fromJson(response.data);
    if (page.nextBefore != null && page.nextBefore! >= before) {
      throw const FormatException('Invalid page cursor from the server.');
    }
    return page;
  }

  void _validateReport(Map<String, dynamic> data) {
    ReportRecord.fromJson(Map<String, dynamic>.from(data['report'] as Map));
    if (data['notification'] is Map) {
      ResidentNotification.fromJson(
        Map<String, dynamic>.from(data['notification'] as Map),
      );
    }
  }

  void _validateSchedule(Map<String, dynamic> data) {
    ScheduleRequest.fromJson(
      Map<String, dynamic>.from(data['schedule'] as Map),
    );
    if (data['notification'] is Map) {
      ResidentNotification.fromJson(
        Map<String, dynamic>.from(data['notification'] as Map),
      );
    }
  }
}
