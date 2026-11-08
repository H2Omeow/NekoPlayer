final _urlQuery = RegExp(
  r'''(\b[a-z][a-z0-9+.-]*://[^\s?#"'<>]*)\?[^\s"'<>]*''',
  caseSensitive: false,
);
final _headerLine = RegExp(
  r'''((?:proxy-)?authorization|set-cookie|cookie)(["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\r\n]*)''',
  caseSensitive: false,
);
final _secretField = RegExp(
  r'''(["']?[\w.-]*(?:token|secret|passw(?:or)?d|api[_-]?key|music_u|sessionid|session_id|credential)[\w.-]*["']?)(\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&}\]]+)''',
  caseSensitive: false,
);
final _bearer = RegExp(r'\bBearer\s+[\w.~+/=-]+', caseSensitive: false);

/// Removes credentials from text before it reaches a log file.
String redactSecrets(String text) => text
    .replaceAllMapped(_urlQuery, (m) => '${m[1]}?<redacted>')
    .replaceAllMapped(_headerLine, (m) => '${m[1]}${m[2]}<redacted>')
    .replaceAllMapped(_secretField, (m) => '${m[1]}${m[2]}<redacted>')
    .replaceAll(_bearer, 'Bearer <redacted>');
