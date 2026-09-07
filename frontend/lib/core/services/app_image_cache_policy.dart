import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:omninest/core/utils/platform_helper.dart';

const _mebibyte = 1024 * 1024;

/// 应用级图片缓存目标平台。
enum AppImageCacheTarget { web, mobile, desktop, other }

/// 图片缓存条目和解码内存预算。
@immutable
class AppImageCacheBudget {
  /// 创建图片缓存预算。
  const AppImageCacheBudget({
    required this.maximumEntries,
    required this.maximumBytes,
  });

  /// 最多保留的缓存条目数。
  final int maximumEntries;

  /// 最多保留的解码图片字节数。
  final int maximumBytes;
}

/// 统一管理 Flutter 全局图片缓存的平台预算。
abstract final class AppImageCachePolicy {
  /// 返回当前运行平台对应的缓存目标。
  static AppImageCacheTarget resolveCurrentTarget() {
    if (isWebPlatform) {
      return AppImageCacheTarget.web;
    }
    if (isMobilePlatform) {
      return AppImageCacheTarget.mobile;
    }
    if (isDesktopPlatform) {
      return AppImageCacheTarget.desktop;
    }
    return AppImageCacheTarget.other;
  }

  /// 返回指定平台的图片缓存预算。
  static AppImageCacheBudget budgetFor(AppImageCacheTarget target) {
    switch (target) {
      case AppImageCacheTarget.web:
        return const AppImageCacheBudget(
          maximumEntries: 220,
          maximumBytes: 96 * _mebibyte,
        );
      case AppImageCacheTarget.mobile:
        return const AppImageCacheBudget(
          maximumEntries: 160,
          maximumBytes: 64 * _mebibyte,
        );
      case AppImageCacheTarget.desktop:
        // 桌面内存充裕；幻灯片/查看器按屏宽降采样后单张约 10-30MB，
        // 预算过小会让邻居预取互相驱逐、每次切换重新解码（表现为闪烁）。
        return const AppImageCacheBudget(
          maximumEntries: 320,
          maximumBytes: 384 * _mebibyte,
        );
      default:
        return const AppImageCacheBudget(
          maximumEntries: 160,
          maximumBytes: 64 * _mebibyte,
        );
    }
  }

  /// 将当前平台预算应用到指定的 Flutter 图片缓存。
  static void configure(ImageCache cache, {AppImageCacheTarget? target}) {
    final budget = budgetFor(target ?? resolveCurrentTarget());
    cache.maximumSize = budget.maximumEntries;
    cache.maximumSizeBytes = budget.maximumBytes;
  }
}
