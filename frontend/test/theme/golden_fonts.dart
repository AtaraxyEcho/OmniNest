// 视觉基线共用的字体装载：不装字体时 flutter test 用占位字体，
// 每个字形都是一块实心矩形，看不出真实的字重与可读性。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadGoldenFonts() async {
  final inter =
      FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'));
  final notoSans =
      FontLoader('NotoSansSC')
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-400.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-500.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-600.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-700.ttf'));
  final icons = FontLoader('MaterialIcons')..addFont(_loadMaterialIcons());
  await Future.wait(<Future<void>>[
    inter.load(),
    notoSans.load(),
    icons.load(),
  ]);
}

Future<ByteData> _loadMaterialIcons() async {
  var directory = File(Platform.resolvedExecutable).parent;
  final separator = Platform.pathSeparator;
  for (var level = 0; level < 8; level++) {
    final fontFile = File(
      <String>[
        directory.path,
        'bin',
        'cache',
        'artifacts',
        'material_fonts',
        'MaterialIcons-Regular.otf',
      ].join(separator),
    );
    if (await fontFile.exists()) {
      final bytes = await fontFile.readAsBytes();
      return ByteData.sublistView(Uint8List.fromList(bytes));
    }
    directory = directory.parent;
  }
  throw StateError('无法定位 Flutter Material Icons 字体。');
}
