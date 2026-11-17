import 'package:dio/dio.dart';

import '../api_client.dart';
import '../paged_records.dart';
import '../resident_models.dart';
import '../../services/pending_submissions.dart';
import '../input_validation.dart';
import '../hospital.dart';

class DriverApi {
  DriverApi([Dio? client]) : _client = client ?? dio;

  final Dio _client;
  final CancelToken _requests = CancelToken();
  void dispose() => _requests.cancel();

  Future<Map<String, dynamic>> updateTeamRole(int teamId, String role) async {
    final response = await _client.patch(
      '/driver-responder/teams/$teamId/role',
      data: {'role': role},
      cancelToken: _requests,
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid team role response.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> switchTeamVehicle(
    int teamId,
    int vehicleId,
  ) async {
    final response = await _client.patch(
      '/driver-responder/teams/$teamId/vehicle',
      data: {'vehicle_id': vehicleId},
      cancelToken: _requests,
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid team vehicle response.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<RecordPage> fetchMaintenanceReportsPage({int? before}) async {
    final response = await _client.get(
      '/driver-responder/maintenance-reports',
      queryParameters: {'before': ?before},
      cancelToken: _requests,
    );
    final page = RecordPage.fromJson(response.data);
    if (before != null &&
        page.nextBefore != null &&
        page.nextBefore! >= before) {
      throw const FormatException('Invalid page cursor from the server.');
    }
    return page;
  }

  Future<Map<String, dynamic>> submitMaintenanceReport(
    Map<String, dynamic> report,
  ) async {
    final data = await PendingSubmissions.send(
      _client,
      '/driver-responder/maintenance-reports',
      report,
      validate: (data) {
        if (data['report'] is! Map) {
          throw const FormatException('Invalid maintenance report response.');
        }
      },
      cancelToken: _requests,
    );
    return Map<String, dynamic>.from(data['report'] as Map);
  }

  Future<Map<String, dynamic>> fetchBootstrap() async {
    final response = await _client.get(
      '/driver-responder/bootstrap',
      cancelToken: _requests,
    );
    final data = response.data;
    if (data is! Map) {
      throw const FormatException('Invalid driver data from the server.');
    }

    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> fetchHistory() async {
    final response = await _client.get(
      '/driver-responder/history',
      cancelToken: _requests,
    );
    return _items(response.data);
  }

  Future<List<Map<String, dynamic>>> fetchIncidentTypes() async {
    final response = await _client.get(
      '/driver-responder/incident-types',
      cancelToken: _requests,
    );
    return _items(response.data);
  }

  Future<List<HospitalRecommendation>> fetchHospitals(int reportId) async {
    final response = await _client.get(
      '/driver-responder/assignments/$reportId/hospitals',
      cancelToken: _requests,
    );
    return _items(response.data).map(HospitalRecommendation.fromJson).toList();
  }

  Future<
    ({
      Map<String, dynamic>? assignment,
      List<HospitalRecommendation> hospitals,
    })
  >
  markHospitalUnavailable(int reportId, int hospitalId) async {
    final response = await _client.post(
      '/driver-responder/assignments/$reportId/hospitals/$hospitalId/unavailable',
      cancelToken: _requests,
    );
    final data = response.data;
    if (data is! Map) {
      throw const FormatException('Invalid hospital update response.');
    }
    final assignment = data['assignment'];
    final hospitals = _items(
      data,
    ).map(HospitalRecommendation.fromJson).toList();
    return (
      assignment: assignment is Map
          ? Map<String, dynamic>.from(assignment)
          : null,
      hospitals: hospitals,
    );
  }

  Future<Map<String, dynamic>?> updateAssignmentStatus(
    int reportId,
    String status,
  ) => updateAssignmentStage(reportId, status);

  Future<Map<String, dynamic>?> updateAssignmentStage(
    int reportId,
    String status, {
    int? hospitalId,
    String? destination,
  }) async {
    final response = await _client.patch(
      '/driver-responder/assignments/$reportId/status',
      data: {
        'response_status': status,
        'hospital_id': ?hospitalId,
        'destination': ?destination,
      },
      cancelToken: _requests,
    );
    final data = response.data;
    if (data is! Map) {
      throw const FormatException(
        'Invalid assignment response from the server.',
      );
    }
    if (!data.containsKey('assignment') ||
        data['assignment'] != null && data['assignment'] is! Map) {
      throw const FormatException(
        'Invalid assignment response from the server.',
      );
    }
    final assignment = data['assignment'];
    return assignment is Map ? Map<String, dynamic>.from(assignment) : null;
  }

  Future<String> updateAvailability(String status, {int? vehicleId}) async {
    final response = await _client.patch(
      '/driver-responder/availability',
      data: {'vehicle_status': status, 'vehicle_id': ?vehicleId},
      cancelToken: _requests,
    );
    final data = response.data;
    if (data is! Map || data['vehicle_status'] is! String) {
      throw const FormatException('Invalid vehicle status from the server.');
    }

    return data['vehicle_status'] as String;
  }

  Future<Map<String, dynamic>> updateProfile({
    required String name,
    int? vehicleId,
    required String contact,
    required String vehicleType,
    required String vehicleNumber,
  }) async {
    final response = await _client.put(
      '/driver-responder/profile',
      data: {
        'name': InputValidation.normalizeName(name),
        'contact': InputValidation.normalizePhone(contact),
      },
      cancelToken: _requests,
    );
    final data = response.data;
    if (data is! Map || data['profile'] is! Map) {
      throw const FormatException('Invalid profile response from the server.');
    }

    return Map<String, dynamic>.from(data['profile'] as Map);
  }

  Future<Map<String, dynamic>> submitReport(Map<String, dynamic> report) async {
    final data = await PendingSubmissions.send(
      _client,
      '/driver-responder/reports',
      report,
      validate: (data) {
        ReportRecord.fromJson(Map<String, dynamic>.from(data['report'] as Map));
      },
      cancelToken: _requests,
    );
    if (data['report'] is! Map) {
      throw const FormatException('Invalid report response from the server.');
    }

    return Map<String, dynamic>.from(data['report'] as Map);
  }

  List<Map<String, dynamic>> _items(Object? value) {
    final data = value is Map ? value['data'] : value;
    if (data is! List) {
      throw const FormatException('Invalid list response from the server.');
    }

    return data.map((item) {
      if (item is! Map) {
        throw const FormatException('Invalid item in server response.');
      }
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  Future<RecordPage> fetchHistoryPage({int? before}) async {
    final response = await _client.get(
      '/driver-responder/history',
      queryParameters: {'before': ?before},
      cancelToken: _requests,
    );
    final page = RecordPage.fromJson(response.data);
    if (before != null &&
        page.nextBefore != null &&
        page.nextBefore! >= before) {
      throw const FormatException('Invalid page cursor from the server.');
    }
    return page;
  }

  Future<RecordPage> fetchServiceSchedulesPage({
    int? before,
    bool today = false,
    bool active = false,
  }) async {
    final response = await _client.get(
      '/driver-responder/schedules',
      queryParameters: {
        'before': ?before,
        if (today) 'today': 1,
        if (active) 'active': 1,
      },
      cancelToken: _requests,
    );
    final page = RecordPage.fromJson(response.data);
    if (before != null &&
        page.nextBefore != null &&
        page.nextBefore! >= before) {
      throw const FormatException('Invalid page cursor from the server.');
    }
    return page;
  }

  Future<void> completeServiceSchedule(int scheduleId) async {
    final response = await _client.patch(
      '/driver-responder/schedules/$scheduleId/complete',
      cancelToken: _requests,
    );
    if (response.data is! Map || response.data['status'] != 'completed') {
      throw const FormatException(
        'Invalid service completion response from the server.',
      );
    }
  }

  Future<Map<String, dynamic>> fetchReportForm(int reportId) async {
    final response = await _client.get(
      '/driver-responder/reports/$reportId/patient',
      cancelToken: _requests,
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid report form response from the server.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> saveDriverForm(
    int reportId, {
    required String revision,
    required Map<String, dynamic> driverSection,
  }) async {
    final response = await _client.put(
      '/driver-responder/reports/$reportId/patient',
      data: {
        'revision': revision,
        'driver_section': driverSection,
      },
      cancelToken: _requests,
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid driver form save response.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }
}
