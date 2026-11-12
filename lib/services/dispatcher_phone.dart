import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DispatcherPhone {
  static const _key = 'sos_dispatcher_phone';
  static final number = ValueNotifier<String>('');

  static Future<void> load() async {
    final cached = (await SharedPreferences.getInstance()).getString(_key);
    number.value = cached ?? dotenv.get('DISPATCHER_PHONE', fallback: '');
  }

  static Future<void> update(String? value) async {
    if (value == null || value.trim().isEmpty || value == number.value) return;
    number.value = value.trim();
    await (await SharedPreferences.getInstance()).setString(_key, number.value);
  }
}
