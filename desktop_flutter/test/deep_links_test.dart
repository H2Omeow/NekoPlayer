import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/deep_links.dart';

void main() {
  test('parses share links from the web and the custom scheme', () {
    final web = AppDeepLink.parse(
      Uri.parse('https://player.nekoh2o.top/s/abcdefghijklmnop1234'),
    );
    expect(web?.shareToken, 'abcdefghijklmnop1234');

    final custom = AppDeepLink.parse(
      Uri.parse('nekoplayer://share?token=abcdefghijklmnop1234'),
    );
    expect(custom?.shareToken, 'abcdefghijklmnop1234');
  });

  test('parses chat and user links', () {
    expect(
      AppDeepLink.parse(Uri.parse('nekoplayer://chat?peer=user-aaaaaa'))?.chatPeer,
      'user-aaaaaa',
    );
    expect(
      AppDeepLink.parse(Uri.parse('nekoplayer://user?id=user-bbbbbb'))?.userId,
      'user-bbbbbb',
    );
  });

  test('rejects foreign hosts, unknown schemes and malformed tokens', () {
    expect(AppDeepLink.parse(Uri.parse('https://evil.test/s/abcdefghijklmnop1234')), isNull);
    expect(AppDeepLink.parse(Uri.parse('https://player.nekoh2o.top/s/short')), isNull);
    expect(AppDeepLink.parse(Uri.parse('nekoplayer://share?token=bad token')), isNull);
    expect(AppDeepLink.parse(Uri.parse('nekoplayer://unknown?id=1')), isNull);
    expect(AppDeepLink.parse(Uri.parse('https://player.nekoh2o.top/user?id=1')), isNull);
  });
}
