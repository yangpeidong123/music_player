import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// 歌曲模型
class SongEntry {
  final String id;
  final String name;
  final String singer;
  final String album;
  final String source;
  final String musicId;
  final String? img;
  final int interval;
  final String? hash;

  SongEntry({
    required this.id,
    required this.name,
    required this.singer,
    this.album = '',
    required this.source,
    required this.musicId,
    this.img,
    this.interval = 0,
    this.hash,
  });

  factory SongEntry.fromMap(Map<String, dynamic> m) => SongEntry(
        id: m['id'] as String,
        name: m['name'] as String,
        singer: m['singer'] as String,
        album: m['album'] as String? ?? '',
        source: m['source'] as String,
        musicId: m['musicId'] as String,
        img: m['img'] as String?,
        interval: m['interval'] as int? ?? 0,
        hash: m['hash'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'name': name, 'singer': singer, 'album': album,
        'source': source, 'musicId': musicId, 'img': img,
        'interval': interval, 'hash': hash,
      };
}

/// 歌单模型
class PlaylistEntry {
  final String id;
  final String name;
  final String? cover;
  final String description;
  PlaylistEntry({required this.id, required this.name, this.cover, this.description = ''});

  factory PlaylistEntry.fromMap(Map<String, dynamic> m) => PlaylistEntry(
        id: m['id'] as String, name: m['name'] as String,
        cover: m['cover'] as String?, description: m['description'] as String? ?? '',
      );
}

/// 音源记录
class SourceEntry {
  final String id;
  final String name;
  final String? url;
  final String version;
  final String author;
  final bool enabled;
  SourceEntry({required this.id, required this.name, this.url, required this.version, this.author = '', this.enabled = true});

