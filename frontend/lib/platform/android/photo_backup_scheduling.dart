// 照片备份调度门面：IO 平台接 WorkManager，Web 回落空实现。
export 'photo_backup_scheduling_stub.dart'
    if (dart.library.io) 'photo_backup_scheduling_io.dart';
