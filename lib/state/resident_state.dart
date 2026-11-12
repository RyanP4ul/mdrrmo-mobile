import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:latlong2/latlong.dart';

import '../data/api/resident_service.api.dart';
import '../data/resident_models.dart';
import '../data/paged_records.dart';
import '../data/input_validation.dart';

import 'package:dio/dio.dart' show DioException, CancelToken;

class ResidentState extends ChangeNotifier {
  ResidentState(this.profile, {ResidentApi? api})
    : _api = api ?? ResidentApi() {
    unawaited(load());
  }

  final ResidentApi _api;
  ResidentProfile profile;
  List<IncidentType> incidentTypes = [];
  List<RecentIncident> recent = [];
  List<ReportRecord> reports = [];
  List<ResidentNotification> notifications = [];
  List<ScheduleRequest> schedules = [];
  Map<IncidentType, int> _incidentTypeIds = {};

  bool isLoading = true;
  Object? loadError;
  int _pendingWrites = 0;
  bool _isDisposed = false;
  bool _loading = false;
  bool hasLoaded = false;
  int? _unreadTotal;
  bool isUpdatingNotifications = false;
  final Map<String, int?> _cursors = {};
  final Set<String> _expanded = {};
  String? loadingPage;
  final Map<String, Object> pageErrors = {};
  bool hasMore(String resource) => _cursors[resource] != null;

  bool get isSaving => _pendingWrites > 0;
  int get unreadCount =>
      _unreadTotal ??
      notifications.where((notification) => notification.unread).length;

  Future<void> load() async {
    if (_loading || isSaving || _isDisposed) return;
    _loading = true;
    isLoading = true;
    loadError = null;
    _notify();

    try {
      final data = await _api.fetchBootstrap();
      if (_isDisposed) return;
      final nextProfile = ResidentProfile.fromJson(
        _requiredMap(data['profile'], 'profile'),
      );
      final nextTypes = _parseIncidentTypes(data['incident_types']);
      final nextReports = _parseList(data['reports'], ReportRecord.fromJson);
      final nextNotifications = _parseList(
        data['notifications'],
        ResidentNotification.fromJson,
      );
      final nextSchedules = _parseList(
        data['schedules'],
        ScheduleRequest.fromJson,
      );
      final overlaps = {
        'reports': nextReports.any(
          (item) => reports.any((old) => old.id == item.id),
        ),
        'schedules': nextSchedules.any(
          (item) => schedules.any((old) => old.id == item.id),
        ),
        'notifications': nextNotifications.any(
          (item) => notifications.any((old) => old.id == item.id),
        ),
      };
      final paging = data['paging'];
      final nextCursors = <String, int?>{};
      for (final resource in ['reports', 'schedules', 'notifications']) {
        final cursor = paging is Map ? paging[resource] : null;
        if (cursor != null && (cursor is! int || cursor <= 0)) {
          throw const FormatException('Invalid page cursor.');
        }
        nextCursors[resource] = cursor as int?;
      }
      final unread = data['unread_count'];
      if (unread != null && (unread is! int || unread < 0)) {
        throw const FormatException('Invalid unread count.');
      }
      profile = nextProfile;
      _incidentTypeIds = nextTypes;
      incidentTypes = nextTypes.keys.toList();
      reports = hasLoaded
          ? mergeRecords(nextReports, reports, (item) => item.id)
          : nextReports;
      notifications = hasLoaded
          ? mergeRecords(nextNotifications, notifications, (item) => item.id)
          : nextNotifications;
      schedules = hasLoaded
          ? mergeRecords(nextSchedules, schedules, (item) => item.id)
          : nextSchedules;
      for (final resource in nextCursors.keys) {
        if (!_expanded.contains(resource) || overlaps[resource] != true) {
          _cursors[resource] = nextCursors[resource];
          _expanded.remove(resource);
        }
      }
      _unreadTotal = data['unread_count'] as int?;
      hasLoaded = true;
      recent = reports
          .take(5)
          .map(
            (report) => RecentIncident(
              report.type,
              report.location,
              report.status,
              report.time,
            ),
          )
          .toList();
    } catch (error) {
      if (_isDisposed || error is DioException && CancelToken.isCancel(error)) {
        return;
      }
      loadError = error;
    } finally {
      _loading = false;
      isLoading = false;
      _notify();
    }
  }

