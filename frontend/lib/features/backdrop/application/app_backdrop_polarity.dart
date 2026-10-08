import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_tone_sampler.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_tone.dart';

/// 单张壁纸图的亮度，按 URL 缓存（瓦片预览与主图同缓存键，二次采样不再取网络）。
final appBackdropToneProvider = FutureProvider.family<AppBackdropTone, String>((
  ref,
  url,
) async {
  try {
    return await sampleAppBackdropTone(url);
  } on Exception {
    // 取不到像素就当它是暗的：判错极性的代价是整页可读性，保守取值只损失一次观感。
    return const AppBackdropTone(topLuminance: 0, bottomLuminance: 0);
  }
});

/// 当前环境壁纸的明暗极性。视频壁纸与采样未完成时取暗基准。
final appBackdropPolarityProvider = Provider<AppBackdropPolarity>((ref) {
  final state = ref.watch(appBackdropControllerProvider).asData?.value;
  if (state == null || !state.hasActiveBackdrop) {
    return AppBackdropPolarity.dark;
  }
  final asset = state.selectedBackdrop;
  if (asset == null) {
    return AppBackdropPolarity.dark;
  }
  final thumbnail = asset.thumbnailPath;
  final url =
      (thumbnail != null && thumbnail.isNotEmpty) ? thumbnail : asset.path;
  if (url.isEmpty) {
    return AppBackdropPolarity.dark;
  }
  return ref.watch(appBackdropToneProvider(url)).asData?.value.polarity ??
      AppBackdropPolarity.dark;
});
