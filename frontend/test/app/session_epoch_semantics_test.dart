import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/session/session_epoch.dart';

/// 语义回归：换号重置必须让旧账号数据「不可见」，而不是仅触发刷新。
///
/// Riverpod 的 AsyncValue 在 invalidate（刷新）语义下会把上一份数据保留为
/// 可访问旧值（isRefreshing + asData 可用），于是 .when(skipLoadingOnRefresh:
/// true) 与 asData 读取会渲染上一账号内容；而依赖变化（会话世代递增）属于
/// reload 语义，旧值不可访问。本测试锁定这一差别，避免重置机制退化。
class _EpochScopedNotifier extends AsyncNotifier<String> {
  static int builds = 0;

  @override
  Future<String> build() async {
    final epoch = ref.watch(sessionEpochProvider);
    builds += 1;
    // 模拟网络延迟，避免事件合并掩盖中间态。
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return 'epoch-$epoch';
  }
}

final _scopedProvider = AsyncNotifierProvider<_EpochScopedNotifier, String>(
  _EpochScopedNotifier.new,
);

void main() {
  test('会话世代递增后重建期间不暴露上一账号旧值', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final seen = <AsyncValue<String>>[];
    container.listen(_scopedProvider, (prev, next) => seen.add(next));
    expect(await container.read(_scopedProvider.future), 'epoch-0');

    container.read(sessionEpochProvider.notifier).bump();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final loading = seen.where((value) => value.isLoading).toList();
    expect(loading, isNotEmpty);
    // 依赖变化语义：重建期间旧值不可作为数据访问。
    expect(loading.every((value) => value.asData == null), isTrue);
    expect(loading.every((value) => value.isRefreshing), isFalse);
    // 重建期间也不应出现「旧值 + 有数据」的组合。
    expect(
      seen.any(
        (value) =>
            value.isLoading &&
            value.asData?.value == 'epoch-0' &&
            value != seen.first,
      ),
      isFalse,
    );

    expect(await container.read(_scopedProvider.future), 'epoch-1');
    expect(_EpochScopedNotifier.builds, 2);
  });

  test('同时递增世代与 invalidate 时仍保持依赖变化语义', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final seen = <AsyncValue<String>>[];
    container.listen(_scopedProvider, (prev, next) => seen.add(next));
    await container.read(_scopedProvider.future);

    container.read(sessionEpochProvider.notifier).bump();
    container.invalidate(_scopedProvider);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final loading = seen.where((value) => value.isLoading).toList();
    expect(loading, isNotEmpty);
    expect(loading.every((value) => value.asData == null), isTrue);
  });
}
