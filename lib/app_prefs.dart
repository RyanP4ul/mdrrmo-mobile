import 'package:shared_preferences/shared_preferences.dart';

/// Tiny wrapper over SharedPreferences for device-level preferences.
class AppPrefs {
  AppPrefs._(this.prefs);
  final SharedPreferences prefs;

  static late AppPrefs instance;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accountType');
    instance = AppPrefs._(prefs);
  }
}
