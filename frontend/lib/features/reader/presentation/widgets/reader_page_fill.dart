import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';

/// 首屏至少要凑够这么多项才认为填满了滚动视口。
///
/// 取一个封面栅格两行的量：再多就是白拉分页，更少则首屏明显空。
const int readerPageFillThreshold = 12;

/// 可见条目不足一屏且服务端还有下一页时，继续往后拉分页。
///
/// 书架是从书库的已加载分页里过滤出来的：书库前 50 本只有 2 本在书架时，书架只渲染
/// 这 2 项，内容高度撑不满视口就永远不会触发触底加载，排在第 51 本之后的书架书
/// 在书架页永远看不到。分段与关键词已下沉服务端查询参数，同一条补页通道继续为
/// 书库页与管理页兜住"一屏都填不满"的首帧。
void scheduleReaderPageFill(
  WidgetRef ref, {
  required int visibleCount,
  required bool hasMore,
  required bool isLoadingMore,
}) {
  if (visibleCount >= readerPageFillThreshold || !hasMore || isLoadingMore) {
    return;
  }
  // 控制器是应用级 Provider，取到的实例在页面之后仍然有效；先把 notifier 取在
  // 同步段里，回调内不再碰 ref。
  final controller = ref.read(readerCenterControllerProvider.notifier);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(controller.loadMoreItems());
  });
}
