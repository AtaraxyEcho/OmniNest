import 'dart:io' show Platform;

/// flutter_tester 运行时会注入 FLUTTER_TEST=true 环境变量（原生平台分支）。
bool get musicRunningInFlutterTest =>
    Platform.environment['FLUTTER_TEST'] == 'true';