  Future<ReportRecord> submitReport({
    required IncidentType type,
    required ReporterType reporter,
    required String location,
    required LatLng pin,
    required String notes,
  }) async {
    _checkCanSubmit();
    final validation =
        InputValidation.text(location, 'Location', 255) ??
        InputValidation.text(notes, 'Details', 2000) ??
        InputValidation.coordinates(pin.latitude, pin.longitude);
    if (validation != null) throw ArgumentError(validation);
    final incidentTypeId = _incidentTypeIds[type];
    if (incidentTypeId == null) {
      throw StateError('This incident type is not available on the server.');
    }

    var refreshAfterReplay = false;
    _pendingWrites++;
    _notify();
    try {
      final response = await _api.submitReport(
        incidentTypeId: incidentTypeId,
        reporterType: reporter.name,
        location: location,
        latitude: pin.latitude,
        longitude: pin.longitude,
        description: notes,
      );
      if (_isDisposed) throw StateError('This session has closed.');
      final report = ReportRecord.fromJson(
        _requiredMap(response['report'], 'report'),
      );
      if (response['_submission_replayed'] == true) {
        refreshAfterReplay = true;
        return report;
      }
      reports.removeWhere((item) => item.id == report.id);
      reports.insert(0, report);
      recent.insert(
        0,
        RecentIncident(
          report.type,
          report.location,
          report.status,
          report.time,
        ),
      );
      if (response['notification'] is Map) {
        if (_unreadTotal != null) _unreadTotal = _unreadTotal! + 1;
        notifications.insert(
          0,
          ResidentNotification.fromJson(
            _requiredMap(response['notification'], 'notification'),
          ),
        );
      }
      _notify();
      return report;
    } finally {
      _pendingWrites--;
      _notify();
      if (refreshAfterReplay && !_isDisposed) await load();
    }
  }

  Future<void> submitSchedule({
    required SchedulePurpose purpose,
    required String address,
    required DateTime when,
    String notes = '',
  }) async {
    _checkCanSubmit();
    final validation =
        InputValidation.text(address, 'Service address', 255) ??
        InputValidation.text(notes, 'Notes', 1000, required: false) ??
        InputValidation.scheduleTime(when);
    if (validation != null) throw ArgumentError(validation);
    var refreshAfterReplay = false;
    _pendingWrites++;
    _notify();
    try {
      final response = await _api.submitSchedule(
        serviceType: purpose.label,
        date: when,
        time: _timeLabel(when),
        address: address,
        notes: notes,
      );
      if (_isDisposed) return;
      final schedule = ScheduleRequest.fromJson(
        _requiredMap(response['schedule'], 'schedule'),
      );
      if (response['_submission_replayed'] == true) {
        refreshAfterReplay = true;
        return;
      }
      schedules.removeWhere((item) => item.id == schedule.id);
      schedules.insert(0, schedule);
      if (response['notification'] is Map) {
        if (_unreadTotal != null) _unreadTotal = _unreadTotal! + 1;
        notifications.insert(
          0,
          ResidentNotification.fromJson(
            _requiredMap(response['notification'], 'notification'),
          ),
        );
      }
      _notify();
    } finally {
      _pendingWrites--;
      _notify();
      if (refreshAfterReplay && !_isDisposed) await load();
    }
  }

  Future<void> markRead(ResidentNotification notification) async {
    if (_isDisposed || !notification.unread || isSaving || _loading) return;
    isUpdatingNotifications = true;
    _pendingWrites++;
    _notify();
    try {
      await _api.markRead(notification.id);
      if (_isDisposed) return;
      notification.unread = false;
      if (_unreadTotal != null && _unreadTotal! > 0) {
        _unreadTotal = _unreadTotal! - 1;
      }
    } finally {
      isUpdatingNotifications = false;
      _pendingWrites--;
      _notify();
    }
  }

