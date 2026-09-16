import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';

String localizedFileUploadTaskMessage(
  FileUploadClientTask task,
  AppLocalizations l10n,
) {
  return switch (task.messageCode) {
    FileUploadTaskMessageCode.waiting => l10n.filesWaitingUpload,
    FileUploadTaskMessageCode.directUploading => l10n.filesDirectUploading,
    FileUploadTaskMessageCode.multipartUploading =>
      l10n.filesMultipartUploading,
    FileUploadTaskMessageCode.pausePending => l10n.filesUploadPausePending,
    FileUploadTaskMessageCode.paused => l10n.filesUploadPausedMsg,
    FileUploadTaskMessageCode.resuming => l10n.filesResumingUpload,
    FileUploadTaskMessageCode.completed => l10n.filesUploadDone,
    FileUploadTaskMessageCode.scanPending => l10n.filesUploadScanPending,
    FileUploadTaskMessageCode.conflict => l10n.filesConflictMsg(
      task.messageArgument ?? task.fileName,
    ),
    FileUploadTaskMessageCode.partCompleted => l10n.filesUploadedParts(
      task.messageCurrent ?? 0,
      task.messageTotal ?? 0,
    ),
    FileUploadTaskMessageCode.retrying => l10n.filesUploadRetrying,
    FileUploadTaskMessageCode.failed => task.message ?? l10n.filesStatusFailed,
    _ => task.message ?? '',
  };
}
