import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/data/account_store.dart';
import 'package:nekoplayer_desktop/data/native_music_catalog.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/ui/kugou_account_page.dart';

void main() {
  late AccountStore accounts;
  late NativeMusicCatalog catalog;
  late List<CatalogRequest> requests;
  late Future<Map<String, dynamic>> Function(CatalogRequest) handler;
  setUp(() async {
    accounts = AccountStore();
    await accounts.initialize();
    await accounts.update(kugou: {'dfid': 'test-device'});
    requests = [];
    handler = (_) async => {
      'status': 1,
      'data': {'token': 'new-token', 'userid': 123},
    };
    catalog = NativeMusicCatalog(
      accounts: accounts,
      transport: (request) async {
        requests.add(request);
        return handler(request);
      },
    );
  });

  test('invalid phone or code cannot issue SMS or login requests', () async {
    await expectLater(
      catalog.sendKugouCode('123'),
      throwsA(isA<MusicSearchException>()),
    );
    await expectLater(
      catalog.loginKugouMobile('13800000000', 'no'),
      throwsA(isA<MusicSearchException>()),
    );
    expect(requests, isEmpty);
    await catalog.sendKugouCode('13800000000');
    expect(requests.single.uri.host, 'login-user.kugou.com');
    expect(requests.single.uri.path, '/v7/send_mobile_code');
    expect((jsonDecode(requests.single.body!) as Map)['mobile'], '13800000000');
  });

  test(
    'SMS login encrypts code, replaces old auth and retains device identity',
    () async {
      await accounts.update(
        kugou: {'token': 'old', 'userid': '456', 'vip_token': 'stale-vip'},
      );
      final device = accounts.kugou()['KUGOU_API_GUID'];
      await catalog.loginKugouMobile('13800000000', '123456');
      final request = requests.single;
      expect(request.uri.host, 'loginserviceretry.kugou.com');
      expect(request.headers['support-calm'], '1');
      final body = jsonDecode(request.body!) as Map;
      expect(body['mobile'], '13*****0');
      expect(body['params'], matches(r'^[a-fA-F0-9]+$'));
      expect(body['pk'], hasLength(256));
      expect(body.containsKey('code'), isFalse);
      expect(accounts.kugou()['token'], 'new-token');
      expect(accounts.kugou()['userid'], '123');
      expect(accounts.kugou()['vip_token'], isNull);
      expect(accounts.kugou()['KUGOU_API_GUID'], device);
    },
  );

  test(
    'multiple linked accounts are explicit and cancellation never stores auth',
    () async {
      handler = (_) async => {
        'status': 1,
        'data': {
          'accounts': [
            {'userid': 1, 'nickname': 'one'},
            {'userid': 2, 'nickname': 'two'},
          ],
        },
      };
      await expectLater(
        catalog.loginKugouMobile('13800000000', '123456'),
        throwsA(
          isA<KugouAccountSelection>().having(
            (failure) => failure.accounts.length,
            'choices',
            2,
          ),
        ),
      );
      expect(accounts.kugouLoggedIn(), isFalse);
      handler = (_) async => {
        'status': 1,
        'data': {'token': 'valid', 'userid': 1},
      };
      await expectLater(
        catalog.loginKugouMobile(
          '13800000000',
          '123456',
          userId: '1',
          accept: () => false,
        ),
        throwsA(isA<MusicSearchException>()),
      );
      expect(accounts.kugouLoggedIn(), isFalse);
    },
  );

  test(
    'token refresh validates returned account and handles lite session independently',
    () async {
      await accounts.update(
        kugou: {'token': 'lite-old', 'userid': '123', 'dfid': 'lite-device'},
        platform: 1,
      );
      handler = (_) async => {
        'status': 1,
        'data': {'token': 'wrong', 'userid': 456},
      };
      await expectLater(
        catalog.refreshKugouToken(),
        throwsA(isA<MusicSearchException>()),
      );
      expect(accounts.kugou()['token'], 'lite-old');
      handler = (_) async => {
        'status': 1,
        'data': {'token': 'refreshed', 'userid': 123},
      };
      await catalog.refreshKugouToken();
      final body = jsonDecode(requests.last.body!) as Map;
      expect(requests.last.uri.path, '/v5/login_by_token');
      expect(body['p3'], isNotEmpty);
      expect(body['t1'], isA<String>());
      expect(body['t2'], isA<String>());
      expect(body['gitversion'], '5f0b7c4');
      expect(accounts.kugou(0)['token'], isNull);
      expect(accounts.kugou(1)['token'], 'refreshed');
    },
  );

  test(
    'VIP claim is explicit concept-only and checks official acknowledgment',
    () async {
      await accounts.update(kugou: {'token': 'standard', 'userid': '1'});
      await expectLater(
        catalog.claimKugouDailyVip(),
        throwsA(isA<MusicSearchException>()),
      );
      expect(requests, isEmpty);
      await accounts.update(
        kugou: {'token': 'lite', 'userid': '2'},
        platform: 1,
      );
      handler = (_) async => {'status': 0};
      await expectLater(
        catalog.claimKugouDailyVip(),
        throwsA(isA<MusicSearchException>()),
      );
      handler = (_) async => {'status': 1};
      await catalog.claimKugouDailyVip();
      expect(
        requests.last.uri.path,
        '/youth/v1/recharge/receive_vip_listen_song',
      );
      expect(requests.last.uri.queryParameters['receive_day'], '1');
      expect(requests.last.body, isNotNull);
    },
  );

  testWidgets('compact account page never sends SMS on opening', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final localAccounts = AccountStore();
    await localAccounts.initialize();
    final localCatalog = NativeMusicCatalog(
      accounts: localAccounts,
      transport: (_) async {
        fail('No automatic network request');
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: KugouAccountPage(catalog: localCatalog)),
    );
    await tester.pumpAndSettle();
    expect(find.text('发送验证码'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
