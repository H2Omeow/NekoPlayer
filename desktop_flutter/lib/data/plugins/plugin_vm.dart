import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../i18n/tr.dart';

class PluginVm {
  PluginVm(String libraryPath) : _library = DynamicLibrary.open(libraryPath) {
    _handle = _library
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'neko_plugin_create',
        )();
    if (_handle == nullptr) throw StateError(tr('音源脚本引擎初始化失败。'));
  }

  final DynamicLibrary _library;
  late final Pointer<Void> _handle;
  late final _eval = _library
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)
      >('neko_plugin_eval');
  late final _close = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('neko_plugin_close');

  String evaluate(String script) {
    final input = script.toNativeUtf8();
    try {
      final output = _eval(_handle, input);
      if (output == nullptr) throw StateError(tr('音源脚本执行失败。'));
      final envelope =
          jsonDecode(output.toDartString()) as Map<String, dynamic>;
      if (envelope['ok'] != true) throw FormatException('${envelope['error']}');
      return '${envelope['value'] ?? ''}';
    } finally {
      calloc.free(input);
    }
  }

  void close() => _close(_handle);
}
