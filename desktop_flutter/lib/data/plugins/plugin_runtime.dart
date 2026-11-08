import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as paths;

import '../../diagnostics/crash_log.dart';
import '../../domain/music_plugin.dart';
import '../library_store.dart';
import 'plugin_http.dart';
import 'plugin_vm.dart';

abstract interface class PluginScriptRuntime {
  Future<Map<String, dynamic>> inspect(
    String script,
    Uri url, {
    String? format,
  });
  Future<Object?> invoke(
    MusicPluginSource source,
    String method,
    List<Object?> args,
  );
}

class NativePluginRuntime implements PluginScriptRuntime {
  NativePluginRuntime({
    this.store,
    this.libraryPath,
    Future<String> Function()? bundle,
  }) : _bundle =
           bundle ??
           (() => rootBundle.loadString('assets/music_plugins/runtime.js'));

  final LibraryStore? store;
  final String? libraryPath;
  final Future<String> Function() _bundle;
  final Map<String, Map<String, dynamic>> _storage = {};
  Future<void> _queue = Future.value();
  bool _restored = false;

  Future<T> _serialize<T>(Future<T> Function() task) {
    final next = _queue.then((_) => task());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _restore() async {
    if (_restored) return;
    final raw = await store?.read();
    if (raw != null) {
      final entries = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in entries.entries) {
        _storage[entry.key] = Map<String, dynamic>.from(entry.value as Map);
      }
    }
    _restored = true;
  }

  @override
  Future<Map<String, dynamic>> inspect(
    String script,
    Uri url, {
    String? format,
  }) => _serialize(() async {
    final result = await _run(
      script,
      {'format': format, 'os': Platform.operatingSystem},
      null,
      const [],
    );
    return Map<String, dynamic>.from(result['value'] as Map);
  });

  @override
  Future<Object?> invoke(
    MusicPluginSource source,
    String method,
    List<Object?> args,
  ) => _serialize(() async {
    await _restore();
    final result = await _run(
      source.script,
      {
        'format': source.format,
        'name': source.name,
        'os': Platform.operatingSystem,
        'variables': source.variables,
        'storage': _storage[source.id] ?? {},
      },
      method,
      args,
    );
    final next = {
      ..._storage,
      source.id: Map<String, dynamic>.from(result['storage'] as Map? ?? {}),
    };
    await store?.write(jsonEncode(next));
    _storage
      ..clear()
      ..addAll(next);
    return result['value'];
  });

  Future<Map<String, dynamic>> _run(
    String script,
    Map<String, dynamic> options,
    String? method,
    List<Object?> args,
  ) async {
    final runtime = await _bundle();
    final executable = paths.dirname(Platform.resolvedExecutable);
    final library =
        libraryPath ??
        paths.join(
          executable,
          Platform.isWindows
              ? 'nekoplayer_plugins.dll'
              : 'lib/libnekoplayer_plugins.so',
        );
    try {
      return await Isolate.run(
        () => executePlugin(library, runtime, script, options, method, args),
      );
    } catch (failure, stack) {
      CrashLog.error(
        'plugin',
        'Plugin ${options['name'] ?? '(inspect)'} ${method ?? 'load'} failed',
        error: failure,
        stack: stack,
      );
      rethrow;
    }
  }
}

Future<Map<String, dynamic>> executePlugin(
  String library,
  String runtime,
  String script,
  Map<String, dynamic> options,
  String? method,
  List<Object?> args,
) async {
  final clock = Stopwatch()..start();
  final vm = PluginVm(library);
  try {
    vm.evaluate(runtime);
    vm.evaluate(
      'NekoPlugin.load(${jsonEncode(script)},${jsonEncode(options)});',
    );
    Future<Map<String, dynamic>> finish() async {
      var requestCount = 0;
      final active = <int, Future<Map<String, dynamic>>>{};
      while (clock.elapsed < const Duration(seconds: 25)) {
        final state =
            jsonDecode(vm.evaluate('NekoPlugin.take()'))
                as Map<String, dynamic>;
        if (state['state'] == 'error') {
          throw FormatException('${state['error']}');
        }
        if (state['state'] == 'done') return state;
        final requests = (state['requests'] as List)
            .cast<Map<String, dynamic>>();
        if (requests.isEmpty && active.isEmpty) {
          throw const FormatException('音源脚本未完成操作，且未发起可处理的请求。');
        }
        if ((requestCount += requests.length) > 64) {
          throw const FormatException('音源脚本请求次数过多。');
        }
        for (final request in requests) {
          final id = (request['id'] as num).toInt();
          active[id] = (() async {
            Object? value;
            var success = true;
            try {
              final payload = request['payload'] as Map<String, dynamic>;
              final remaining = const Duration(seconds: 25) - clock.elapsed;
              if (remaining <= Duration.zero) throw TimeoutException('插件执行超时。');
              value = await (switch (request['kind']) {
                'http' => sendPluginHttp(payload),
                'delay' => Future<Object?>.delayed(
                  Duration(
                    milliseconds: (payload['milliseconds'] as num)
                        .toInt()
                        .clamp(0, 15000),
                  ),
                  () => null,
                ),
                _ => throw const FormatException('插件发起了不支持的宿主调用。'),
              }).timeout(remaining);
            } catch (error) {
              success = false;
              value = error is FormatException ? error.message : '插件网络请求失败或超时。';
            }
            return <String, dynamic>{
              'id': id,
              'success': success,
              'value': value,
            };
          })();
        }
        final reply = await Future.any(active.values);
        active.remove(reply['id']);
        vm.evaluate(
          'NekoPlugin.deliver(${reply['id']},${reply['success']},${jsonEncode(reply['value'])});',
        );
      }
      throw TimeoutException('音源脚本执行超时。');
    }

    final metadata = await finish();
    if (method == null) return metadata;
    vm.evaluate(
      'NekoPlugin.invoke(${jsonEncode(method)},${jsonEncode(args)});',
    );
    return await finish();
  } finally {
    vm.close();
  }
}
