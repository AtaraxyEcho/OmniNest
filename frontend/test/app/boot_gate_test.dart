import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/boot_gate.dart';

void main() {
  test('看门狗到期后放行门控并触发一次路由重算', () async {
    final container = ProviderContainer(
      overrides: [
        bootGateBudgetProvider.overrideWithValue(
          const Duration(milliseconds: 5),
        ),
      ],
    );
    addTearDown(container.dispose);

    final refreshProvider = Provider<ValueNotifier<int>>(
      (ref) => installBootGate(ref),
    );
    final refresh = container.read(refreshProvider);
    // 每次新建 Provider 实例，避免非 autoDispose 的读缓存把过期前的
    // true 一直留到断言时。
    bool allowsWaiting() =>
        container.read(Provider<bool>((ref) => bootGateAllowsWaiting(ref)));

    expect(allowsWaiting(), isTrue);
    expect(refresh.value, 0);

    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(container.read(bootGateElapsedProvider), isTrue);
    expect(allowsWaiting(), isFalse);
    expect(refresh.value, 1);
  });

  test('到期前不误触发刷新', () {
    final container = ProviderContainer(
      overrides: [
        bootGateBudgetProvider.overrideWithValue(const Duration(days: 1)),
      ],
    );
    addTearDown(container.dispose);
    final refreshProvider = Provider<ValueNotifier<int>>(
      (ref) => installBootGate(ref),
    );

    final refresh = container.read(refreshProvider);
    expect(container.read(bootGateElapsedProvider), isFalse);
    expect(refresh.value, 0);
  });
}
