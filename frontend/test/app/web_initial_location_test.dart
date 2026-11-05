import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/web_initial_location_parse.dart';

/// 冷启动深链解析：hash 路由取 fragment，非法地址回落到门户。
void main() {
  test('取 hash 深链作为初始路由', () {
    expect(
      parseWebInitialLocation('https://nest.example.com/#/reader/items/book-1'),
      '/reader/items/book-1',
    );
    expect(
      parseWebInitialLocation(
        'https://nest.example.com/base/#/files/preview/f-1',
      ),
      '/files/preview/f-1',
    );
  });

  test('裸根与空 fragment 回落门户', () {
    expect(parseWebInitialLocation('https://nest.example.com/'), isNull);
    expect(parseWebInitialLocation('https://nest.example.com/#'), isNull);
    expect(parseWebInitialLocation(''), isNull);
  });

  test('fragment 不是应用路由时不当作深链', () {
    expect(
      parseWebInitialLocation('https://nest.example.com/#section-2'),
      isNull,
    );
  });

  test('非法地址不抛异常', () {
    expect(parseWebInitialLocation('http://[::1'), isNull);
    expect(parseWebInitialLocation('not a url'), isNull);
  });

  test('路径式地址（未启用 path 策略）不误判为深链', () {
    expect(
      parseWebInitialLocation('https://nest.example.com/reader/items/book-1'),
      isNull,
    );
  });
}
