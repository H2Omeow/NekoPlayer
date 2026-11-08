import 'app_language.dart';
import 'string_tables.g.dart';

const Map<String, Map<String, Object>> _tables = {
  'zh-TW': stringsZhTw,
  'en': stringsEn,
  'ja': stringsJa,
};

final RegExp _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

/// Looks up the normalized Simplified Chinese source template.
String tr(String source, [Map<String, Object?> params = const {}]) {
  final table = _tables[AppLanguage.currentTag];
  final value = table?[source];
  String text;
  if (value is String) {
    text = value;
  } else if (value is Map) {
    num? countValue;
    for (final param in params.values) {
      if (param is num) {
        countValue = param;
        break;
      }
    }
    final count = countValue?.toInt();
    text =
        (count == 1 ? value['one'] : value['other']) as String? ??
        value['other'] as String? ??
        value['one'] as String? ??
        source;
  } else {
    text = source;
  }
  return text.replaceAllMapped(
    _placeholder,
    (match) => params[match.group(1)]?.toString() ?? match.group(0)!,
  );
}
