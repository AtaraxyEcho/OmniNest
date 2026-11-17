export 'package:omninest/features/portal/presentation/widgets/portal_media_thumbnail.dart';

/// Portal 对外暴露的表现层能力门面。
///
/// 跨 feature 复用（如 Library 媒体空间的缩略图渲染）只允许经由本
/// 门面导入，避免直接依赖 portal 内部表现层路径。
