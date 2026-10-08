import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_tone.dart';

/// 取一张已缓存网络图的分带亮度。
///
/// 走 Flutter 自己的图片管线（ImageProvider → ui.Image → 小画布重绘），
/// 因此复用壁纸已用的 HTTP/磁盘缓存，也不需要业务模块去读原始字节路径。
/// 解码尺寸固定为个位数像素，全屏壁纸的解码代价不落在 UI isolate 之外。
Future<AppBackdropTone> sampleAppBackdropTone(String url) async {
  final info = await _resolveFirstImage(NetworkImage(url));
  final source = info.image;
  const sampleWidth = 6;
  const sampleHeight = 12;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    Rect.fromLTWH(0, 0, sampleWidth.toDouble(), sampleHeight.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final small = picture.toImageSync(sampleWidth, sampleHeight);
  try {
    final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      return const AppBackdropTone(topLuminance: 0, bottomLuminance: 0);
    }
    return toneFromRgba(
      rgba: data.buffer.asUint8List(),
      width: sampleWidth,
      height: sampleHeight,
    );
  } finally {
    small.dispose();
    picture.dispose();
    source.dispose();
  }
}

Future<ImageInfo> _resolveFirstImage(ImageProvider<Object> provider) {
  final completer = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  stream.addListener(
    ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) {
          completer.complete(info);
        }
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    ),
  );
  return completer.future;
}
