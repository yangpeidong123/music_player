import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// 歌曲表
@DataClassName('SongEntry')
class Songs extends Table {
  TextColumn get id => text()(); // source_id + music_id
  TextColumn get name => text()();
  TextColumn get singer => text()();
  TextColumn get album => text().withDefault(const Constant(''))();
  TextColumn get source => text()(); // kw, wy, kg, tx, mg
  TextColumn get musicId => text()(); // 平台内 ID
  TextColumn get img => text().nullable()();
  IntColumn get interval => integer().withDefault(const Constant(0))();
  TextColumn get hash => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 歌单表
@DataClassName('PlaylistEntry')
class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get cover => text().nullable()();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get sort => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 歌单-歌曲关联表
@DataClassName('PlaylistSongEntry')
class PlaylistSongs extends Table {
  TextColumn get playlistId => text().references(Playlists, #id)();
  TextColumn get songId => text().references(Songs, #id)();
  IntColumn get sort => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {playlistId, songId};
}

/// 播放历史表
@DataClassName('HistoryEntry')
class PlayHistory extends Table {
  IntegerColumn get id => integer().autoIncrement()();
  TextColumn get songId => text().references(Songs, #id)();
  DateTimeColumn get playedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get playCount => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 收藏表
@DataClassName('FavoriteEntry')
class Favorites extends Table {
  TextColumn get songId => text().references(Songs, #id)();
  DateTimeColumn get favoritedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {songId};
}

/// 音源记录表
@DataClassName('SourceEntry')
class SourceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get url => text().nullable()();
  TextColumn get script => text()();
  TextColumn get version => text()();
  TextColumn get author => text().withDefault(const Constant(''))();
  TextColumn get homepage => text().nullable()();
  TextColumn get capabilities => text()(); // JSON
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get importedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Songs, Playlists, PlaylistSongs, PlayHistory, Favorites, SourceRecords])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'music_player.db'));
      return NativeDatabase.createInBackground(file);
    });
  }

  // ============================================================
  // 歌曲 CRUD
  // ============================================================

  Future<String> upsertSong({
    required String musicId,
    required String source,
    required String name,
    required String singer,
    String album = '',
    String? img,
    int interval = 0,
    String? hash,
  }) async {
    final id = '${source}_$musicId';
    await into(songs).insertOnConflictUpdate(SongsCompanion.insert(
      id: id,
      name: name,
      singer: singer,
      album: Value(album),
      source: source,
      musicId: musicId,
      img: Value(img),
      interval: Value(interval),
      hash: Value(hash),
    ));
    return id;
  }

  Future<List<SongEntry>> getAllSongs() => select(songs).get();
  Future<SongEntry?> getSong(String id) =>
      (select(songs)..where((t) => t.id.equals(id))).getSingleOrNull();

  // ============================================================
  // 歌单 CRUD
  // ============================================================

  Future<String> createPlaylist(String name, {String? cover, String description = ''}) async {
    final id = 'pl_${DateTime.now().millisecondsSinceEpoch}';
    await into(playlists).insert(PlaylistsCompanion.insert(
      id: id,
      name: name,
      cover: Value(cover),
      description: Value(description),
    ));
    return id;
  }

  Future<List<PlaylistEntry>> getAllPlaylists() =>
      (select(playlists)..orderBy([(t) => OrderingTerm.asc(t.sort)])).get();

  Future<void> renamePlaylist(String id, String name) =>
      (update(playlists)..where((t) => t.id.equals(id))).write(PlaylistsCompanion(name: name));

  Future<void> deletePlaylist(String id) async {
    await (delete(playlistSongs)..where((t) => t.playlistId.equals(id))).go();
    await (delete(playlists)..where((t) => t.id.equals(id))).go();
  }

  Future<void> addSongToPlaylist(String playlistId, String songId, {int sort = 0}) =>
      into(playlistSongs).insertOnConflictUpdate(PlaylistSongsCompanion.insert(
        playlistId: playlistId,
        songId: songId,
        sort: Value(sort),
      ));

  Future<void> removeSongFromPlaylist(String playlistId, String songId) =>
      (delete(playlistSongs)..where((t) =>
          t.playlistId.equals(playlistId) & t.songId.equals(songId))).go();

  Future<List<SongEntry>> getPlaylistSongs(String playlistId) async {
    final query = select(songs).join(
      innerJoin(playlistSongs, playlistSongs.songId.equalsExp(songs.id)),
    )
      ..where(playlistSongs.playlistId.equals(playlistId))
      ..orderBy([OrderingTerm.asc(playlistSongs.sort)]);
    final rows = await query.get();
    return rows.map((row) => row.readTable(songs)).toList();
  }

  // ============================================================
  // 播放历史
  // ============================================================

  Future<void> recordPlay(String songId) async {
    final existing = await (select(playHistory)
          ..where((t) => t.songId.equals(songId))
          ..orderBy([(t) => OrderingTerm.desc(t.playedAt)])
          ..limit(1))
        .getSingleOrNull();

    if (existing != null &&
        DateTime.now().difference(existing.playedAt).inMinutes < 5) {
      // 5 分钟内重复播放只增加计数
      await (update(playHistory)..where((t) => t.id.equals(existing.id)))
          .write(PlayHistoryCompanion(
        playCount: Value(existing.playCount + 1),
        playedAt: Value(DateTime.now()),
      ));
    } else {
      await into(playHistory).insert(PlayHistoryCompanion.insert(songId: songId));
    }
  }

  Future<List<SongEntry>> getPlayHistory({int limit = 100}) async {
    final query = select(songs).join(
      innerJoin(playHistory, playHistory.songId.equalsExp(songs.id)),
    )
      ..orderBy([OrderingTerm.desc(playHistory.playedAt)])
      ..limit(limit);
    final rows = await query.get();
    return rows.map((row) => row.readTable(songs)).toList();
  }

  Future<void> clearHistory() => delete(playHistory).go();

  // ============================================================
  // 收藏
  // ============================================================

  Future<void> addFavorite(String songId) =>
      into(favorites).insertOnConflictUpdate(
        FavoritesCompanion.insert(songId: songId));

  Future<void> removeFavorite(String songId) =>
      (delete(favorites)..where((t) => t.songId.equals(songId))).go();

  Future<bool> isFavorite(String songId) =>
      (select(favorites)..where((t) => t.songId.equals(songId))).getSingleOrNull()
          .then((e) => e != null);

  Future<List<SongEntry>> getFavorites() async {
    final query = select(songs).join(
      innerJoin(favorites, favorites.songId.equalsExp(songs.id)),
    )..orderBy([OrderingTerm.desc(favorites.favoritedAt)]);
    final rows = await query.get();
    return rows.map((row) => row.readTable(songs)).toList();
  }

  // ============================================================
  // 音源记录
  // ============================================================

  Future<void> saveSource({
    required String id,
    required String name,
    String? url,
    required String script,
    required String version,
    String author = '',
    String? homepage,
    required String capabilities,
  }) => into(sourceRecords).insertOnConflictUpdate(
        SourceRecordsCompanion.insert(
          id: id,
          name: name,
          url: Value(url),
          script: script,
          version: version,
          author: Value(author),
          homepage: Value(homepage),
          capabilities: capabilities,
        ));

  Future<List<SourceEntry>> getAllSources() => select(sourceRecords).get();
  Future<void> deleteSource(String id) =>
      (delete(sourceRecords)..where((t) => t.id.equals(id))).go();
  Future<void> setSourceEnabled(String id, bool enabled) =>
      (update(sourceRecords)..where((t) => t.id.equals(id)))
          .write(SourceRecordsCompanion(enabled: Value(enabled)));
}
