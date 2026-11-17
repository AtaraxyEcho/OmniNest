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
  final notoSans = FontLoader('NotoSansSC')
    ..addFont(rootBundle.load('assets/fonts/NotoSansSC-VF.ttf'));
  final icons = FontLoader('MaterialIcons')..addFont(_loadMaterialIcons());
  // 衬线数字与等宽档位是样例签名排版；漏装会让这些文字在基线图里
  // 变成实心矩形，整张图的可读性判断随之失效。只登记没有中文覆盖的字族：
  // 再登记一款中文族会让 CJK 的回退目标变得不确定，既有基线整体位移。
  final serif = FontLoader('InstrumentSerif')
    ..addFont(rootBundle.load('assets/fonts/InstrumentSerif-Regular.ttf'));
  final mono = FontLoader('JetBrainsMono')
    ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
  await Future.wait(<Future<void>>[
    inter.load(),
    notoSans.load(),
    icons.load(),
    serif.load(),
    mono.load(),
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
