class RecordPage {
  const RecordPage(this.items, this.nextBefore);
  final List<Map<String, dynamic>> items;
  final int? nextBefore;
  factory RecordPage.fromJson(Object? value) {
    if (value is! Map || value['data'] is! List) {
      throw const FormatException('Invalid record page from the server.');
    }
    final next = value['next_before'];
    if (next != null && (next is! int || next <= 0)) {
      throw const FormatException('Invalid page cursor from the server.');
    }
    return RecordPage(
      (value['data'] as List).map((item) {
        if (item is! Map) {
          throw const FormatException('Invalid record from the server.');
        }
        return Map<String, dynamic>.from(item);
      }).toList(),
      next as int?,
    );
  }
}

List<T> mergeRecords<T>(
  List<T> fresh,
  List<T> previous,
  Object Function(T) id,
) {
  final seen = <Object>{};
  final records = [
    ...fresh,
    ...previous,
  ].where((record) => seen.add(id(record))).toList();
  if (records.every((record) => id(record) is int)) {
    records.sort((a, b) => (id(b) as int).compareTo(id(a) as int));
  }
  return records;
}
