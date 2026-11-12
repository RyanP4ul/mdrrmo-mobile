class InputValidation {
  static String normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[\s-]+'), '');
  static String normalizeName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
  static String? phone(String? value) =>
      RegExp(r'^(09\d{9}|\+639\d{9})$').hasMatch(normalizePhone(value ?? ''))
      ? null
      : 'Enter a valid PH mobile number';
  static String? name(String? value) {
    final parts = normalizeName(value ?? '').split(' ');
    if (parts.length < 2 ||
        parts.first.isEmpty ||
        parts.first.runes.length > 60 ||
        parts.skip(1).join(' ').runes.length > 60) {
      return 'Enter your first and last name, each at most 60 characters';
    }
    return null;
  }

  static String? text(
    String? value,
    String label,
    int max, {
    bool required = true,
  }) {
    final text = value?.trim() ?? '';
    if (required && text.isEmpty) return '$label is required';
    return text.runes.length > max
        ? '$label must be at most $max characters'
        : null;
  }

  static String? coordinates(double latitude, double longitude) =>
      latitude.isFinite &&
          longitude.isFinite &&
          latitude >= -90 &&
          latitude <= 90 &&
          longitude >= -180 &&
          longitude <= 180
      ? null
      : 'Choose a valid map location';
  static String? scheduleTime(DateTime when) {
    // Service requests use Balagtas civil time, independently of the device timezone.
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final civilNow = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );
    return when.isAfter(civilNow) ? null : 'Choose a future date and time';
  }
}
