import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/files/domain/file_operation.dart';
import 'package:omninest/features/files/domain/file_upload_complete_result.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

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
    repository.firstUploadResult.complete('etag-1');
    await uploadFuture;

    final pausedTask =
        container
            .read(fileBrowserControllerProvider)
            .value!
            .localUploadTasks
            .single;
    expect(pausedTask.status, 'PAUSED');
    expect(pausedTask.uploadedBytes, 3);
    expect(repository.uploadedPartUrls, ['http://minio/part-1']);
    expect(repository.completedPartNumbers, [1]);

    final resumeFuture = controller.resumeLocalUploadTask(pausedTask.id);
    await repository.secondUploadStarted.future;
    repository.secondUploadResult.complete('etag-2');
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
    ]);
    expect(repository.completedPartNumbers, [1, 2]);
    expect(repository.completedSessions, ['upload-123']);
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
      repository.firstUploadResult.complete('etag-1');
      await uploadFuture;

      final requestCountBeforeResume = repository.personalPageRequests.length;
      final resumeFuture = controller.resumeLocalUploadTask(task.id);
      await repository.secondUploadStarted.future;
      repository.secondUploadResult.complete('etag-2');
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

  test('canceling offline download marks task as canceled', () async {
    final repository =
        _FakeFileRepository()
          ..offlineTasks = [
            const OfflineDownloadTask(
              id: 'offline-id',
              sourceUri: 'https://example.com/movie.mp4',
              status: 'QUEUED',
            ),
          ];
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);
    await controller.showOfflineDownloads();

    await controller.cancelOfflineDownload(repository.offlineTasks.single);

    expect(repository.cancelledOfflineDownloads, ['offline-id']);
    expect(
      container
          .read(fileBrowserControllerProvider)
          .value!
          .offlineTasks
          .single
          .status,
      'CANCELLED',
    );
  });

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
    expect(failedState.lastActionError?.message, 'FILE_QUOTA_EXCEEDED');
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

  test('file pagination appends the next page without duplicates', () async {
    final first = _fileNode('file-1', 'one.txt');
    final second = _fileNode('file-2', 'two.txt');
    final repository =
        _FakeFileRepository()
          ..personalFilesByPage[0] = [first]
          ..personalFilesByPage[1] = [first, second];
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(fileBrowserControllerProvider.notifier);
    await container.read(fileBrowserControllerProvider.future);

    await controller.loadMoreFiles();

    final files = container.read(fileBrowserControllerProvider).value!.files;
    expect(files.map((file) => file.id), ['file-1', 'file-2']);
    expect(repository.personalPageRequests, [0, 1]);
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
      expect(state.externalBrowseError, 'EXTERNAL_STORAGE_INVALID');
      expect(state.isBusy, isFalse);

      await controller.showFiles();
      state = container.read(fileBrowserControllerProvider).value!;
      expect(state.section, FileManagerSection.allFiles);
    },
  );
}

class _FakeFileRepository implements FileRepository {
  List<FileUploadQueueItem> uploadQueue = const [];
  List<OfflineDownloadTask> offlineTasks = const [];
  List<ExternalStorageAccount> externalAccounts = const [];
  List<ExternalFileItem> externalFiles = const [];
  List<FileNode> recycleBin = const [];
  final purgedFileIds = <String>[];
  final batchPurgedFileIds = <String>[];
  final uploadedPartUrls = <String>[];
  final completedPartNumbers = <int>[];
  final completedSessions = <String>[];
  final cancelledUploadSessions = <String>[];
  final cancelledOfflineDownloads = <String>[];
  final deletedFileIds = <String>[];
  final deletedSharedFileIds = <String>[];
  final createdSharedFolderNames = <String>[];
  final renamedSharedFileIds = <String>[];
  final deletedExternalPaths = <String>[];
  final renamedExternalPaths = <String>[];
  final sharedFilesByParent = <String?, List<FileNode>>{};
  final sharedParentRequests = <String?>[];
  final personalFilesByPage = <int, List<FileNode>>{};
  final personalPageRequests = <int>[];
  final firstUploadStarted = Completer<void>();
  final secondUploadStarted = Completer<void>();
  final firstUploadResult = Completer<String>();
  final secondUploadResult = Completer<String>();
  Completer<void>? deleteFileCompleter;
  Completer<void>? deleteExternalFileCompleter;
  Completer<List<ExternalFileItem>>? externalBrowseCompleter;
  Object? deleteFileError;
  Object? externalBrowseError;

  @override
  Future<List<FileNode>> listFiles({
    String? parentId,
    String? category,
  }) async => const [];

