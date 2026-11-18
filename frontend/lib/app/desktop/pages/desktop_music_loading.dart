part of 'desktop_music_page.dart';

/// 首次取曲库数据时保留当前分区的内容结构，避免空列表先闪成空态。
class _MusicLoadingSkeleton extends StatelessWidget {
  const _MusicLoadingSkeleton({required this.tab});

  final DesktopMusicTab tab;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      DesktopMusicTab.home => const _MusicHomeSkeleton(),
      DesktopMusicTab.tracks ||
      DesktopMusicTab.favorites => const _MusicTracksSkeleton(),
      DesktopMusicTab.albums ||
      DesktopMusicTab.playlists => const _MusicGridSkeleton(),
    };
  }
}

class _MusicHomeSkeleton extends StatelessWidget {
  const _MusicHomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 350,
          child: Row(
            children: [
              const SizedBox(
                width: 280,
                height: 280,
                child: DesktopSkeletonBox(radius: 16),
              ),
              const SizedBox(width: 40),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DesktopSkeletonBox(width: 132, height: 11),
                    const SizedBox(height: 14),
                    const FractionallySizedBox(
                      widthFactor: 0.68,
                      alignment: Alignment.centerLeft,
                      child: DesktopSkeletonBox(height: 48, radius: 12),
                    ),
                    const SizedBox(height: 12),
                    const DesktopSkeletonBox(width: 220, height: 14),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        const DesktopSkeletonBox(width: 88, height: 38),
                        const SizedBox(width: 10),
                        const DesktopSkeletonBox(width: 132, height: 38),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const DesktopSkeletonBox(width: 82, height: 10),
        const SizedBox(height: 7),
        const DesktopSkeletonBox(width: 140, height: 24),
        const SizedBox(height: 18),
        const _MusicGridSkeleton(),
      ],
    );
  }
}

class _MusicTracksSkeleton extends StatelessWidget {
  const _MusicTracksSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const DesktopSkeletonBox(width: 250, height: 36),
            const SizedBox(width: 12),
            const DesktopSkeletonBox(width: 90, height: 32),
            const Spacer(),
            const DesktopSkeletonBox(width: 120, height: 32),
          ],
        ),
        const SizedBox(height: 16),
        const DesktopSkeletonRows(count: 8, avatar: false),
      ],
    );
  }
}

class _MusicGridSkeleton extends StatelessWidget {
  const _MusicGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 200).floor().clamp(2, 8);
        final width = (constraints.maxWidth - (columns - 1) * 18) / columns;
        return Wrap(
          spacing: 18,
          runSpacing: 24,
          children: [
            for (var index = 0; index < columns; index++)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: DesktopSkeletonBox(radius: 14, index: index * 3),
                    ),
                    const SizedBox(height: 10),
                    FractionallySizedBox(
                      widthFactor: 0.72,
                      alignment: Alignment.centerLeft,
                      child: DesktopSkeletonBox(
                        height: 13,
                        index: index * 3 + 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    FractionallySizedBox(
                      widthFactor: 0.48,
                      alignment: Alignment.centerLeft,
                      child: DesktopSkeletonBox(
                        height: 11,
                        index: index * 3 + 2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
