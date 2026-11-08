import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/native_lyrics_view.dart';
import 'package:nekoplayer_desktop/ui/embedded_lyrics_view.dart';

final supported = Platform.isLinux || Platform.isWindows;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MethodChannel channel;
  late List<MethodCall> calls;
  late Map<String, Object?> availability;
  late Map<String, Object?> creation;

  setUp(() {
    channel = const MethodChannel('top.nekoh2o/lyrics_view');
    calls = [];
    availability = {'available': true};
    creation = {'ok': true};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'isAvailable' => availability,
            'create' => creation,
            _ => <String, Object?>{},
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpView(
    WidgetTester tester, {
    VoidCallback? onOpenInBrowser,
  }) async {
    final native = NativeLyricsView(channel: channel);
    await tester.pumpWidget(
      MaterialApp(
        home: Padding(
          padding: const EdgeInsets.fromLTRB(10, 20, 30, 40),
          child: EmbeddedLyricsView(
            native: native,
            start: () async => Uri.parse('http://127.0.0.1:4321/'),
            onOpenInBrowser: onOpenInBrowser,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('creates the view and reports its bounds', (tester) async {
    await pumpView(tester);
    final create = calls.singleWhere((call) => call.method == 'create');
    final url = Uri.parse((create.arguments as Map)['url'] as String);
    expect(url.queryParameters['embedded'], '1');
    expect(url.host, '127.0.0.1');
    final bounds = calls.lastWhere((call) => call.method == 'setBounds');
    final arguments = bounds.arguments as Map;
    expect(arguments['x'], 10);
    expect(arguments['y'], 20);
    expect(arguments['width'], 800 - 10 - 30);
    expect(arguments['height'], 600 - 20 - 40);
    expect(arguments['devicePixelRatio'], tester.view.devicePixelRatio);
    expect(calls.lastWhere((call) => call.method == 'setVisible').arguments, {
      'visible': true,
    });
    await tester.pumpWidget(const SizedBox());
    expect(calls.last.method, 'destroy');
  }, skip: !supported);

  testWidgets('hides while a dialog covers it', (tester) async {
    await pumpView(tester);
    final context = tester.element(find.byType(EmbeddedLyricsView));
    unawaited(
      showDialog<void>(context: context, builder: (_) => const AlertDialog()),
    );
    await tester.pumpAndSettle();
    expect(calls.lastWhere((call) => call.method == 'setVisible').arguments, {
      'visible': false,
    });
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(calls.lastWhere((call) => call.method == 'setVisible').arguments, {
      'visible': true,
    });
  }, skip: !supported);

  testWidgets('shows the reason and a browser action when unavailable', (
    tester,
  ) async {
    availability = {'available': false, 'reason': '缺少组件'};
    var opened = 0;
    await pumpView(tester, onOpenInBrowser: () => opened++);
    expect(find.text('缺少组件'), findsOneWidget);
    expect(calls.where((call) => call.method == 'create'), isEmpty);
    await tester.tap(find.text('在浏览器中打开'));
    expect(opened, 1);
  }, skip: !supported);

  testWidgets('creation failure falls back with the reason', (tester) async {
    creation = {'ok': false, 'reason': '无法创建内嵌网页'};
    await pumpView(tester);
    expect(find.text('无法创建内嵌网页'), findsOneWidget);
    expect(calls.where((call) => call.method == 'setBounds'), isEmpty);
  }, skip: !supported);

  testWidgets('fills a loosely constrained area once loaded', (tester) async {
    // A Row gives its children loose heights, like the full player does.
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(
              child: EmbeddedLyricsView(
                native: NativeLyricsView(channel: channel),
                start: () async => Uri.parse('http://127.0.0.1:4321/'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final bounds =
        calls.lastWhere((call) => call.method == 'setBounds').arguments as Map;
    expect(bounds['width'], 800);
    expect(bounds['height'], 600);
    await tester.pumpWidget(const SizedBox());
  }, skip: !supported);
}
