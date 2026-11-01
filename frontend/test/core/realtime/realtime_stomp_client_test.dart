import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_stomp_client.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

/// 记录构造出的配置，并把建链与订阅换成可控桩，避免真实 WebSocket。
class _StubStompClient extends StompClient {
  _StubStompClient(StompConfig config) : super(config: config);

  int activateCalls = 0;
  int deactivateCalls = 0;
  int subscribeCalls = 0;
  bool throwOnSubscribe = false;
  bool throwOnDeactivate = false;

  @override
  void activate() {
    activateCalls++;
  }

  @override
  void deactivate() {
    deactivateCalls++;
    if (throwOnDeactivate) {
      throw StompBadStateException('no active connection while disconnecting');
    }
  }

  @override
  StompUnsubscribe subscribe({
    required String destination,
    required StompFrameCallback callback,
    Map<String, String>? headers,
  }) {
    subscribeCalls++;
    if (throwOnSubscribe) {
      throw StompBadStateException('no active connection while subscribing');
    }
    return ({unsubscribeHeaders}) {};
  }
}

void main() {
  test('CONNECTED 回调到达时连接已断：状态回落且后续仍可重新建链', () async {
    final created = <_StubStompClient>[];
    final client = RealtimeStompClient(
      url: 'ws://127.0.0.1:1/ws',
      accessTokenResolver: () => 'token',
      clientFactory: (config) {
        final stub = _StubStompClient(config);
        created.add(stub);
        return stub;
      },
    );

    client.connect();
    expect(created, hasLength(1));
    created.first.throwOnSubscribe = true;

    created.first.config.onConnect(StompFrame(command: 'CONNECTED'));

    expect(created.first.subscribeCalls, 1);
    expect(client.state, RealtimeTransportState.disconnected);
    expect(created.first.deactivateCalls, 1);

    // 失效连接必须被清空，否则 connect() 会被短路条件挡回，本会话再也收不到推送。
    client.connect();
    expect(created, hasLength(2));

    await client.dispose();
  });

  test('订阅成功时保持 connected 并订阅同步与通知两个目的地', () async {
    final created = <_StubStompClient>[];
    final client = RealtimeStompClient(
      url: 'ws://127.0.0.1:1/ws',
      accessTokenResolver: () => 'token',
      clientFactory: (config) {
        final stub = _StubStompClient(config);
        created.add(stub);
        return stub;
      },
    );

    client.connect();
    created.first.config.onConnect(StompFrame(command: 'CONNECTED'));

    expect(created.first.subscribeCalls, 2);
    expect(client.state, RealtimeTransportState.connected);

    await client.dispose();
  });

  test('拆除时补发 DISCONNECT 帧失败：异常不逃逸且状态落到 disconnected', () async {
    final created = <_StubStompClient>[];
    final client = RealtimeStompClient(
      url: 'ws://127.0.0.1:1/ws',
      accessTokenResolver: () => 'token',
      clientFactory: (config) {
        final stub = _StubStompClient(config);
        created.add(stub);
        return stub;
      },
    );

    client.connect();
    created.first.config.onConnect(StompFrame(command: 'CONNECTED'));
    // 服务端已因会话吊销关掉链路，此时补发 DISCONNECT 帧必抛状态异常。
    created.first.throwOnDeactivate = true;

    expect(client.pause, returnsNormally);
    expect(client.state, RealtimeTransportState.disconnected);
    expect(created.first.deactivateCalls, 1);

    await client.dispose();
  });
}
