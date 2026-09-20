import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/application/video_cover_recovery.dart';
import 'package:omninest/features/video/presentation/widgets/movie_poster_image.dart';

/// 影片海报世代重试接线：同 cacheKey 的 URL 轮换不会重载已失败流，
/// 自愈世代号必须以后缀进入最终 cacheKey。
void main() {
  testWidgets('世代号为 0 时 cacheKey 原样传递', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProviderScope(
          child: const Scaffold(
            body: MoviePosterImage(
              imageUrl: 'http://localhost:1/p.jpg',
              cacheKey: 'movie-poster:v1',
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.cacheKey, 'movie-poster:v1');
  });

  testWidgets('自愈世代号递增后 cacheKey 追加重试后缀', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProviderScope(
          overrides: [
            videoCoverRecoveryProvider.overrideWith(_FixedGeneration.new),
          ],
          child: const Scaffold(
            body: MoviePosterImage(
              imageUrl: 'http://localhost:1/p.jpg',
              cacheKey: 'movie-poster:v1',
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.cacheKey, 'movie-poster:v1:r2');
  });
}

class _FixedGeneration extends VideoCoverRecoveryController {
  @override
  int build() => 2;
}
