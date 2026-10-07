import 'package:omninest/core/search/scoped_search_registry.dart';
import 'package:omninest/features/music/application/music_scoped_search_source.dart';
import 'package:omninest/features/photos/application/photo_scoped_search_source.dart';
import 'package:omninest/features/search/application/file_scoped_search_source.dart';
import 'package:omninest/features/video/application/video_scoped_search_source.dart';

/// 组合根：把各模块提供的全局搜索来源登记进核心注册表。
///
/// 只有 app 层被允许同时看到所有业务模块；核心层与搜索页都不反向依赖模块，
/// 因此新增一档的内容来源时，只需在模块自己的 application 层实现
/// `ScopedSearchSource`，再回到这里登记一行。未登记的内容档在覆盖层里
/// 直接不出现，不预留空档。
void registerScopedSearchSources() {
  ScopedSearchRegistry.register(const VideoScopedSearchSource());
  ScopedSearchRegistry.register(const PhotoScopedSearchSource());
  ScopedSearchRegistry.register(const MusicScopedSearchSource());
  ScopedSearchRegistry.register(const FileScopedSearchSource());
}
