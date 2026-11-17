import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/connectivity_listener.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/core/storage/sync_queue.dart';
import 'package:omninest/features/files/data/file_api.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_progress_repository.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';

class MockReaderApi extends Mock implements ReaderApi {}

class MockFileApi extends Mock implements FileApi {}

class MockMusicApi extends Mock implements MusicApi {}

/// 测试用 FileNode 占位对象
FileNode _dummyFileNode() => const FileNode(
  id: 'dummy',
  parentId: null,
  name: 'dummy',
  isFolder: false,
  nodeType: 'FILE',
  normalizedPath: '/dummy',
  sizeBytes: 0,
  updatedAt: null,
);

void main() {
  late LocalDatabase db;
  late SyncQueue syncQueue;
  late MockFileApi fileApi;
  late MockMusicApi musicApi;
  late MusicProgressRepository musicProgressRepository;
  late MockReaderApi readerApi;
  late ConnectivityListener listener;

  setUpAll(() {
    registerFallbackValue(_dummyFileNode());
    registerFallbackValue(
      MusicPlaybackProgress(
        playableKey: 'fallback',
        positionSeconds: 0,
        durationSeconds: 0,
        completed: false,
        updatedAt: DateTime.utc(2026, 7, 14),
        version: 0,
      ),
    );
  });

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    syncQueue = SyncQueue(db);
    fileApi = MockFileApi();
    musicApi = MockMusicApi();
    musicProgressRepository = MusicProgressRepository(
      database: db,
      syncQueue: syncQueue,
      api: musicApi,
    );
    readerApi = MockReaderApi();
    ReaderSyncQueue.init(db);
    listener = ConnectivityListener(
      syncQueue: syncQueue,
      fileApi: fileApi,
      musicApi: musicApi,
      musicProgressRepository: musicProgressRepository,
      readerApi: readerApi,
    );
  });

  tearDown(() async {
    listener.stop();
    await db.close();
  });

  group('replaySyncQueue dispatch', () {
    test('dispatches file.favorite to FileApi.addFavorite', () async {
      await syncQueue.enqueue(
        type: 'file.favorite',
        payload: jsonEncode({'fileId': 'file-123'}),
      );
      when(
        () => fileApi.addFavorite('file-123'),
      ).thenAnswer((_) async => _dummyFileNode());

      await listener.replaySyncQueue();

      verify(() => fileApi.addFavorite('file-123')).called(1);
      // 操作应标记为 completed
      final remaining = await syncQueue.dequeue();
      expect(remaining, isEmpty);
    });

    test('dispatches file.unfavorite to FileApi.removeFavorite', () async {
      await syncQueue.enqueue(
        type: 'file.unfavorite',
        payload: jsonEncode({'fileId': 'file-456'}),
      );
      when(() => fileApi.removeFavorite('file-456')).thenAnswer((_) async {});

      await listener.replaySyncQueue();

      verify(() => fileApi.removeFavorite('file-456')).called(1);
    });

    test(
      'dispatches music.play_history to MusicApi.recordPlayHistory',
      () async {
        await syncQueue.enqueue(
          type: 'music.play_history',
          payload: jsonEncode({'trackId': 'track-001'}),
        );
        when(
          () => musicApi.recordPlayHistory('track-001'),
        ).thenAnswer((_) async {});

        await listener.replaySyncQueue();

        verify(() => musicApi.recordPlayHistory('track-001')).called(1);
      },
    );

    test('dispatches merged music playback progress', () async {
      await musicProgressRepository.saveLocal(
        playableKey: 'online:netease:song-1',
        position: const Duration(seconds: 75),
        duration: const Duration(seconds: 180),
        completed: false,
      );
      when(() => musicApi.savePlaybackProgress(any())).thenAnswer(
        (_) async => MusicPlaybackProgress(
          playableKey: 'online:netease:song-1',
          positionSeconds: 75,
          durationSeconds: 180,
          completed: false,
          updatedAt: DateTime(2026, 7, 10),
          version: 1,
        ),
      );

      await listener.replaySyncQueue();

      verify(() => musicApi.savePlaybackProgress(any())).called(1);
      expect(await syncQueue.dequeue(), isEmpty);
    });

    test('unknown type is marked completed without API call', () async {
      await syncQueue.enqueue(
        type: 'unknown.type',
        payload: jsonEncode({'someKey': 'someValue'}),
      );

      await listener.replaySyncQueue();

      verifyNever(() => fileApi.addFavorite(any()));
      verifyNever(() => fileApi.removeFavorite(any()));
      verifyNever(() => musicApi.recordPlayHistory(any()));
      // 操作应标记为 completed，不阻塞队列
      final remaining = await syncQueue.dequeue();
      expect(remaining, isEmpty);
    });

    test('API exception marks operation as failed', () async {
      await syncQueue.enqueue(
        type: 'file.favorite',
        payload: jsonEncode({'fileId': 'file-err'}),
      );
      when(() => fileApi.addFavorite('file-err')).thenThrow(Exception('网络异常'));

      await listener.replaySyncQueue();

      verify(() => fileApi.addFavorite('file-err')).called(1);
      // 操作应标记为 failed
      final pending = await syncQueue.dequeue();
      expect(pending, isEmpty);
      // 重试队列中应有该操作
      final dbOps = await db.select(db.syncOperations).get();
      expect(dbOps.first.status, 'failed');
      expect(dbOps.first.retryCount, 1);
    });

    test('replays reader sync queue before generic queue', () async {
      await ReaderSyncQueue.enqueueProgress(
        itemId: 'reader-1',
        charOffset: 300,
        progressPercent: 0.3,
        readingMode: 'scroll',
      );
      when(
        () => readerApi.updateProgress(
          itemId: 'reader-1',
          charOffset: 300,
          progressPercent: 0.3,
          readingMode: 'scroll',
          chapterId: null,
        ),
      ).thenAnswer((_) async {});

      await listener.replaySyncQueue();

      verify(
        () => readerApi.updateProgress(
          itemId: 'reader-1',
          charOffset: 300,
          progressPercent: 0.3,
          readingMode: 'scroll',
          chapterId: null,
        ),
      ).called(1);
      final operations = await db.select(db.syncOperations).get();
      // 同步成功的 reader 操作 payload 含笔记/批注明文，成功后即从本地库清理。
      expect(operations, isEmpty);
    });
  });
}