  @override
  Future<FileNodePage> listFilesPage({
    String? parentId,
    String? category,
    int page = 0,
    int size = 100,
  }) async {
    personalPageRequests.add(page);
    final files = personalFilesByPage[page] ?? const [];
    final totalElements =
        personalFilesByPage.values
            .expand((items) => items)
            .map((file) => file.id)
            .toSet()
            .length;
    return FileNodePage(
      items: files,
      page: page,
      size: size,
      totalElements: totalElements,
      totalPages: personalFilesByPage.isEmpty ? 0 : personalFilesByPage.length,
    );
  }

  @override
  Future<FileStorageStats> storageStats() async => const FileStorageStats(
    totalFiles: 0,
    totalFolders: 0,
    usedBytes: 0,
    quotaStatus: 'NORMAL',
    quotaBytes: 1024,
    typeDistribution: [],
  );

  @override
  Future<List<FileUploadQueueItem>> listUploadQueue() async => uploadQueue;

  @override
  Future<FileUploadSession> createUploadSession({
    String? parentId,
    required String fileName,
    required int sizeBytes,
    String? mimeType,
    String? sha256,
    int? partSizeBytes,
    String? spaceType,
    String? asVersionOfFileId,
  }) async {
    return const FileUploadSession(
      id: 'session-id',
      uploadId: 'upload-123',
      parentId: null,
      fileName: 'large.bin',
      sizeBytes: 6,
      partSizeBytes: 3,
      totalParts: 2,
      mimeType: 'application/octet-stream',
      status: 'CREATED',
      bucket: 'files',
      objectKey: 'users/1/large.bin',
      uploadUrl: 'http://minio/part-1',
      parts: [
        FileUploadPart(
          partNumber: 1,
          sizeBytes: 3,
          status: 'PENDING',
          uploadUrl: 'http://minio/part-1',
        ),
        FileUploadPart(
          partNumber: 2,
          sizeBytes: 3,
          status: 'PENDING',
          uploadUrl: 'http://minio/part-2',
        ),
      ],
      expiresAt: null,
    );
  }

  @override
  Future<String> putUploadUrl({
    required String uploadUrl,
    required Stream<List<int>> data,
    required int contentLength,
    FileUploadCancellationToken? cancellationToken,
    FileUploadProgressCallback? onProgress,
  }) {
    uploadedPartUrls.add(uploadUrl);
    if (uploadedPartUrls.length == 1) {
      firstUploadStarted.complete();
      return firstUploadResult.future;
    }
    secondUploadStarted.complete();
    return secondUploadResult.future;
  }

  @override
  Future<void> completeUploadPart({
    required String uploadId,
    required int partNumber,
    required String eTag,
  }) async {
    completedPartNumbers.add(partNumber);
  }

  @override
  Future<FileUploadCompleteResult> completeUploadSession({
    required String sessionId,
    String? sha256,
    String? asVersionOfFileId,
  }) async {
    completedSessions.add(sessionId);
    return const FileUploadCompleteResult(
      uploadId: 'upload-1',
      status: 'SCANNING',
    );
  }

  @override
  Future<void> cancelUploadSession(String uploadId) async {
    cancelledUploadSessions.add(uploadId);
    uploadQueue =
        uploadQueue.where((item) => item.uploadId != uploadId).toList();
  }

  @override
  Future<FileNode> addFavorite(String fileId) => throw UnimplementedError();

  @override
  Future<void> cancelOfflineDownload(String taskId) async {
    cancelledOfflineDownloads.add(taskId);
    offlineTasks =
        offlineTasks
            .map(
              (task) =>
                  task.id == taskId ? task.copyWith(status: 'CANCELLED') : task,
            )
            .toList();
  }

  @override
  Future<ExternalStorageAccount> createExternalStorage({
    required String provider,
    required String displayName,
    required String encryptedCredentials,
  }) => throw UnimplementedError();

  @override
  Future<FileNode> createFolder({String? parentId, required String name}) =>
      throw UnimplementedError();

  @override
  Future<OfflineDownloadTask> createOfflineDownload({
    required String sourceUri,
    String? targetParentId,
  }) => throw UnimplementedError();

  @override
  Future<FileShareLink> createShareLink({
    required String resourceId,
    String resourceType = 'FILE',
    String? password,
    bool generatePassword = false,
    DateTime? expiresAt,
    int? maxAccessCount,
  }) => throw UnimplementedError();

  @override
  Future<FileSharePreview> previewShare(String token, {String? password}) =>
      throw UnimplementedError();

