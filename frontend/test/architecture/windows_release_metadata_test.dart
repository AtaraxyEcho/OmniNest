import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 发布元数据必须使用 OmniNest 产品标识', () {
    final resource = File('windows/runner/Runner.rc').readAsStringSync();
    final mainSource = File('windows/runner/main.cpp').readAsStringSync();

    expect(resource, contains('VALUE "CompanyName", "OmniNest"'));
    expect(resource, contains('VALUE "FileDescription", "OmniNest"'));
    expect(resource, contains('VALUE "ProductName", "OmniNest"'));
    expect(resource, isNot(contains('com.example')));
    expect(mainSource, contains('window.Create(L"OmniNest"'));
  });
}
