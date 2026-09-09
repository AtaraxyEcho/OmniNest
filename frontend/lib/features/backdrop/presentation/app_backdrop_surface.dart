import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_image.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_video_view.dart';

/// 应用级背景渲染层。
///
/// 图片素材三端统一走网络渲染;视频桌面/移动走 media_kit,Web 走 HTML video 适配器;
/// 内置壁纸在桌面/移动为本机文件、在 Web 为打包资产地址。
class AppBackdropSurface extends ConsumerWidget {
  const AppBackdropSurface({
    required this.asset,
    required this.settings,
    required this.policy,
    required this.active,
    super.key,
  });

  final AppBackdropAsset? asset;
  final AppBackdropSettings settings;
  final AppBackdropPolicy policy;
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
    final shouldBlur = settings.blurAmount > 0.05 && asset?.isVideo != true;
    final mediaLayer =
        shouldBlur
            ? ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: settings.blurAmount,
                sigmaY: settings.blurAmount,
              ),
              child: media,
            )
            : media;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Colors.transparent, child: mediaLayer),
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
    final source = asset.path;
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
      return AppBackdropVideoView(
        source: source,
        fit: fit,
        playing: active && motionAllowed,
        muted: settings.videoMuted,
        fallbackSource: bundledDefaultWallpaperWebAsset,
        onSourceStale: onSourceStale,
      );
    }
    if (!motionAllowed) {
      return _videoStaticFallback(context, ref, asset, fit);
    }
    return AppBackdropVideoView(
      source: source,
      fit: fit,
      playing: active,
      muted: settings.videoMuted,
      onSourceStale: onSourceStale,
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
      return AppBackdropImage(
        url: asset.path,
        cacheKey: 'backdrop:${asset.id}',
        fit: fit,
        alignment: alignment,
        // contain 时用模糊同图铺底,避免非 16:9 图出现大面积空白/“被拉伸”观感。
        blurPad: true,
        fallbackAsset: bundledDefaultWallpaperPosterAsset,
        onUrlFailed:
            () => Future<void>.microtask(() async {
              await ref
                  .read(appBackdropControllerProvider.notifier)
                  .ensureFreshServerUrls(force: true);
            }),
      );
    }
    // 内置素材当前为视频;非 server 图片不在此分支渲染。
    return const SizedBox.shrink();
  }

  Widget _videoStaticFallback(
    BuildContext context,
    WidgetRef ref,
    AppBackdropAsset asset,
    BoxFit fit,
  ) {
    final thumbnail = asset.thumbnailPath;
    if (asset.sourceType == AppBackdropSourceType.server &&
        thumbnail != null &&
        thumbnail.isNotEmpty) {
      return AppBackdropImage(
        url: thumbnail,
        cacheKey: 'backdrop-thumb:${asset.id}',
        fit: fit,
        onUrlFailed:
            () => Future<void>.microtask(() async {
              await ref
                  .read(appBackdropControllerProvider.notifier)
                  .ensureFreshServerUrls(force: true);
            }),
      );
    }
    if (asset.sourceType == AppBackdropSourceType.bundled) {
      return Image.asset(bundledDefaultWallpaperPosterAsset, fit: fit);
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
          colors: [Color(0xFF0A1821), Color(0xFF111927)],
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