  @override
  Future<void> acceptShare(
    String token, {
    String? password,
    String? targetParentId,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteFile(String fileId) async {
    deletedFileIds.add(fileId);
    final error = deleteFileError;
    if (error != null) {
      throw error;
    }
    final completer = deleteFileCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<FileNode> moveFile({
    required String fileId,
    required String parentId,
  }) => throw UnimplementedError();

  @override
  Future<FileNode> copyFile({required String fileId, String? targetParentId}) =>
      throw UnimplementedError();

  @override
  Future<List<FileVersion>> listFileVersions(String fileId) =>
      throw UnimplementedError();

  @override
  Future<FileNode> restoreFileVersion({
    required String fileId,
    required String versionId,
  }) => throw UnimplementedError();

  @override
  Future<String> downloadUrl(String fileId) => throw UnimplementedError();

  @override
  Future<String> loadTextPreview(String fileId) => throw UnimplementedError();

  @override
  Future<void> disableExternalStorage(String accountId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteExternalStorage(String accountId) =>
      throw UnimplementedError();

  @override
  Future<ExternalStorageAccount> updateExternalStorage({
    required String accountId,
    required String displayName,
    required String encryptedCredentials,
  }) => throw UnimplementedError();

  @override
  Future<List<ExternalStorageAccount>> listExternalStorages() =>
      Future.value(externalAccounts);

  @override
  Future<List<FileNode>> listFavoriteFiles() => throw UnimplementedError();

  @override
  Future<List<FileShareLink>> listMyShares() => throw UnimplementedError();

  @override
  Future<List<OfflineDownloadTask>> listOfflineDownloads() async =>
      offlineTasks;

  @override
  Future<List<FileNode>> listRecentFiles() => throw UnimplementedError();

  @override
  Future<List<FileNode>> listRecycleBin({
    String spaceType = 'PERSONAL',
  }) async => recycleBin;

  @override
  Future<List<FileShareLink>> listShareLinks() => throw UnimplementedError();

  @override
  Future<List<SharedFileItem>> listSharedWithMe() => throw UnimplementedError();

  @override
  Future<TaskSubmission> purgeFile(String fileId) async {
    purgedFileIds.add(fileId);
    return const TaskSubmission(taskId: 'purge-task', status: 'QUEUED');
  }

  @override
  Future<void> removeFavorite(String fileId) => throw UnimplementedError();

  @override
  Future<FileNode> renameFile({required String fileId, required String name}) =>
      throw UnimplementedError();

  @override
  Future<FileNode> restoreFile(String fileId) => throw UnimplementedError();

  @override
  Future<void> revokeShare(String shareId) => throw UnimplementedError();

  @override
  Future<FileUploadPolicy> uploadPolicy() async => const FileUploadPolicy(
    directUploadMaxBytes: 64 * 1024 * 1024,
    defaultPartSizeBytes: 10 * 1024 * 1024,
    maxPartSizeBytes: 100 * 1024 * 1024,
    maxTotalParts: 1000,
    maxConcurrentParts: 4,
  );

  @override
  Future<List<ExternalFileItem>> browseExternalStorage(
    String accountId,
    String path,
  ) async {
    final error = externalBrowseError;
    if (error != null) {
      throw error;
    }
    final completer = externalBrowseCompleter;
    if (completer != null) {
      return completer.future;
    }
    return externalFiles;
  }

  @override
  Future<ImportTask> createImportTask(
    String accountId, {
    required String sourcePath,
    required String sourceKind,
    String? targetParentId,
    String? spaceType,
    String? asVersionOfFileId,
  }) => throw UnimplementedError();

  @override
  Future<List<ImportTask>> listImportTasks() => throw UnimplementedError();

  @override
  Future<void> cancelImportTask(String taskId) => throw UnimplementedError();

  @override
  Future<List<FileNode>> batchDeleteFiles(List<String> fileIds) =>
      throw UnimplementedError();

  @override
  Future<List<FileNode>> batchRestoreFiles(List<String> fileIds) =>
      throw UnimplementedError();

  @override
  Future<TaskSubmission> batchPurgeFiles(List<String> fileIds) async {
    batchPurgedFileIds.addAll(fileIds);
    return const TaskSubmission(taskId: 'purge-batch-task', status: 'QUEUED');
  }

  @override
  Future<List<FileNode>> batchMoveFiles(
    List<String> fileIds,
    String parentId,
  ) => throw UnimplementedError();

  @override
  Future<List<FileNode>> batchAddFavorites(List<String> fileIds) =>
      throw UnimplementedError();

  @override
  Future<void> batchRemoveFavorites(List<String> fileIds) =>
      throw UnimplementedError();

  @override
  Future<ExternalSpaceUsage> getExternalStorageSpace(String accountId) =>
      Future.value(
        const ExternalSpaceUsage(
          totalBytes: 100,
          usedBytes: 25,
          freeBytes: 75,
          trashedBytes: 0,
        ),
      );

  @override
  Future<void> mkdirExternalStorage(String accountId, String remotePath) =>
      throw UnimplementedError();

  @override
  Future<void> deleteExternalFile(String accountId, String remotePath) async {
    deletedExternalPaths.add(remotePath);
    final completer = deleteExternalFileCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<void> renameExternalFile(
    String accountId, {
    required String oldPath,
    required String newName,
  }) async {
    renamedExternalPaths.add('$oldPath->$newName');
  }

  // 共享空间相关方法
  @override
  Future<List<FileNode>> listSharedSpaceFiles({String? parentId}) async {
    sharedParentRequests.add(parentId);
    return sharedFilesByParent[parentId] ?? const [];
  }

  @override
  Future<FileNodePage> listSharedSpaceFilesPage({
    String? parentId,
    int page = 0,
    int size = 100,
  }) async {
    sharedParentRequests.add(parentId);
    final files = sharedFilesByParent[parentId] ?? const [];
    return FileNodePage(
      items: files,
      page: page,
      size: size,
      totalElements: files.length,
      totalPages: files.isEmpty ? 0 : 1,
    );
  }

  @override
  Future<FileNode> createSharedFolder({
    String? parentId,
    required String name,
  }) async {
    createdSharedFolderNames.add(name);
    return _folderNode('created-shared-folder', name);
  }

  @override
  Future<FileNode> renameSharedFile({
    required String fileId,
    required String name,
  }) async {
    renamedSharedFileIds.add(fileId);
    return _fileNode(fileId, name);
  }

  @override
  Future<void> moveToSharedSpace(String fileId) => throw UnimplementedError();

  @override
  Future<void> moveToPersonalSpace(String fileId) => throw UnimplementedError();

  @override
  Future<void> deleteSharedFile(String fileId) async {
    deletedSharedFileIds.add(fileId);
  }

  @override
  Future<SharedSpaceUsage> getSharedSpaceUsage() async =>
      const SharedSpaceUsage(usedBytes: 0, maxBytes: -1, fileCount: 0);
}

class _BatchFileRepository extends _FakeFileRepository {
  final List<String> directUploadNames = [];
  int _uploadCallCount = 0;

  @override
  Future<FileUploadSession> createUploadSession({
    String? parentId,
    required String fileName,
    required int sizeBytes,
    String? mimeType,
    String? sha256,
    int? partSizeBytes,
    String? spaceType,
    String? asVersionOfFileId,
  }) async {
    return FileUploadSession(
      id: 'session-$fileName',
      uploadId: 'upload-$fileName',
      parentId: parentId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      partSizeBytes: sizeBytes,
      totalParts: 1,
      mimeType: mimeType ?? 'application/octet-stream',
      status: 'CREATED',
      bucket: 'files',
      objectKey: 'users/1/$fileName',
      uploadUrl: 'http://upload/$fileName',
      parts: const [],
      expiresAt: null,
    );
  }

  @override
  Future<String> putUploadUrl({
    required String uploadUrl,
    required Stream<List<int>> data,
    required int contentLength,
    FileUploadCancellationToken? cancellationToken,
    FileUploadProgressCallback? onProgress,
  }) async {
    final fileName = Uri.parse(uploadUrl).pathSegments.last;
    directUploadNames.add(fileName);
    _uploadCallCount += 1;
    if (_uploadCallCount == 1) {
      throw StateError('upload failed');
    }
    onProgress?.call(contentLength, contentLength);
    return 'etag-$fileName';
  }
}

FileNode _folderNode(String id, String name) {
  return FileNode(
    id: id,
    parentId: null,
    name: name,
    isFolder: true,
    nodeType: 'FOLDER',
    normalizedPath: '/$name',
    sizeBytes: 0,
    updatedAt: DateTime.parse('2026-05-21T12:00:00Z'),
  );
}

FileNode _fileNode(String id, String name) {
  return FileNode(
    id: id,
    parentId: null,
    name: name,
    isFolder: false,
    nodeType: 'FILE',
    normalizedPath: '/$name',
    mimeType: 'application/octet-stream',
    sizeBytes: 6,
    updatedAt: DateTime.parse('2026-05-21T12:00:00Z'),
  );
}
