import 'dart:async';
import 'dart:convert';

/// Keeps the last few KB of a child process's stderr so a failure can be
/// logged with context instead of draining the pipe into the void.
class ProcessTail {
  ProcessTail(Stream<List<int>> stream, {this.limit = 4096}) {
    _done = stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (chunk) {
            _text += chunk;
            if (_text.length > limit) {
              _text = _text.substring(_text.length - limit);
            }
          },
          onError: (Object _) {},
          cancelOnError: false,
        )
        .asFuture<void>()
        .catchError((Object _) {});
  }

  final int limit;
  String _text = '';
  late final Future<void> _done;

  String get text => _text.trim();

  /// Completes once the stream ended (bounded so a stuck pipe cannot hang).
  Future<String> settled() async {
    await _done.timeout(const Duration(milliseconds: 300), onTimeout: () {});
    return text;
  }
}
