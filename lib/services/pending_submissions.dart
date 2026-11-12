import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_service.dart';

String newSubmissionKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class PendingSubmission {
  const PendingSubmission(
    this.key,
    this.path,
    this.payload, {
    this.storageKey,
    this.createdAt,
  });

  final String key;
  final String? storageKey;
  final String path;
  final Map<String, dynamic> payload;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
    'key': key,
    'path': path,
    'payload': payload,
    if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
  };

  factory PendingSubmission.fromJson(
    Map<String, dynamic> value, {
    String? storageKey,
  }) {
    if (!PendingSubmissions.allowedPaths.contains(value['path']) ||
        value['key'] is! String ||
        value['payload'] is! Map) {
      throw const FormatException('Invalid saved submission.');
    }
    final rawCreated = value['created_at']?.toString();
    return PendingSubmission(
      value['key'] as String,
      value['path'] as String,
      Map<String, dynamic>.from(value['payload'] as Map),
      storageKey: storageKey,
      createdAt: rawCreated == null ? null : DateTime.tryParse(rawCreated),
    );
  }

  String get label =>
      path.endsWith('/schedules') ? 'Schedule request' : 'Incident report';

  String get location =>
      payload['location']?.toString() ??
      payload['address']?.toString() ??
      payload['pickup']?.toString() ??
      '';

  String? get summary {
    final parts = <String>[
      if (payload['service_type'] != null) '${payload['service_type']}',
      if (payload['preferred_date'] != null)
        '${payload['preferred_date']} ${payload['preferred_time'] ?? ''}'.trim(),
      if (payload['description'] != null) '${payload['description']}',
      if (payload['symptoms'] != null) '${payload['symptoms']}',
      if (payload['notes'] != null && '${payload['notes']}'.trim().isNotEmpty)
        '${payload['notes']}',
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class PendingSubmissions {
  static const allowedPaths = {
    '/resident/reports',
    '/resident/schedules',
    '/driver-responder/reports',
  };
  static const _storage = FlutterSecureStorage();
  static final changes = ValueNotifier<int>(0);
  static Future<void> _lock = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() work) {
    final result = _lock.then((_) => work());
    _lock = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Future<String> _storageKey() async {
    final auth = AuthService();
    return 'pending_submissions_${base64Url.encode(utf8.encode('${auth.apiUrl}|${await auth.accountKey()}'))}';
  }

  static Future<List<PendingSubmission>> read({String? storageKey}) async {
    storageKey ??= await _storageKey();
    final stored = await _storage.read(key: storageKey);
    if (stored == null) return [];
    final decoded = jsonDecode(stored);
    if (decoded is! List) {
      throw const FormatException('Saved submissions could not be read.');
    }
    return decoded
        .map(
          (item) => PendingSubmission.fromJson(
            Map<String, dynamic>.from(item as Map),
            storageKey: storageKey,
          ),
        )
        .toList();
  }

  static Future<void> _save(
    List<PendingSubmission> records,
    String storageKey,
  ) async {
    await _storage.write(
      key: storageKey,
      value: jsonEncode(records.map((item) => item.toJson()).toList()),
    );
    changes.value++;
  }

  static Future<PendingSubmission> prepare(
    String path,
    Map<String, dynamic> payload,
  ) => _serialized(() async {
    if (!allowedPaths.contains(path)) {
      throw ArgumentError('Unsupported submission type.');
    }
    final scope = await _storageKey();
    final records = await read(storageKey: scope);
    final matches = records.where((item) => item.path == path);
    if (matches.isNotEmpty) {
      final record = matches.first;
      if (jsonEncode(record.payload) != jsonEncode(payload)) {
        throw StateError(
          'An earlier ${record.label.toLowerCase()} still needs confirmation. Use Pending submissions before sending different details.',
        );
      }
      return record;
    }
    final record = PendingSubmission(
      newSubmissionKey(),
      path,
      payload,
      storageKey: scope,
      createdAt: DateTime.now().toUtc(),
    );
    await _save([...records, record], scope);
    return record;
  });
  static Future<void> complete(String key, {String? storageKey}) =>
      _serialized(() async {
        final scope = storageKey ?? await _storageKey();
        final records = await read(storageKey: scope);
        await _save(records.where((item) => item.key != key).toList(), scope);
      });

  static Future<Map<String, dynamic>> send(
    Dio client,
    String path,
    Map<String, dynamic> payload, {
    required void Function(Map<String, dynamic>) validate,
    CancelToken? cancelToken,
  }) async {
    final record = await prepare(path, payload);
    try {
      final response = await client.post(
        path,
        data: record.payload,
        options: Options(headers: {'Idempotency-Key': record.key}),
        cancelToken: cancelToken,
      );
      if (response.data is! Map) {
        throw const FormatException(
          'Invalid submission response. Retry the pending submission to confirm its result.',
        );
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      try {
        validate(data);
      } catch (_) {
        throw const FormatException(
          'The server returned incomplete submission data. Confirm the saved submission before sending again.',
        );
      }
      data['_submission_replayed'] =
          response.headers.value('Idempotency-Replayed') == 'true';
      await complete(record.key, storageKey: record.storageKey);
      return data;
    } on DioException catch (error) {
      // A validation rejection definitively saved nothing. Timeouts, 5xx, 401 and cancellations remain recoverable.
      if (error.response?.statusCode == 422) {
        await complete(record.key, storageKey: record.storageKey);
      }
      rethrow;
    }
  }
}
