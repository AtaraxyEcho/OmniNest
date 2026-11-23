import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 带小比例容差的 golden 比较器。
///
/// 首页 hero 的两枚玻璃徽标会通过 `BackdropFilter` 采样底下的封面图，而封面解码
/// 在「单跑本文件」与「并行跑整个桌面套件」两种调度下会落在不同相位：整跑时稳定
/// 差 0.32%（约 5.1k 像素），全部集中在徽标的采样底色上，与布局/配色无关。
///
/// 这里允许「单像素通道差 > 8/255 的像素」占比不超过 0.6%：真正的布局位移、
/// 卡片缺失或主题换色都会远超该量级，仍会被拦下；同时把标准失败产物（
/// isolatedDiff / maskedDiff）留给超容差的情况。
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile, {this.maxDiffRatio = 0.006});

  /// 允许的差异像素占比上限。
  final double maxDiffRatio;

  /// 单像素视为「不同」的通道差阈值（0-255）。
  static const int _channelTolerance = 8;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final File goldenFile = File.fromUri(basedir.resolveUri(golden));
    if (!goldenFile.existsSync()) {
      return super.compare(imageBytes, golden);
    }
    final Uint8List expectedBytes = await goldenFile.readAsBytes();
    if (_bytesEqual(expectedBytes, imageBytes)) {
      return true;
    }
    final bool withinTolerance = await _withinTolerance(
      expectedBytes,
      imageBytes,
    );
    if (withinTolerance) {
      return true;
    }
    // 超出容差：走标准比较器，产出 diff 图与失败信息。
    return super.compare(imageBytes, golden);
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.lengthInBytes != b.lengthInBytes) {
      return false;
    }
    for (var i = 0; i < a.lengthInBytes; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _withinTolerance(Uint8List expected, Uint8List actual) async {
    final ui.Image expectedImage = await _decode(expected);
    final ui.Image actualImage = await _decode(actual);
    try {
      if (expectedImage.width != actualImage.width ||
          expectedImage.height != actualImage.height) {
        return false;
      }
      final ByteData? expectedData = await expectedImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final ByteData? actualData = await actualImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (expectedData == null || actualData == null) {
        return false;
      }
      final Uint8List a = expectedData.buffer.asUint8List();
      final Uint8List b = actualData.buffer.asUint8List();
      final int pixels = expectedImage.width * expectedImage.height;
      var differing = 0;
      for (var i = 0; i < a.lengthInBytes; i += 4) {
        if ((a[i] - b[i]).abs() > _channelTolerance ||
            (a[i + 1] - b[i + 1]).abs() > _channelTolerance ||
            (a[i + 2] - b[i + 2]).abs() > _channelTolerance) {
          differing += 1;
        }
      }
      return differing / pixels <= maxDiffRatio;
    } finally {
      expectedImage.dispose();
      actualImage.dispose();
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }
}
