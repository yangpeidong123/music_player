import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/engine/source_engine.dart';

void main() {
  group('SourceMeta', () {
    test('parses standard metadata', () {
      const script = '''
/*!
 * @name 测试音源
 * @description 这是一个测试
 * @version v1.2.3
 * @author 作者
 * @homepage https://example.com
 */
console.log('hi');
''';
      final meta = SourceMeta.fromScript(script);
      expect(meta.name, '测试音源');
      expect(meta.description, '这是一个测试');
      expect(meta.version, 'v1.2.3');
      expect(meta.author, '作者');
      expect(meta.homepage, 'https://example.com');
      expect(meta.isValid, isTrue);
    });

    test('handles missing metadata', () {
      const script = 'console.log("no meta");';
      final meta = SourceMeta.fromScript(script);
      expect(meta.name, isEmpty);
      expect(meta.isValid, isFalse);
    });

    test('handles partial metadata', () {
      const script = '''
/*!
 * @name Test
 * @version 1.0
 */
''';
      final meta = SourceMeta.fromScript(script);
      expect(meta.name, 'Test');
      expect(meta.version, '1.0');
      expect(meta.author, isEmpty);
    });
  });

  group('MusicInfo', () {
    test('toJson and fromJson roundtrip', () {
      const original = MusicInfo(
        id: '123',
        name: 'Song',
        singer: 'Artist',
        album: 'Album',
        source: 'kw',
        img: 'https://example.com/img.jpg',
        interval: 240,
      );
      final json = original.toJson();
      final restored = MusicInfo.fromJson({...json, 'source': 'kw'});
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.singer, original.singer);
      expect(restored.album, original.album);
      expect(restored.interval, original.interval);
    });

    test('stableId is platform-specific', () {
      const m1 = MusicInfo(id: '1', name: 'A', singer: 'B', source: 'kw');
      const m2 = MusicInfo(id: '1', name: 'A', singer: 'B', source: 'wy');
      expect(m1.stableId, 'kw_1');
      expect(m2.stableId, 'wy_1');
      expect(m1.stableId != m2.stableId, isTrue);
    });
  });

  group('SourceCapabilities', () {
    test('parses from json', () {
      final json = {
        'sources': {
          'kw': {
            'type': 'music',
            'actions': ['musicUrl', 'lyric', 'pic'],
            'qualitys': ['128k', '320k', 'flac'],
          },
        },
      };
      final caps = SourceCapabilities.fromJson(json);
      expect(caps.supports('kw'), isTrue);
      expect(caps.supports('wy'), isFalse);
      expect(caps.qualitys['kw'], ['128k', '320k', 'flac']);
      expect(caps.availablePlatforms, ['kw']);
    });
  });
}
