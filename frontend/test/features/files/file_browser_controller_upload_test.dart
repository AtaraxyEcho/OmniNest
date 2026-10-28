import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/public_share.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';

import 'package:omninest/features/files/domain/file_operation.dart';
import 'package:omninest/features/files/domain/file_upload_complete_result.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

part 'file_upload_test_paged_fakes.dart';
part 'file_upload_test_repository_fakes.dart';

void main() {
  test('paused upload resumes from next unfinished part', () async {
    final repository = _FakeFileRepository();
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    final uploadFuture = controller.uploadFiles([
      XFile.fromData(
        Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        path: 'large.bin',
        name: 'large.bin',
        mimeType: 'application/octet-stream',
      ),
    ]);
    await repository.firstUploadStarted.future;

    final task =
        container
            .read(fileBrowserControllerProvider)
            .value!
            .localUploadTasks
            .single;
    controller.pauseLocalUploadTask(task.id);
    // 两个在途分片都会收到取消；停留在 PAUSED，不把已取消的分片记成完成。
    await uploadFuture;

    final pausedTask =
        container
            .read(fileBrowserControllerProvider)
            .value!
            .localUploadTasks
            .single;
    expect(pausedTask.status, 'PAUSED');
    expect(pausedTask.uploadedBytes, 0);
    expect(repository.uploadedPartUrls, [
      'http://minio/part-1',
      'http://minio/part-2',
    ]);
    expect(repository.completedPartNumbers, isEmpty);

    final resumeFuture = controller.resumeLocalUploadTask(pausedTask.id);
    await repository.waitForUploadCount(4);
    repository.completeUploadAt(2, 'etag-1');
    repository.completeUploadAt(3, 'etag-2');
    await resumeFuture;

    final completedTask =
        container
            .read(fileBrowserControllerProvider)
            .value!
            .localUploadTasks
            .single;
    expect(completedTask.status, 'COMPLETED');
    expect(completedTask.uploadedBytes, 6);
    expect(repository.uploadedPartUrls, [
      'http://minio/part-1',
      'http://minio/part-2',
      'http://minio/part-1',
      'http://minio/part-2',
    ]);
    expect(repository.completedPartNumbers, [1, 2]);
    expect(repository.completedSessions, ['upload-123']);
  });

  test('分片 URL 在途时暂停：不再发起该分片上传且任务保持 PAUSED', () async {
    // 取分片 URL 的请求在途时还没有登记取消令牌，暂停必须由状态守卫拦住，
    // 否则响应回来后会继续上传整个分片（最大 64 MB）。
    final repository =
        _FakeFileRepository()
          ..omitPartUrls = true
          ..partUrlCompleter = Completer<String>()
          ..partUrlRequested = Completer<void>();
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    final uploadFuture = controller.uploadFiles([
      XFile.fromData(
        Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        path: 'large.bin',
        name: 'large.bin',
        mimeType: 'application/octet-stream',
      ),
    ]);
    await repository.partUrlRequested!.future;
    final task =
        container
            .read(fileBrowserControllerProvider)
            .value!
            .localUploadTasks
            .single;
    controller.pauseLocalUploadTask(task.id);
    repository.partUrlCompleter!.complete('https://storage.test/late');
    await uploadFuture;

    expect(repository.uploadedPartUrls, isEmpty, reason: '暂停后不得再上传分片');
    final pausedTask =
        container
            .read(fileBrowserControllerProvider)
            .value!
            .localUploadTasks
            .single;
    expect(pausedTask.status, 'PAUSED');
    expect(repository.completedSessions, isEmpty);
  });

  test('确认分片在途时暂停：任务保持 PAUSED，不被覆写回 UPLOADING', () async {
    final repository =
        _FakeFileRepository()
          ..completePartCompleter = Completer<void>()
          ..completePartRequested = Completer<void>();
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);
    // 记录状态序列：暂停后若被分片确认回调覆写回 UPLOADING，
    // 收尾的 _markUploadPaused 会把终态改回 PAUSED，只看最终状态会漏掉这次闪变。
    final statuses = <String>[];
    container.listen(fileBrowserControllerProvider, (previous, next) {
      final tasks = next.value?.localUploadTasks;
      if (tasks != null && tasks.isNotEmpty) {
        statuses.add(tasks.single.status);
      }
    }, fireImmediately: true);

    final uploadFuture = controller.uploadFiles([
      XFile.fromData(
        Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        path: 'large.bin',
        name: 'large.bin',
        mimeType: 'application/octet-stream',
      ),
    ]);
    await repository.firstUploadStarted.future;
    await repository.secondUploadStarted.future;
    repository.firstUploadResult.complete('etag-1');
    repository.secondUploadResult.complete('etag-2');
    await repository.completePartRequested!.future;
    final task =
        container
            .read(fileBrowserControllerProvider)
            .value!
            .localUploadTasks
            .single;
    controller.pauseLocalUploadTask(task.id);
    repository.completePartCompleter!.complete();
    await uploadFuture;

    final pausedTask =
        container
            .read(fileBrowserControllerProvider)
            .value!
            .localUploadTasks
            .single;
    expect(pausedTask.status, 'PAUSED');
    expect(repository.completedSessions, isEmpty);
    final pauseIndex = statuses.indexOf('PAUSED');
    expect(pauseIndex, isNonNegative);
    expect(
      statuses.skip(pauseIndex + 1),
      isNot(contains('UPLOADING')),
      reason: '暂停后不得再出现 UPLOADING 覆写',
    );
  });

  test(
    'resuming a paused upload refreshes the file list on completion',
    () async {
      final repository = _FakeFileRepository();
      final container = ProviderContainer.test(
        overrides: [fileRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(fileBrowserControllerProvider.notifier);
      await container.read(fileBrowserControllerProvider.future);

      final uploadFuture = controller.uploadFiles([
        XFile.fromData(
          Uint8List.fromList([1, 2, 3, 4, 5, 6]),
          path: 'large.bin',
          name: 'large.bin',
          mimeType: 'application/octet-stream',
        ),
      ]);
      await repository.firstUploadStarted.future;
      final task =
          container
              .read(fileBrowserControllerProvider)
              .value!
              .localUploadTasks
              .single;
      controller.pauseLocalUploadTask(task.id);
      await uploadFuture;

      final requestCountBeforeResume = repository.personalPageRequests.length;
      final resumeFuture = controller.resumeLocalUploadTask(task.id);
      await repository.waitForUploadCount(4);
      repository.completeUploadAt(2, 'etag-1');
      repository.completeUploadAt(3, 'etag-2');
      await resumeFuture;

      final completedTask =
          container
              .read(fileBrowserControllerProvider)
              .value!
              .localUploadTasks
              .single;
      expect(completedTask.status, 'COMPLETED');
      expect(
        repository.personalPageRequests.length,
        requestCountBeforeResume + 1,
      );
    },
  );

  test('purging a recycle bin item removes it optimistically', () async {
    final file = _fileNode('trashed-1', 'old.txt');
    final repository = _FakeFileRepository()..recycleBin = [file];
    var summaryBuilds = 0;
    final container = ProviderContainer.test(
      overrides: [
        fileRepositoryProvider.overrideWithValue(repository),
        activeTaskSummaryProvider.overrideWith((ref) {
          summaryBuilds += 1;
          return const ActiveTaskSummary(activeCount: 0, failedCount: 0);
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(activeTaskSummaryProvider, (_, _) {});
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);
    await controller.showRecycleBin();

    await controller.purgeFile(file);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(fileBrowserControllerProvider).value!;
    expect(state.recycleBin, isEmpty);
    expect(state.section, FileManagerSection.recycleBin);
    expect(repository.purgedFileIds, ['trashed-1']);
    expect(summaryBuilds, 2);
  });

  test('batch purge removes selected entries optimistically', () async {
    final first = _fileNode('trashed-1', 'one.txt');
    final second = _fileNode('trashed-2', 'two.txt');
    final repository = _FakeFileRepository()..recycleBin = [first, second];
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);
    await controller.showRecycleBin();
    controller.toggleSelection(first.id);
    controller.toggleSelection(second.id);

    await controller.batchPurgeFiles();

    final state = container.read(fileBrowserControllerProvider).value!;
    expect(state.recycleBin, isEmpty);
    expect(repository.batchPurgedFileIds, ['trashed-1', 'trashed-2']);
    expect(state.selectedFileIds, isEmpty);
  });

  test(
    'deleting server upload session cancels it and removes it from queue',
    () async {
      final repository =
          _FakeFileRepository()
            ..uploadQueue = [
              const FileUploadQueueItem(
                id: 'session-id',
                uploadId: 'upload-123',
                fileName: 'large.bin',
                sizeBytes: 6,
                partSizeBytes: 3,
                totalParts: 2,
                uploadedParts: 1,
                status: 'UPLOADING',
              ),
            ];
      final container = ProviderContainer.test(
        overrides: [fileRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(fileBrowserControllerProvider.notifier);
      await container.read(fileBrowserControllerProvider.future);
      await controller.showUploadQueue();

      await controller.deleteServerUploadSession(repository.uploadQueue.single);

      expect(repository.cancelledUploadSessions, ['upload-123']);
      expect(
        container.read(fileBrowserControllerProvider).value!.uploadQueue,
        isEmpty,
      );
    },
  );

  test(
    'foreground file actions expose loading state until request finishes',
    () async {
      final repository = _FakeFileRepository();
      final deleteCompleter = Completer<void>();
      repository.deleteFileCompleter = deleteCompleter;
      final container = ProviderContainer.test(
        overrides: [fileRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(fileBrowserControllerProvider.notifier);
      await container.read(fileBrowserControllerProvider.future);

      final deleteFuture = controller.deleteFile(
        _fileNode('file-id', 'clip.mp4'),
      );

      final busyState = container.read(fileBrowserControllerProvider).value!;
      expect(busyState.isBusy, isTrue);
      expect(busyState.activeOperation, FileOperation.moveToRecycleBin);
      expect(busyState.lastActionError, isNull);

      deleteCompleter.complete();
      await deleteFuture;

      final settledState = container.read(fileBrowserControllerProvider).value!;
      expect(settledState.isBusy, isFalse);
      expect(settledState.activeOperation, isNull);
      expect(repository.deletedFileIds, ['file-id']);
    },
  );

  test('foreground file action failures store readable error state', () async {
    final repository =
        _FakeFileRepository()
          ..deleteFileError = const AppException(
            code: 'FILE_QUOTA_EXCEEDED',
            message: '存储配额不足',
          );
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await expectLater(
      controller.deleteFile(_fileNode('file-id', 'clip.mp4')),
      throwsA(isA<AppException>()),
    );

    final failedState = container.read(fileBrowserControllerProvider).value!;
    expect(failedState.isBusy, isFalse);
    expect(
      failedState.lastActionError?.operation,
      FileOperation.moveToRecycleBin,
    );
    expect(failedState.lastActionError?.message, '存储配额不足');
    expect(failedState.lastActionError?.code, 'FILE_QUOTA_EXCEEDED');
  });

  test('uploads stay visible without blocking file browsing', () async {
    final repository = _FakeFileRepository();
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    final uploadFuture = controller.uploadFiles([
      XFile.fromData(
        Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        path: 'large.bin',
        name: 'large.bin',
        mimeType: 'application/octet-stream',
      ),
    ]);
    await repository.firstUploadStarted.future;

    final uploadingState = container.read(fileBrowserControllerProvider).value!;
    expect(uploadingState.isBusy, isFalse);
    expect(uploadingState.uploadQueueBadgeCount, 1);
    expect(uploadingState.inlineUploadTasks.map((task) => task.fileName), [
      'large.bin',
    ]);

    repository.firstUploadResult.complete('etag-1');
    repository.secondUploadResult.complete('etag-2');
    await uploadFuture;
  });

  test('shared folder parent navigation stays on shared repository', () async {
    final rootFolder = _folderNode('shared-root', 'Shared Root');
    final nestedFolder = _folderNode('shared-child', 'Shared Child');
    final repository =
        _FakeFileRepository()
          ..sharedFilesByParent[null] = [rootFolder]
          ..sharedFilesByParent[rootFolder.id] = [nestedFolder]
          ..sharedFilesByParent[nestedFolder.id] = const [];
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await controller.switchSpace('SHARED');
    await controller.openFolder(rootFolder);
    await controller.openFolder(nestedFolder);
    await controller.goToParent();

    var current = container.read(fileBrowserControllerProvider).value!;
    expect(current.spaceType, 'SHARED');
    expect(current.parentId, rootFolder.id);
    expect(current.breadcrumbs.map((node) => node.id), [rootFolder.id]);

    await controller.goToParent();
    current = container.read(fileBrowserControllerProvider).value!;
    expect(current.parentId, isNull);
    expect(current.breadcrumbs, isEmpty);
    expect(repository.sharedParentRequests, [
      null,
      rootFolder.id,
      nestedFolder.id,
      rootFolder.id,
      null,
    ]);
  });

  test('batch upload continues after an individual file fails', () async {
    final repository = _BatchFileRepository();
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    final result = await controller.uploadFiles([
      XFile.fromData(
        Uint8List.fromList([1]),
        path: 'failed.bin',
        name: 'failed.bin',
      ),
      XFile.fromData(
        Uint8List.fromList([2]),
        path: 'completed.bin',
        name: 'completed.bin',
      ),
    ]);

    expect(result.total, 2);
    expect(result.completed, 1);
    expect(result.failed, 1);
    expect(repository.directUploadNames, ['failed.bin', 'completed.bin']);
    final tasks =
        container.read(fileBrowserControllerProvider).value!.localUploadTasks;
    expect(
      tasks.map((task) => task.status),
      containsAll(['FAILED', 'COMPLETED']),
    );
  });

  test('goToFilePage fetches only the target page', () async {
    final first = _fileNode('file-1', 'one.txt');
    final second = _fileNode('file-2', 'two.txt');
    final repository =
        _FakeFileRepository()
          ..personalFilesByPage[0] = [first]
          ..personalFilesByPage[1] = [second];
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await controller.goToFilePage(1);

    final state = container.read(fileBrowserControllerProvider).value!;
    // 只拉目标页：列表内容与分页条范围一一对应。
    expect(state.files.map((file) => file.id), ['file-2']);
    expect(state.filePage, 1);
    // build 无参预载走仓储默认每页 10 条。
    expect(state.filePageSize, 10);
    // build 预载页 0 后，跳页仅请求目标页 1，不再 0..N 串行重放。
    expect(repository.personalPageRequests, [0, 1]);
  });

  test('main list falls back to the new last page when depleted', () async {
    final first = _fileNode('file-1', 'one.txt');
    final second = _fileNode('file-2', 'two.txt');
    final repository =
        _FakeFileRepository()
          ..personalFilesByPage[0] = [first]
          ..personalFilesByPage[1] = [second];
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await controller.goToFilePage(1);
    // 他端删尽末页：仅剩页 0。
    repository.personalFilesByPage.remove(1);

    await controller.refreshFiles();

    final state = container.read(fileBrowserControllerProvider).value!;
    // 越界空页回退到新末页，分页条不停留在空页。
    expect(state.files.map((file) => file.id), ['file-1']);
    expect(state.filePage, 0);
    expect(repository.personalPageRequests, [0, 1, 1, 0]);
  });

  test('folder navigation keeps the chosen rows per page', () async {
    final repository = _FakeFileRepository();
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await controller.setFilePageSize(50);
    await controller.openFolder(_folderNode('folder-1', 'docs'));

    final state = container.read(fileBrowserControllerProvider).value!;
    // 目录导航回到第 0 页，但每页条数沿用用户已选值而非默认。
    expect(state.filePage, 0);
    expect(state.filePageSize, 50);
    expect(state.parentId, 'folder-1');
  });

  test('mutation refresh keeps recycle list and meta in sync', () async {
    final first = _fileNode('trashed-1', 'one.txt');
    final second = _fileNode('trashed-2', 'two.txt');
    final repository =
        _RecyclePagedRepository()
          ..recyclePages[0] = [first]
          ..recyclePages[1] = [second]
          ..totalElements = 2;
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await controller.showRecycleBin(page: 1, size: 1);
    await controller.refreshFileNodesForCurrentSection();

    final state = container.read(fileBrowserControllerProvider).value!;
    // 按原页窗（页 1）重拉并同步 meta，不再全量拉取覆盖分页条口径。
    expect(state.recycleBin.map((file) => file.id), ['trashed-2']);
    expect(state.recycleMeta.page, 1);
    expect(state.recycleMeta.totalElements, 2);
    expect(repository.recyclePageRequests, [1, 1]);
    expect(repository.recycleFullListRequests, 0);
  });

  test('mutation refresh falls back when the last page is depleted', () async {
    final first = _fileNode('trashed-1', 'one.txt');
    final second = _fileNode('trashed-2', 'two.txt');
    final repository =
        _RecyclePagedRepository()
          ..recyclePages[0] = [first]
          ..recyclePages[1] = [second]
          ..totalElements = 2;
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await controller.showRecycleBin(page: 1, size: 1);
    // 末页唯一条目被删除：仅剩页 0。
    repository
      ..recyclePages.remove(1)
      ..totalElements = 1;

    await controller.refreshFileNodesForCurrentSection();

    final state = container.read(fileBrowserControllerProvider).value!;
    // 越界空页回退到新末页，分页条不停留在空页。
    expect(state.recycleBin.map((file) => file.id), ['trashed-1']);
    expect(state.recycleMeta.page, 0);
    expect(state.recycleMeta.totalElements, 1);
    expect(repository.recyclePageRequests, [1, 1, 0]);
  });

  test('shared space mutations use shared-space repository methods', () async {
    final file = _fileNode('shared-file', 'shared.txt');
    final repository =
        _FakeFileRepository()..sharedFilesByParent[null] = [file];
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);
    await controller.switchSpace('SHARED');

    await controller.createFolder('Shared Folder');
    await controller.renameFile(file, 'renamed.txt');
    await controller.deleteFile(file);

    expect(repository.createdSharedFolderNames, ['Shared Folder']);
    expect(repository.renamedSharedFileIds, ['shared-file']);
    expect(repository.deletedSharedFileIds, ['shared-file']);
    expect(repository.deletedFileIds, isEmpty);
  });

  test(
    'remote browse completion does not restore an obsolete section',
    () async {
      final browseCompleter = Completer<List<ExternalFileItem>>();
      final repository =
          _FakeFileRepository()
            ..externalAccounts = const [
              ExternalStorageAccount(
                id: 'storage-id',
                provider: 'S3',
                displayName: '家庭对象存储',
                status: 'ACTIVE',
              ),
            ]
            ..externalBrowseCompleter = browseCompleter;
      final container = ProviderContainer.test(
        overrides: [fileRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(fileBrowserControllerProvider.notifier);
      await container.read(fileBrowserControllerProvider.future);
      await controller.showExternalStorage();

      final browseFuture = controller.browseExternalStorage('storage-id');
      expect(
        container
            .read(fileBrowserControllerProvider)
            .value!
            .isExternalBrowseLoading,
        isTrue,
      );

      await controller.showFiles();
      browseCompleter.complete(const [
        ExternalFileItem(name: 'photos', path: '/photos', isDir: true),
      ]);
      await browseFuture;

      final state = container.read(fileBrowserControllerProvider).value!;
      expect(state.section, FileManagerSection.allFiles);
      expect(state.externalFiles, isEmpty);
      expect(state.isExternalBrowseLoading, isFalse);
      expect(state.isBusy, isFalse);
    },
  );

  test(
    'remote browse failure releases loading state and keeps navigation usable',
    () async {
      final repository =
          _FakeFileRepository()
            ..externalAccounts = const [
              ExternalStorageAccount(
                id: 'storage-id',
                provider: 'WEBDAV',
                displayName: '家庭网盘',
                status: 'ACTIVE',
              ),
            ]
            ..externalBrowseError = const AppException(
              code: 'EXTERNAL_STORAGE_INVALID',
              message: '外部存储参数无效',
            );
      final container = ProviderContainer.test(
        overrides: [fileRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(fileBrowserControllerProvider.notifier);
      await container.read(fileBrowserControllerProvider.future);
      await controller.showExternalStorage();

      await expectLater(
        controller.browseExternalStorage('storage-id'),
        throwsA(isA<AppException>()),
      );

      var state = container.read(fileBrowserControllerProvider).value!;
      expect(state.isExternalBrowseLoading, isFalse);
      expect(state.externalBrowseError, '外部存储参数无效');
      expect(state.isBusy, isFalse);

      await controller.showFiles();
      state = container.read(fileBrowserControllerProvider).value!;
      expect(state.section, FileManagerSection.allFiles);
    },
  );

  test('批量上传途中切换目录，排队文件仍写入发起时的目录', () async {
    final repository = _BatchFileRepository();
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await controller.openFolder(_folderNode('folder-1', '工作文档'));
    repository.policyGate = Completer<void>();
    final uploadFuture = controller.uploadFiles([
      XFile.fromData(Uint8List.fromList([1]), path: 'a.bin', name: 'a.bin'),
      XFile.fromData(Uint8List.fromList([2]), path: 'b.bin', name: 'b.bin'),
    ]);
    // 批次已开始、目标尚未定型时切换目录：排队文件不能跟着落进新目录。
    await repository.policyReached.future;
    await controller.openFolder(_folderNode('folder-2', '其他目录'));
    repository.policyGate!.complete();
    await uploadFuture;

    expect(repository.createdSessions.map((session) => session.parentId), [
      'folder-1',
      'folder-1',
    ]);
  });

  test('上传历史只保留最近 20 条终态任务', () async {
    final repository = _BatchFileRepository();
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await controller.uploadFiles([
      for (var index = 0; index < 25; index++)
        XFile.fromData(
          Uint8List.fromList([index]),
          path: 'f$index.bin',
          name: 'f$index.bin',
        ),
    ]);

    final tasks =
        container.read(fileBrowserControllerProvider).value!.localUploadTasks;
    final terminal = tasks.where((task) => task.isTerminal).toList();
    expect(terminal, hasLength(20));
    // 队尾的新任务是用户最关心的：裁剪必须丢最旧的，而不是刚完成的。
    expect(terminal.map((task) => task.fileName), contains('f24.bin'));
  });
}
