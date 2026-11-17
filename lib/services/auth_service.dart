import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import 'pending_submissions.dart' show newSubmissionKey;
import '../data/input_validation.dart';

class SessionExpiredException implements Exception {
  const SessionExpiredException();
  @override
  String toString() => 'Your session has expired. Please sign in again.';
}

class AuthService {
  AuthService({http.Client? client}) : _client = client ?? _defaultClient;
  final http.Client _client;
  static final http.Client _defaultClient = http.Client();
  static Future<void> _sessionWork = Future.value();
  static Future<T> _sessionWrite<T>(Future<T> Function() work) {
    final result = _sessionWork.then((_) => work());
    _sessionWork = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  static bool _signingIn = false;
  static Future<void>? _logoutOperation;
  static final sessionExpired = ValueNotifier<int>(0);
  final apiUrl = dotenv.get(
    'API_URL',
    fallback: 'https://mdrrmo-production.up.railway.app/api',
  );

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    if (_signingIn || _logoutOperation != null) {
      throw StateError('An account request is already in progress.');
    }
    _signingIn = true;
    try {
      return await _login(
        email: email,
        password: password,
      );
    } finally {
      _signingIn = false;
    }
  }

  Future<Map<String, dynamic>> _login({
    required String email,
    required String password,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$apiUrl/auth/mobile/login'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'email': email,
            'password': password,
            'device_name': 'MDRRMO Flutter Mobile',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode >= 500) {
      throw Exception('MDRRMO is temporarily unavailable. Please try again.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid response from the server.');
    }

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(decoded, 'Unable to sign in.'));
    }

    final token = decoded['token'];
    final user = decoded['user'];
    if (token is! String || token.isEmpty) {
      throw Exception('The server did not return an authentication token.');
    }
    if (user is! Map<String, dynamic>) {
      throw const FormatException('Invalid response from the server.');
    }

    if (!['resident', 'driver/responder'].contains(user['role'])) {
      throw Exception(
        'This mobile app is for residents and drivers/responders. Admin and dispatcher accounts use the website.',
      );
    }
    await _sessionWrite(() async {
      await _saveAccount(user);
      await _storage.write(key: _tokenKey, value: token);
    });
    return user;
  }

  Future<String> register({
    required String name,
    required String contact,
    required String address,
    required String email,
    required String password,
    required String consentVersion,
    String? idType,
    Uint8List? idPhotoBytes,
    String? idPhotoName,
    String? submissionKey,
  }) async {
    final key = submissionKey ?? newSubmissionKey();
    final uri = Uri.parse('$apiUrl/auth/mobile/register');
    final http.Response response;
    if (idPhotoBytes != null && idPhotoName != null) {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Idempotency-Key'] = key
        ..headers['Accept'] = 'application/json'
        ..fields['name'] = InputValidation.normalizeName(name)
        ..fields['contact'] = InputValidation.normalizePhone(contact)
        ..fields['address'] = address
        ..fields['email'] = email
        ..fields['password'] = password
        ..fields['password_confirmation'] = password
        ..fields['consent'] = '1'
        ..fields['consent_version'] = consentVersion;
      if (idType != null && idType.isNotEmpty) {
        request.fields['id_type'] = idType;
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          'id_photo',
          idPhotoBytes,
          filename: idPhotoName,
        ),
      );
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed);
    } else {
      response = await _client
          .post(
            uri,
            headers: {
              'Idempotency-Key': key,
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'name': InputValidation.normalizeName(name),
              'contact': InputValidation.normalizePhone(contact),
              'address': address,
              'email': email,
              'password': password,
              'password_confirmation': password,
              'consent': true,
              'consent_version': consentVersion,
              if (idType != null && idType.isNotEmpty) 'id_type': idType,
            }),
          )
          .timeout(const Duration(seconds: 15));
    }

    if (response.statusCode >= 500) {
      throw Exception('MDRRMO is temporarily unavailable. Please try again.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid response from the server.');
    }
    if (response.statusCode != 201) {
      throw Exception(_errorMessage(decoded, 'Unable to create your account.'));
    }

    return decoded['message']?.toString() ??
        'Registration submitted. Your account is waiting for review.';
  }

  Future<String> getToken() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null || token.isEmpty) {
      throw const SessionExpiredException();
    }
    return token;
  }

  Future<bool> hasToken() async =>
      (await _storage.read(key: _tokenKey))?.isNotEmpty ?? false;

  Future<void> clearSession({bool notify = false, String? expectedToken}) =>
      _sessionWrite(() async {
        if (expectedToken != null &&
            await _storage.read(key: _tokenKey) != expectedToken) {
          return;
        }
        await _storage.delete(key: _tokenKey);
        if (notify) sessionExpired.value++;
      });

  Future<Map<String, dynamic>> getMe() async {
    final token = await getToken();
    final response = await _client
        .get(
          Uri.parse('$apiUrl/auth/mobile/me'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401 || response.statusCode == 403) {
      await clearSession(expectedToken: token);
      throw const SessionExpiredException();
    }
    if (response.statusCode != 200) {
      throw Exception('Could not check your session. Please try again.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['user'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid response from the server.');
    }
    final user = decoded['user'] as Map<String, dynamic>;
    if (!['resident', 'driver/responder'].contains(user['role'])) {
      await clearSession(expectedToken: token);
      throw const SessionExpiredException();
    }
    await _sessionWrite(() async {
      if (await _storage.read(key: _tokenKey) != token) {
        throw const SessionExpiredException();
      }
      await _saveAccount(user);
    });
    return user;
  }

  Future<void> logout() {
    if (_signingIn) {
      return Future<void>.error(
        StateError(
          'Wait for the sign-in request to finish before signing out.',
        ),
      );
    }
    return _logoutOperation ??= _performLogout().whenComplete(
      () => _logoutOperation = null,
    );
  }

  Future<void> _performLogout() async {
    final token = await _storage.read(key: _tokenKey);
    try {
      if (token == null || token.isEmpty) return;
      final response = await _client
          .post(
            Uri.parse('$apiUrl/auth/mobile/logout'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (![200, 401, 403].contains(response.statusCode)) {
        throw Exception('Could not log out. Please try again.');
      }
    } catch (_) {
      // Local logout must remain available when the server is unreachable.
    } finally {
      await clearSession(expectedToken: token);
    }
  }

  static Future<void> _saveAccount(Map<String, dynamic> user) async {
    if (user['id'] is! int ||
        !['resident', 'driver/responder'].contains(user['role'])) {
      throw const FormatException('Invalid account identity from the server.');
    }
    final identity =
        user['account_key']?.toString() ?? '${user['role']}:${user['id']}';
    await _storage.write(key: 'account_key', value: identity);
  }

  Future<String> accountKey() async {
    final stored = await _storage.read(key: 'account_key');
    if (stored != null && stored.isNotEmpty) return stored;
    await getMe();
    return (await _storage.read(key: 'account_key'))!;
  }

  Future<Map<String, dynamic>> fetchPolicy() async {
    final response = await _client
        .get(
          Uri.parse('$apiUrl/auth/mobile/policy'),
          headers: {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        data is! Map<String, dynamic> ||
        data['version'] is! String ||
        data['consent'] is! String ||
        data['privacy'] is! String) {
      throw const FormatException(
        'Could not load the privacy information. Please try again.',
      );
    }
    return data;
  }

  String _errorMessage(Map<String, dynamic> decoded, String fallback) {
    final errors = decoded['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final firstError = errors.values.first;
      if (firstError is List && firstError.isNotEmpty) {
        return firstError.first.toString();
      }
    }
    return decoded['message']?.toString() ?? fallback;
  }
}
