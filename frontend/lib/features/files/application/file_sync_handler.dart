import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_scope_handler.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/application/file_download_url_provider.dart';
import 'package:omninest/features/files/application/share_link_controller.dart';

/// 文件作用域实时失效刷新处理器。
class FileSyncHandler implements RealtimeScopeHandler {
  FileSyncHandler(this.ref);

  final Ref ref;
  final RealtimeRevisionTracker _auxiliaryRevisions = RealtimeRevisionTracker();

  @override
  RealtimeScope get scope => RealtimeScope.files;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) => true;

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) async {
    final auxiliary = _auxiliaryRevisions.pending(invalidations);
    if (auxiliary.isNotEmpty && ref.exists(fileStorageStatsProvider)) {
      final _ = await ref.refresh(fileStorageStatsProvider.future);
    }
    for (final invalidation in auxiliary) {
      final resourceId = invalidation.resourceId;
      if (resourceId == null) continue;
      final provider = fileDownloadUrlProvider(resourceId);
      if (ref.exists(provider)) {
        final _ = await ref.refresh(provider.future);
      }
    }
    if (auxiliary.isNotEmpty && ref.exists(myShareLinksProvider)) {
      await ref.read(myShareLinksProvider.notifier).load();
    }
    _auxiliaryRevisions.markCompleted(auxiliary);
    if (!ref.exists(fileBrowserControllerProvider)) return false;
    await ref.read(fileBrowserControllerProvider.future);
    await ref.read(fileBrowserControllerProvider.notifier).refreshForRealtime();
    _auxiliaryRevisions.clear(invalidations);
    return true;
  }
}

/// 文件导入任务实时失效刷新处理器。
class FileTaskSyncHandler implements RealtimeScopeHandler {
  FileTaskSyncHandler(this.ref);

  final Ref ref;

  @override
  RealtimeScope get scope => RealtimeScope.tasks;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) {
    return invalidation.resourceType == '*' ||
        invalidation.resourceType == 'TASK_EXTERNAL_IMPORT' ||
        invalidation.resourceType == 'TASK_OFFLINE_DOWNLOAD';
  }

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) async {
    if (!ref.exists(fileBrowserControllerProvider)) return false;
    await ref.read(fileBrowserControllerProvider.future);
    final section =
        ref.read(fileBrowserControllerProvider).asData?.value.section;
    final notifier = ref.read(fileBrowserControllerProvider.notifier);
    if (section == FileManagerSection.offlineDownloads) {
      await notifier.showOfflineDownloads();
      return true;
    }
    return notifier.refreshImportTasksForRealtime();
  }
}
