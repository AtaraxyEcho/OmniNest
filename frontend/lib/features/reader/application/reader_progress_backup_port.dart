/// 阅读进度平台备份端口的应用层出口。
///
/// 实现是 localStorage 适配器，归 data 层；presentation 只经这一层取用，
/// 页面里不出现 `data/` 直接依赖（见 test/architecture/feature_dependency_boundary_test.dart）。
library;

export 'package:omninest/features/reader/data/reader_progress_backup.dart'
    show ReaderProgressBackupWeb;