  Future<void> markAllRead() async {
    if (_isDisposed || unreadCount == 0 || isSaving || _loading) return;
    isUpdatingNotifications = true;
    _pendingWrites++;
    _notify();
    try {
      await _api.markAllRead();
      if (_isDisposed) return;
      for (final notification in notifications) {
        notification.unread = false;
      }
      _unreadTotal = 0;
    } finally {
      isUpdatingNotifications = false;
      _pendingWrites--;
      _notify();
    }
  }

  Future<void> cancelSchedule(ScheduleRequest schedule) async {
    if (isSaving || _loading) {
      throw StateError('Please wait for the current request to finish.');
    }
    if (!schedule.canCancel) return;
    _pendingWrites++;
    _notify();
    try {
      final response = await _api.cancelSchedule(schedule.id);
      if (_isDisposed) return;
      final updated = ScheduleRequest.fromJson(
        _requiredMap(response['schedule'], 'schedule'),
      );
      final index = schedules.indexWhere((item) => item.id == schedule.id);
      if (index >= 0) schedules[index] = updated;
      if (response['notification'] is Map) {
        notifications.insert(
          0,
          ResidentNotification.fromJson(
            _requiredMap(response['notification'], 'notification'),
          ),
        );
        if (_unreadTotal != null) _unreadTotal = _unreadTotal! + 1;
      }
    } finally {
      _pendingWrites--;
      _notify();
    }
  }

  Future<void> loadMore(String resource) async {
    final cursor = _cursors[resource];
    if (_isDisposed || _loading || isSaving || cursor == null) return;
    loadingPage = resource;
    _pendingWrites++;
    pageErrors.remove(resource);
    _notify();
    try {
      final page = await _api.fetchPage(resource, cursor);
      if (_isDisposed) return;
      switch (resource) {
        case 'reports':
          reports = mergeRecords(
            reports,
            page.items.map(ReportRecord.fromJson).toList(),
            (item) => item.id,
          );
        case 'schedules':
          schedules = mergeRecords(
            schedules,
            page.items.map(ScheduleRequest.fromJson).toList(),
            (item) => item.id,
          );
        case 'notifications':
          notifications = mergeRecords(
            notifications,
            page.items.map(ResidentNotification.fromJson).toList(),
            (item) => item.id,
          );
        default:
          throw ArgumentError('Unknown resource');
      }
      _cursors[resource] = page.nextBefore;
      _expanded.add(resource);
    } catch (error) {
      if (!_isDisposed) pageErrors[resource] = error;
    } finally {
      loadingPage = null;
      _pendingWrites--;
      _notify();
    }
  }

  void _checkCanSubmit() {
    if (_isDisposed) throw StateError('This session has closed.');
    if (!profile.canSubmit) {
      throw StateError(
        'Your resident account must be approved before submitting requests.',
      );
    }
    if (_loading || isSaving) {
      throw StateError('Please wait for the current request to finish.');
    }
  }

  Map<IncidentType, int> _parseIncidentTypes(Object? value) {
    if (value is! List) {
      throw const FormatException(
        'Incident types are missing from the server response.',
      );
    }

    final result = <IncidentType, int>{};
    for (final item in value) {
      final json = _requiredMap(item, 'incident type');
      final type = IncidentType.fromJson(json);
      result[type] = json['id'] as int;
    }

    return result;
  }

  List<T> _parseList<T>(Object? value, T Function(Map<String, dynamic>) parse) {
    if (value is! List) {
      throw const FormatException(
        'A list is missing from the server response.',
      );
    }

    return value.map((item) => parse(_requiredMap(item, 'list item'))).toList();
  }

  Map<String, dynamic> _requiredMap(Object? value, String field) {
    if (value is! Map) {
      throw FormatException('Invalid $field in the server response.');
    }

    return Map<String, dynamic>.from(value);
  }

  String _timeLabel(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _api.dispose();
    super.dispose();
  }
}

class ResidentScope extends InheritedNotifier<ResidentState> {
  const ResidentScope({
    super.key,
    required ResidentState state,
    required super.child,
  }) : super(notifier: state);

  static ResidentState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ResidentScope>()!.notifier!;
}
