import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// iOS Info.plist 权限与后台模式契约。
///
/// 相机/麦克风描述缺失会在调用系统相机时被 iOS 终止；
/// UIBackgroundModes 不得声明未实现的 fetch/processing（审核与行为风险）。
void main() {
  final plistFile = File('${Directory.current.path}/ios/Runner/Info.plist');

  Map<String, Object> readPlist() {
    final document = XmlDocument.parse(plistFile.readAsStringSync());
    final dict = document.rootElement.findElements('dict').first;
    final map = <String, Object>{};
    final children = dict.childElements.toList();
    for (var i = 0; i < children.length - 1; i += 2) {
      final key = children[i].innerText;
      final value = children[i + 1];
      if (value.name.local == 'array') {
        map[key] = value.childElements.map((e) => e.innerText).toList();
      } else {
        map[key] = value.innerText;
      }
    }
    return map;
  }

  test('Info.plist 含相机/麦克风/相册/定位权限描述', () {
    expect(plistFile.existsSync(), isTrue);
    final map = readPlist();
    for (final key in [
      'NSCameraUsageDescription',
      'NSMicrophoneUsageDescription',
      'NSPhotoLibraryUsageDescription',
      'NSPhotoLibraryAddUsageDescription',
      'NSLocationWhenInUseUsageDescription',
    ]) {
      expect(map[key], isA<String>(), reason: '$key 必须存在且为字符串');
      expect((map[key] as String).trim(), isNotEmpty, reason: '$key 不得为空');
    }
  });

  test('UIBackgroundModes 仅保留已实现的 audio', () {
    final map = readPlist();
    final modes =
        (map['UIBackgroundModes'] as List<Object?>? ?? []).cast<String>();
    expect(modes, contains('audio'));
    expect(modes, isNot(contains('fetch')), reason: '无后台 fetch 实现时不得声明');
    expect(
      modes,
      isNot(contains('processing')),
      reason: '无 processing 实现时不得声明',
    );
  });
}
