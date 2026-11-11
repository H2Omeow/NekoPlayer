import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/domain/library.dart';

void main() {
  test('library round trip preserves tracks, playlists and settings', () {
    const original = LibraryData(
      tracks: [Track(path: '/music/猫.flac', title: '猫', artist: 'Neko')],
      favorites: {'/music/猫.flac'},
      history: ['/music/猫.flac'],
      playlists: [
        LocalPlaylist(id: 'one', name: '夜晚', paths: ['/music/猫.flac']),
      ],
      volume: 42,
      rate: 1.25,
      fadePlayback: false,
      fadeMilliseconds: 1200,
    );
    final restored = LibraryData.decode(original.encode());
    expect(restored.tracks.single.title, '猫');
    expect(restored.favorites.single, '/music/猫.flac');
    expect(restored.playlists.single.name, '夜晚');
    expect(restored.volume, 42);
    expect(restored.rate, 1.25);
    expect(restored.fadePlayback, isFalse);
    expect(restored.fadeMilliseconds, 1200);
  });

  test('library drops dangling references and deduplicates records', () {
    const original = LibraryData(
      tracks: [
        Track(path: '/a', title: 'A', artist: ''),
        Track(path: '/a', title: 'A', artist: ''),
      ],
      favorites: {'/a', '/missing'},
      history: ['/a', '/a', '/missing'],
      playlists: [
        LocalPlaylist(id: 'one', name: 'One', paths: ['/a', '/missing', '/a']),
      ],
    );
    final restored = LibraryData.decode(original.encode());
    expect(restored.tracks, hasLength(1));
    expect(restored.favorites, {'/a'});
    expect(restored.history, ['/a']);
    expect(restored.playlists.single.paths, ['/a']);
  });

  test(
    'unknown library format is rejected instead of silently overwritten',
    () {
      expect(
        () => LibraryData.decode('{"version": 99}'),
        throwsFormatException,
      );
      expect(() => LibraryData.decode('not-json'), throwsFormatException);
    },
  );

  test('LRC parses multiple timestamps, fractions and offset', () {
    final lines = parseLrc(
      '[ar:Neko]\n[offset:-200]\n[00:01.5][01:02.050]一句歌词\n[00:00.10]开头',
    );
    expect(lines.map((line) => line.time.inMilliseconds), [0, 1300, 61850]);
    expect(lines.map((line) => line.text), ['开头', '一句歌词', '一句歌词']);
  });

  test('LRC ignores metadata, invalid seconds and blank lines', () {
    expect(
      parseLrc('[ti:Title]\n[00:61.00]invalid\n[00:01.00]\nnot timed'),
      isEmpty,
    );
    expect(
      parseLrc('[00:03]No fraction').single.time,
      const Duration(seconds: 3),
    );
  });
  test(
    'same-time translated lyrics merge without losing the original line',
    () {
      final lines = parseLrc(
        '[00:01]Hello\n[00:02]World\n[00:01]你好\n[00:01]你好',
      );
      expect(lines, hasLength(2));
      expect(lines.first.text, 'Hello');
      expect(lines.first.translation, '你好');
    },
  );
}
