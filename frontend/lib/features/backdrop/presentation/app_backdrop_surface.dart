import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_image.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_video_view.dart';
import 'package:omninest/features/backdrop/presentation/bundled_wallpaper_poster.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/app/theme/backdrop_scrim_colors.dart';

/// 应用级背景渲染层。
///
/// 图片素材三端统一走网络渲染;视频桌面/移动走 media_kit,Web 走 HTML video 适配器;
/// 内置默认壁纸是随包分发的视频,封面帧(打包静图)始终垫在视频层之下。
class AppBackdropSurface extends ConsumerWidget {
  const AppBackdropSurface({
    required this.asset,
    required this.settings,
    required this.policy,
    required this.environmentBlurSigma,
    required this.active,
    super.key,
  });

  final AppBackdropAsset? asset;
  final AppBackdropSettings settings;
  final AppBackdropPolicy policy;

  /// 环境模式折算后的壁纸模糊 sigma，必须由宿主按壳层形态给出。
  ///
  /// 桌面端传 0：`policy.environmentMode` 是移动壳层档位语义，桌面直接消费
  /// 它会给实底前景页（如 `/reader` 的 staticContent=focus 档 sigma 28）压上
  /// 一层全屏 `ImageFilter.blur`，深色前景与该模糊层合成时沿边界出现对角亮缝。
  final double environmentBlurSigma;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BoxFit fit = switch (settings.fit) {
      AppBackdropFit.cover => BoxFit.cover,
      AppBackdropFit.contain => BoxFit.contain,
      AppBackdropFit.fill => BoxFit.fill,
    };
    final alignment = switch (settings.alignment) {
      AppBackdropAlignment.top => Alignment.topCenter,
      AppBackdropAlignment.center => Alignment.center,
      AppBackdropAlignment.bottom => Alignment.bottomCenter,
    };
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final motionAllowed = policy.motionAllowed && !animationsDisabled;
    final media = _buildMedia(
      context,
      ref,
      asset,
      fit,
      alignment,
      motionAllowed,
    );
    // 宿主折算的环境模糊与用户设置取较大值；
    // 视频不做全屏实时模糊（成本过高），存在感由宿主遮罩与不透明度承担。
    final environmentSigma =
        asset?.isVideo == true ? 0.0 : environmentBlurSigma;
    final userBlur = settings.blurAmount;
    final shouldBlur =
        (userBlur > 0.05 || environmentSigma > 0.05) && asset?.isVideo != true;
    // 全屏 ImageFilter.blur 随窗口面积线性变贵;壁纸模糊上限收敛,
    // 观感差异有限,可明显降低最大化/全屏时的 GPU 合成压力。
    final blurSigma =
        shouldBlur
            ? (userBlur > environmentSigma ? userBlur : environmentSigma).clamp(
              0.0,
              28.0,
            )
            : 0.0;
    // 只对静态图片做交叉溶解：交叉层放在 ImageFiltered 内部，避免
    // 两张 4K 图各自高斯模糊造成双倍合成成本；视频是单实例播放器，
    // 换 Key 会让新旧纹理争抢表面并黑屏，固定 Key 跳过溶解。
    final animatedMedia =
        asset?.isVideo == true
            ? media
            : AnimatedSwitcher(
              duration: MotionToken.reduced(
                context,
                const Duration(milliseconds: 300),
              ),
              switchInCurve: MotionToken.curve,
              switchOutCurve: MotionToken.curveIn,
              child: KeyedSubtree(
                key: ValueKey<String>(asset?.id ?? 'none'),
                // AnimatedSwitcher 默认 layoutBuilder 是 StackFit.loose 的
                // Stack：松约束下 Image 按固有像素排版，BoxFit 不参与，
                // 宽视口里 cover/fill 都会退化成 letterbox（左右露出舞台
                // 底色）。背景容器必须永远等于宿主，缩放语义只由 BoxFit
                // 承担，因此这里显式拉满。
                child: SizedBox.expand(child: media),
              ),
            );
    final mediaLayer =
        shouldBlur
            ? ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: animatedMedia,
            )
            : animatedMedia;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              mediaLayer,
              if (settings.dimAmount > 0.01)
                ColoredBox(
                  color: Colors.black.withValues(alpha: settings.dimAmount),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMedia(
    BuildContext context,
    WidgetRef ref,
    AppBackdropAsset? asset,
    BoxFit fit,
    Alignment alignment,
    bool motionAllowed,
  ) {
    if (asset == null || asset.missing) {
      return const _AppBackdropFallback();
    }
    if (asset.isVideo) {
      return _buildVideo(context, ref, asset, fit, motionAllowed);
    }
    return _buildImage(context, ref, asset, fit, alignment);
  }

  Widget _buildVideo(
    BuildContext context,
    WidgetRef ref,
    AppBackdropAsset asset,
    BoxFit fit,
    bool motionAllowed,
  ) {
    // 优先本机缓存(原片落盘),无缓存时用签名 URL 边下边播。
    final source =
        (asset.localVideoPath != null && asset.localVideoPath!.isNotEmpty)
            ? asset.localVideoPath!
            : asset.path;
    if (source.isEmpty) {
      return const _AppBackdropFallback(icon: Icons.movie_creation_outlined);
    }
    void onSourceStale() {
      Future<void>.microtask(() async {
        await ref
            .read(appBackdropControllerProvider.notifier)
            .ensureFreshServerUrls(force: true);
      });
    }

    if (isWebPlatform) {
      // HTML video 在首帧就绪或加载失败前不绘制内容；与 IO 端一致在
      // 底层保留静态海报（平台视图之下的画布内容仍按层级合成），避免黑闪。
      // 海报只跟随素材自身：自定义视频失败时用它自己的缩略图，绝不回退内置默认视频。
      return Stack(
        fit: StackFit.expand,
        children: [
          _videoStaticFallback(context, ref, asset, fit),
          AppBackdropVideoView(
            source: source,
            fit: fit,
            playing: active && motionAllowed,
            muted: settings.videoMuted,
            onSourceStale: onSourceStale,
            codecUnsupported: asset.isWebPlaybackUnsupported,
          ),
        ],
      );
    }
    // Keep the video layer mounted even when motion is disallowed. Unmounting
    // Video forces a full reopen on the next visible frame (black flash).
    // Poster stays underneath for open failure / not-ready cases.
    return Stack(
      fit: StackFit.expand,
      children: [
        _videoStaticFallback(context, ref, asset, fit),
        AppBackdropVideoView(
          source: source,
          fit: fit,
          playing: active && motionAllowed,
          muted: settings.videoMuted,
          onSourceStale: onSourceStale,
        ),
      ],
    );
  }

  Widget _buildImage(
    BuildContext context,
    WidgetRef ref,
    AppBackdropAsset asset,
    BoxFit fit,
    Alignment alignment,
  ) {
    if (asset.sourceType == AppBackdropSourceType.server) {
      final blurActive =
          settings.blurAmount > 0.05 || environmentBlurSigma > 0.05;
      final thumbnail =
          asset.thumbnailPath?.isNotEmpty == true ? asset.thumbnailPath : null;
      return AppBackdropImage(
        // 稳定 Key:父级重建时不重挂 State,避免加载态闪帧。
        key: ValueKey<String>('backdrop-image:${asset.id}'),
        url: asset.path,
        cacheKey: 'backdrop:${asset.id}',
        fit: fit,
        alignment: alignment,
        // contain 时用模糊同图铺底,避免非 16:9 图出现大面积空白/“被拉伸”观感。
        blurPad: true,
        // 自定义壁纸禁止用默认壁纸海报做加载占位,否则全屏会闪错误壁纸。
        // 仅在 URL 彻底失败且无备用地址时由组件内部显示深色底。
        fallbackAsset: null,
        maxDecodeWidth: blurActive ? 1440 : null,
        // 首切即时反馈:瓦片缩略图(与瓦片预览同缓存键,磁盘已缓存)
        // 先行垫底,主图签名 URL 取回解码后无缝淡入覆盖。
        previewUrl: thumbnail,
        previewCacheKey: 'backdrop-preview:${asset.id}',
        onUrlFailed:
            () => Future<void>.microtask(() async {
              await ref
                  .read(appBackdropControllerProvider.notifier)
                  .ensureFreshServerUrls(force: true);
            }),
      );
    }
    if (asset.sourceType == AppBackdropSourceType.bundled) {
      // 内置素材已是视频，走到这里只可能是历史行（v2 图片档）。封面帧就是同一段
      // 素材的首帧，直接垫上比露错误底纹更接近预期；下一个启动周期的
      // ensureBundledBackdrop 会用新元数据覆盖这一行。
      return BundledWallpaperPoster(
        key: const ValueKey<String>('backdrop-bundled-poster'),
        fit: fit,
        alignment: alignment,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _videoStaticFallback(
    BuildContext context,
    WidgetRef ref,
    AppBackdropAsset asset,
    BoxFit fit,
  ) {
    if (asset.sourceType == AppBackdropSourceType.bundled) {
      // 视频首帧就绪前与播放失败后都垫封面帧，避免默认壁纸位置露出舞台底色。
      return BundledWallpaperPoster(
        key: const ValueKey<String>('backdrop-bundled-poster'),
        fit: fit,
      );
    }
    final thumbnail = asset.thumbnailPath;
    if (asset.sourceType == AppBackdropSourceType.server &&
        thumbnail != null &&
        thumbnail.isNotEmpty) {
      return AppBackdropImage(
        key: ValueKey<String>('backdrop-thumb:${asset.id}'),
        url: thumbnail,
        cacheKey: 'backdrop-thumb:${asset.id}',
        fit: fit,
        // 自定义视频壁纸:海报垫底也不得闪默认壁纸。
        fallbackAsset: null,
        onUrlFailed:
            () => Future<void>.microtask(() async {
              await ref
                  .read(appBackdropControllerProvider.notifier)
                  .ensureFreshServerUrls(force: true);
            }),
      );
    }
    return const _AppBackdropFallback(icon: Icons.movie_creation_outlined);
  }
}

class _AppBackdropFallback extends StatelessWidget {
  const _AppBackdropFallback({this.icon = Icons.landscape_outlined});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BackdropStageColors.surfaceStart,
            BackdropStageColors.surfaceEnd,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.34),
          size: 64,
        ),
      ),
    );
  }
}
