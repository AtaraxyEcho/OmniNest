import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';
import 'package:omninest/core/security/offline_text_cipher.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

class MockReaderApi extends Mock implements ReaderApi {}

/// 内存密钥存储：同一用户重复读取返回同一主密钥。
class _InMemoryKeyStore implements OfflineKeyStore {
  final Map<String, List<int>> _keys = {};

  @override
  Future<void> delete(String userId) async {
    _keys.remove(userId);
  }

  @override
  Future<OfflineMasterKey> readOrCreate(String userId) async {
    final key = _keys[userId] ??= List<int>.generate(32, (index) => index + 1);
    return OfflineMasterKey(keyId: 'test', bytes: Uint8List.fromList(key));
  }
}

void main() {
  late LocalDatabase db;
  late MockReaderApi api;
  late OfflineTextCipher cipher;
  final createdAt = DateTime(2026, 9, 20);

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    api = MockReaderApi();
    cipher = OfflineTextCipher(keyStore: _InMemoryKeyStore());
    ReaderSyncQueue.init(db, textCipher: cipher, userId: 'user-1');
  });

  tearDown(() async {
    await db.close();
  });

  Future<SyncOperation> singleOperation() async {
    return (await db.select(db.syncOperations).get()).single;
  }

  test('笔记创建载荷加密落库，且可解密用于待同步合并', () async {
    await ReaderSyncQueue.enqueueNoteCreate(
      localId: 'local-1',
      itemId: 'item-1',
      title: '标题',
      content: '机密笔记正文',
    );

    final operation = await singleOperation();
    expect(operation.payload.startsWith('enc:v1:'), isTrue);
    expect(operation.payload.contains('机密笔记正文'), isFalse);
    expect(operation.payload.contains('"content"'), isFalse);

    final pending = await ReaderSyncQueue.pendingMutations(
      updateType: ReaderSyncQueue.opNoteCreate,
      deleteType: ReaderSyncQueue.opNoteDelete,
      idField: 'localId',
    );
    expect(pending.updatingPayloads['local-1']?['content'], '机密笔记正文');
  });

  test('待同步创建载荷更新后重新加密，不残留明文', () async {
    await ReaderSyncQueue.enqueueNoteCreate(
      localId: 'local-1',
      itemId: 'item-1',
      title: '标题',
      content: '初版正文',
    );

    await ReaderSyncQueue.updatePendingNoteCreate(
      localId: 'local-1',
      title: '新标题',
      content: '更新后的正文',
    );

    final operation = await singleOperation();
    expect(operation.payload.startsWith('enc:v1:'), isTrue);
    expect(operation.payload.contains('更新后的正文'), isFalse);
    expect(operation.payload.contains('新标题'), isFalse);

    final pending = await ReaderSyncQueue.pendingMutations(
      updateType: ReaderSyncQueue.opNoteCreate,
      deleteType: ReaderSyncQueue.opNoteDelete,
      idField: 'localId',
    );
    expect(pending.updatingPayloads['local-1']?['content'], '更新后的正文');
    expect(pending.updatingPayloads['local-1']?['title'], '新标题');
  });

  test('刷新队列时用解密后的载荷发起请求', () async {
    await ReaderSyncQueue.enqueueNoteCreate(
      localId: 'local-1',
      itemId: 'item-1',
      title: '标题',
      content: '正文内容',
    );
    when(
      () => api.createNote(
        itemId: 'item-1',
        charOffset: null,
        title: '标题',
        content: '正文内容',
        clientOperationId: 'local-1',
      ),
    ).thenAnswer(
      (_) async => ReaderNote(
        id: 'local-1',
        readerItemId: 'item-1',
        title: '标题',
        content: '正文内容',
        createdAt: createdAt,
      ),
    );

    await ReaderSyncQueue.flush(api: api);

    verify(
      () => api.createNote(
        itemId: 'item-1',
        charOffset: null,
        title: '标题',
        content: '正文内容',
        clientOperationId: 'local-1',
      ),
    ).called(1);
    expect(await db.select(db.syncOperations).get(), isEmpty);
  });

  test('失败重放仍保留密文载荷，重试时解密成功', () async {
    await ReaderSyncQueue.enqueueNoteUpdate(
      noteId: 'note-1',
      title: '标题',
      content: '正文内容',
    );
    when(
      () => api.updateNote('note-1', title: '标题', content: '正文内容'),
    ).thenThrow(Exception('network down'));

    await ReaderSyncQueue.flush(api: api);

    final failed = await singleOperation();
    expect(failed.status, 'failed');
    expect(failed.retryCount, 1);
    expect(failed.payload.startsWith('enc:v1:'), isTrue);
    expect(failed.payload.contains('正文内容'), isFalse);

    when(
      () => api.updateNote('note-1', title: '标题', content: '正文内容'),
    ).thenAnswer(
      (_) async => ReaderNote(
        id: 'note-1',
        readerItemId: 'item-1',
        title: '标题',
        content: '正文内容',
        createdAt: createdAt,
      ),
    );
    await ReaderSyncQueue.retryFailed();
    await ReaderSyncQueue.flush(api: api);

    verify(
      () => api.updateNote('note-1', title: '标题', content: '正文内容'),
    ).called(2);
  });

  test('载荷无法解密时按失败处理且不崩溃', () async {
    await db
        .into(db.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            userId: const Value('user-1'),
            type: ReaderSyncQueue.opNoteUpdate,
            payload: 'enc:v1:AAAA',
            createdAt: createdAt,
          ),
        );

    await ReaderSyncQueue.flush(api: api);

    final operation = await singleOperation();
    expect(operation.status, 'failed');
    verifyNever(
      () => api.updateNote(
        any(),
        title: any(named: 'title'),
        content: any(named: 'content'),
      ),
    );
  });

  test('未注入加密器时（Web）载荷保持明文', () async {
    ReaderSyncQueue.init(db);

    await ReaderSyncQueue.enqueueNoteCreate(
      localId: 'local-2',
      itemId: 'item-1',
      title: '标题',
      content: '明文正文',
    );

    final operation = await singleOperation();
    expect(operation.payload.startsWith('enc:v1:'), isFalse);
    expect(operation.payload.contains('明文正文'), isTrue);
  });
}