  factory SourceEntry.fromMap(Map<String, dynamic> m) => SourceEntry(
        id: m['id'] as String, name: m['name'] as String, url: m['url'] as String?,
        version: m['version'] as String? ?? '', author: m['author'] as String? ?? '',
        enabled: (m['enabled'] as int? ?? 1) == 1,
      );
}

/// SQLite 数据库 — 使用 sqflite（无需代码生成）
class AppDatabase {
  Database? _db;

  Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final path = p.join(await getDatabasesPath(), 'music_player.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''CREATE TABLE songs(
          id TEXT PRIMARY KEY, name TEXT, singer TEXT, album TEXT,
          source TEXT, musicId TEXT, img TEXT, interval INTEGER, hash TEXT,
          createdAt TEXT DEFAULT (datetime('now')))''');
        await db.execute('''CREATE TABLE playlists(
          id TEXT PRIMARY KEY, name TEXT, cover TEXT, description TEXT,
          sort INTEGER DEFAULT 0, createdAt TEXT, updatedAt TEXT)''');
        await db.execute('''CREATE TABLE playlist_songs(
          playlistId TEXT, songId TEXT, sort INTEGER DEFAULT 0,
          PRIMARY KEY (playlistId, songId))''');
        await db.execute('''CREATE TABLE play_history(
          id INTEGER PRIMARY KEY AUTOINCREMENT, songId TEXT, playedAt TEXT,
          playCount INTEGER DEFAULT 1)''');
        await db.execute('''CREATE TABLE favorites(
          songId TEXT PRIMARY KEY, favoritedAt TEXT)''');
        await db.execute('''CREATE TABLE source_records(
          id TEXT PRIMARY KEY, name TEXT, url TEXT, script TEXT,
          version TEXT, author TEXT, homepage TEXT, capabilities TEXT,
          enabled INTEGER DEFAULT 1, importedAt TEXT)''');
      },
    );
  }

  // — 歌曲 —
  Future<String> upsertSong({required String musicId, required String source, required String name, required String singer, String album = '', String? img, int interval = 0, String? hash}) async {
    final d = await db;
    final id = '${source}_$musicId';
    await d.insert('songs', {'id': id, 'name': name, 'singer': singer, 'album': album, 'source': source, 'musicId': musicId, 'img': img, 'interval': interval, 'hash': hash}, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  Future<SongEntry?> getSong(String id) async {
    final d = await db;
    final list = await d.query('songs', where: 'id = ?', whereArgs: [id], limit: 1);
    return list.isEmpty ? null : SongEntry.fromMap(list.first);
  }

  // — 歌单 —
  Future<String> createPlaylist(String name, {String? cover, String description = ''}) async {
    final d = await db;
    final id = 'pl_${DateTime.now().millisecondsSinceEpoch}';
    await d.insert('playlists', {'id': id, 'name': name, 'cover': cover, 'description': description, 'sort': 0, 'createdAt': DateTime.now().toIso8601String(), 'updatedAt': DateTime.now().toIso8601String()});
    return id;
  }

  Future<List<PlaylistEntry>> getAllPlaylists() async {
    final d = await db;
    final list = await d.query('playlists', orderBy: 'sort ASC');
    return list.map(PlaylistEntry.fromMap).toList();
  }

  Future<void> renamePlaylist(String id, String name) async {
    final d = await db;
    await d.update('playlists', {'name': name, 'updatedAt': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePlaylist(String id) async {
    final d = await db;
    await d.delete('playlist_songs', where: 'playlistId = ?', whereArgs: [id]);
    await d.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addSongToPlaylist(String playlistId, String songId, {int sort = 0}) async {
    final d = await db;
    await d.insert('playlist_songs', {'playlistId': playlistId, 'songId': songId, 'sort': sort}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final d = await db;
    await d.delete('playlist_songs', where: 'playlistId = ? AND songId = ?', whereArgs: [playlistId, songId]);
  }

  Future<List<SongEntry>> getPlaylistSongs(String playlistId) async {
    final d = await db;
    final list = await d.rawQuery('SELECT s.* FROM songs s INNER JOIN playlist_songs ps ON ps.songId = s.id WHERE ps.playlistId = ? ORDER BY ps.sort', [playlistId]);
    return list.map(SongEntry.fromMap).toList();
  }

  // — 播放历史 —
  Future<void> recordPlay(String songId) async {
    final d = await db;
    final existing = await d.query('play_history', where: 'songId = ?', whereArgs: [songId], orderBy: 'playedAt DESC', limit: 1);
    if (existing.isNotEmpty) {
      final last = existing.first;
      final playedAt = DateTime.parse(last['playedAt'] as String);
      if (DateTime.now().difference(playedAt).inMinutes < 5) {
        await d.update('play_history', {'playCount': (last['playCount'] as int? ?? 1) + 1, 'playedAt': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [last['id']]);
        return;
      }
    }
    await d.insert('play_history', {'songId': songId, 'playedAt': DateTime.now().toIso8601String()});
  }

  Future<List<SongEntry>> getPlayHistory({int limit = 100}) async {
    final d = await db;
    final list = await d.rawQuery('SELECT s.* FROM songs s INNER JOIN play_history h ON h.songId = s.id ORDER BY h.playedAt DESC LIMIT ?', [limit]);
    return list.map(SongEntry.fromMap).toList();
  }

  Future<void> clearHistory() async {
    final d = await db;
    await d.delete('play_history');
  }

  // — 收藏 —
  Future<void> addFavorite(String songId) async {
    final d = await db;
    await d.insert('favorites', {'songId': songId, 'favoritedAt': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFavorite(String songId) async {
    final d = await db;
    await d.delete('favorites', where: 'songId = ?', whereArgs: [songId]);
  }

  Future<bool> isFavorite(String songId) async {
    final d = await db;
    final list = await d.query('favorites', where: 'songId = ?', whereArgs: [songId], limit: 1);
    return list.isNotEmpty;
  }

  Future<List<SongEntry>> getFavorites() async {
    final d = await db;
    final list = await d.rawQuery('SELECT s.* FROM songs s INNER JOIN favorites f ON f.songId = s.id ORDER BY f.favoritedAt DESC');
    return list.map(SongEntry.fromMap).toList();
  }

  // — 音源记录 —
  Future<void> saveSource({required String id, required String name, String? url, required String script, required String version, String author = '', String? homepage, required String capabilities}) async {
    final d = await db;
    await d.insert('source_records', {'id': id, 'name': name, 'url': url, 'script': script, 'version': version, 'author': author, 'homepage': homepage, 'capabilities': capabilities, 'enabled': 1, 'importedAt': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SourceEntry>> getAllSources() async {
    final d = await db;
    final list = await d.query('source_records', orderBy: 'importedAt DESC');
    return list.map(SourceEntry.fromMap).toList();
  }

  Future<void> deleteSource(String id) async {
    final d = await db;
    await d.delete('source_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setSourceEnabled(String id, bool enabled) async {
    final d = await db;
    await d.update('source_records', {'enabled': enabled ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<String?> getSourceScript(String id) async {
    final d = await db;
    final list = await d.query('source_records', where: 'id = ?', whereArgs: [id], limit: 1);
    return list.isEmpty ? null : list.first['script'] as String?;
  }

  Future<void> close() async => await _db?.close();
}
