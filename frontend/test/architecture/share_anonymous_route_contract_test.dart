import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/network/api_client.dart';

/// 前后端公开分享路由契约：与后端 `ShareEndpointRoutingContractTest` 保持双向锁死。
///
/// 后端 publicContentFilterChain 匿名放行 `/s/{token}`、`/authorize`、`/preview`、
/// `/children`；`/s/{token}/accept` 需要登录身份，必须交给 Bearer 刷新拦截器。
void main() {
  test('公开分享读取端点免会话，而 /s/{token}/accept 必须要求登录会话', () {
    expect(ApiClient.requiresSession('/s/share_tok_123'), isFalse);
    expect(ApiClient.requiresSession('/s/share_tok_123/authorize'), isFalse);
    expect(ApiClient.requiresSession('/s/share_tok_123/preview'), isFalse);
    expect(ApiClient.requiresSession('/s/share_tok_123/children'), isFalse);
    expect(ApiClient.requiresSession('/s/share_tok_123/'), isFalse);

    // 接受分享（转存）必须经过 Bearer 鉴权与刷新拦截器
    expect(ApiClient.requiresSession('/s/share_tok_123/accept'), isTrue);
    expect(ApiClient.requiresSession('/s/share_tok_123/accept/'), isTrue);
  });
}
