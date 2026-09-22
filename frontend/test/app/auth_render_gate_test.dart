import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/app.dart';

/// 根 builder 认证门控的路径判定：与 router 公开路径口径一致。
/// 登出瞬间路由替换晚于渲染帧，靠该门控遮挡受保护页面的旧画面。
void main() {
  test('已认证时不门控任何路径', () {
    expect(
      gatesUnauthenticatedRender(isAuthenticated: true, path: '/portal'),
      isFalse,
    );
    expect(
      gatesUnauthenticatedRender(isAuthenticated: true, path: '/admin/users'),
      isFalse,
    );
  });

  test('未认证时门控受保护路径', () {
    expect(
      gatesUnauthenticatedRender(isAuthenticated: false, path: '/portal'),
      isTrue,
    );
    expect(
      gatesUnauthenticatedRender(isAuthenticated: false, path: '/music'),
      isTrue,
    );
    expect(
      gatesUnauthenticatedRender(isAuthenticated: false, path: '/files/x'),
      isTrue,
    );
  });

  test('未认证时放行公开路径', () {
    for (final path in [
      '/login',
      '/setup',
      '/server-setup',
      '/boot',
      '/s/abc123',
      '/shared/photos/xyz',
    ]) {
      expect(
        gatesUnauthenticatedRender(isAuthenticated: false, path: path),
        isFalse,
        reason: '$path 应视为公开路径',
      );
    }
  });
}
