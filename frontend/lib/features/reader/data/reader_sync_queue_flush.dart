part of 'reader_sync_queue.dart';

/// 刷新队列的单飞与脏循环状态：与队列本体同库，但把长流程从宿主文件里分离。
Future<void>? _activeFlush;
bool _needsAnotherPass = false;

Future<void> runReaderSyncFlush(ReaderApi? api) async {
  if (api == null || ReaderSyncQueue._db == null) {
    return;
  }
  final active = _activeFlush;
  if (active != null) {
    // 单飞：并发调用者必须等待在途轮次，并请求再跑一轮，
    // 否则创建回包的 localId 替换尚未完成时调用方就拉取远端，
    // 同一条笔记会以 local_xxx 与服务端 ID 双份出现。
    _needsAnotherPass = true;
    await active;
    return;
  }
  final run = _runFlushLoop(api);
  _activeFlush = run;
  try {
    await run;
  } finally {
    if (identical(_activeFlush, run)) {
      _activeFlush = null;
    }
  }
}

Future<void> _runFlushLoop(ReaderApi api) async {
  do {
    _needsAnotherPass = false;
    await _performReaderFlush(api);
  } while (_needsAnotherPass && ReaderSyncQueue._db != null);
}

/// 执行实际的队列刷新逻辑。
Future<void> _performReaderFlush(ReaderApi api) async {
  final sessionUserId = ReaderSyncQueue._userId;
  // 进度行先出：同一本书已合并为一条，数量很小，但笔记/批注积压超过一批时
  // 不能把续读指针排在 50 条之外等下一轮。其余操作仍按 createdAt 升序，
  // 保持 create→update 的先后语义（倒序会让旧更新覆盖新创建载荷）。
  final progressOps = await ReaderSyncQueue._pendingReaderOps(
    types: const [ReaderSyncQueue.opProgress],
  );
  final otherOps = await ReaderSyncQueue._pendingReaderOps(
    types: ReaderSyncQueue._readerOperationTypes,
    limit: ReaderSyncQueue.maxOperationBatch,
  );
  final remainingSlots = (ReaderSyncQueue.maxOperationBatch -
          progressOps.length)
      .clamp(0, ReaderSyncQueue.maxOperationBatch);
  final pending = <SyncOperation>[
    ...progressOps,
    ...otherOps
        .where((operation) => operation.type != ReaderSyncQueue.opProgress)
        .take(remainingSlots),
  ];

  for (final op in pending) {
    // 每一步都是异步边界：期间可能登出或换号。账号一变必须立刻停手，
    // 否则替换逻辑会用新账号查旧账号的 localId，并把删除写进新账号队列。
    if (ReaderSyncQueue._userId != sessionUserId ||
        ReaderSyncQueue._db == null) {
      return;
    }
    // 创建回包会把后续更新/删除的 localId 改写成服务端 ID；pending 是本轮
    // 开始时取的快照，派发前必须重读最新载荷，否则仍会带着临时 ID 发出去。
    final current = await ReaderSyncQueue._reloadPendingOperation(op.id);
    if (current == null) {
      continue;
    }
    try {
      await ReaderSyncQueue._dispatch(api, current);
      await ReaderSyncQueue._markCompleted(current.id);
    } on AppException catch (error) {
      if (error.code == AppErrorCodes.forbidden) {
        // 无 activity:write 的角色：书签/标注/笔记保留本地（本地优先
        // 模型，本地即真值），跳过远端同步，不做无意义重试。
        await ReaderSyncQueue._markCompleted(current.id);
      } else if (ReaderSyncQueue._isIdempotentDeleteFailure(current, error)) {
        // 记录多半在另一台设备上已经删掉了：补发永远不会成功，留着失败行会
        // 长期占表，并让本地删除一直显示"尚未同步"。
        await ReaderSyncQueue._markCompleted(current.id);
      } else {
        await ReaderSyncQueue._markFailed(current);
      }
    } on _UnrecoverableSyncPayload {
      // 密钥轮换后的陈旧密文与网络失败不同：重试永远不会成功。保留有限次
      // 重试供密钥暂时不可用的情况恢复，耗尽后清理，避免队列永久死锁。
      if (current.retryCount + 1 >= ReaderSyncQueue.maxOperationRetries) {
        await ReaderSyncQueue._deleteOwnedOperations([current.id]);
      } else {
        await ReaderSyncQueue._markFailed(current);
      }
    } on Object {
      // StateError 等 Error 也必须收敛：逃逸出去会让本次 flush 提前中断，
      // 并让调用方误以为同步完成。
      await ReaderSyncQueue._markFailed(current);
    }
  }
  if (pending.isNotEmpty) {
    // 已完成 reader 操作的 payload 含笔记/批注明文，同步成功后即清理，
    // 不在本地库长期保留敏感明文副本
    await (ReaderSyncQueue._database.delete(
      ReaderSyncQueue._database.syncOperations,
    )..where(
      (table) =>
          table.status.equals('completed') &
          table.type.isIn(ReaderSyncQueue._readerOperationTypes) &
          ReaderSyncQueue._ownedByCurrentUser(table.userId),
    )).go();
  }
  // 进度以本地 cached_reader_progress 为真值，重试耗尽的失败行只会
  // 长期占表并在下次 retryFailed 里被反复捞起；笔记/批注失败行保留，
  // 那些数据本地即唯一副本。
  await (ReaderSyncQueue._database.delete(
    ReaderSyncQueue._database.syncOperations,
  )..where(
    (table) =>
        table.type.equals(ReaderSyncQueue.opProgress) &
        table.status.equals('failed') &
        table.retryCount.isBiggerOrEqualValue(
          ReaderSyncQueue.maxOperationRetries,
        ) &
        ReaderSyncQueue._ownedByCurrentUser(table.userId),
  )).go();
}
