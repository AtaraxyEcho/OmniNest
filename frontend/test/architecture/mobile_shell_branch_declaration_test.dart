import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/mobile_shell/mobile_navigation_config.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';

/// 壳层的按分支决策必须逐条表态（N5，2026-10-14）。
///
/// 三条决策（子页让位、多选占用、背景策略）此前都以「文件分支显式 + 其余
/// 通配 false/兜底」写成白名单：新增一级分支忘了登记不会报错，只会静默拿到
/// 兜底值，表现为自带页头的整屏层叠在壳层顶栏下出现两套页头——看得见、查不出。
/// 现在通配臂只允许做「调试期当场抛错」这一件事，本文件钉住两侧：
/// 已声明的四条分支必须取值正常，未声明的分支编号必须炸。
void main() {
  const declaredBranches = [
    MobileNavigationConfig.portalBranch,
    MobileNavigationConfig.libraryBranch,
    MobileNavigationConfig.readerBranch,
    MobileNavigationConfig.filesBranch,
  ];

  test('四条已声明分支各自都有显式臂，通配不再当默认值用', () {
    final bindings =
        File(
          'lib/app/mobile_shell/mobile_shell_feature_bindings.dart',
        ).readAsStringSync();
    final config =
        File(
          'lib/app/mobile_shell/mobile_navigation_config.dart',
        ).readAsStringSync();

    for (final branch in declaredBranches) {
      final name =
          branch == MobileNavigationConfig.portalBranch
              ? 'portalBranch'
              : branch == MobileNavigationConfig.libraryBranch
              ? 'libraryBranch'
              : branch == MobileNavigationConfig.readerBranch
              ? 'readerBranch'
              : 'filesBranch';
      expect(
        bindings.contains('MobileNavigationConfig.$name'),
        isTrue,
        reason: '两条让位/多选决策都要显式列出 $name 分支',
      );
      expect(
        config.contains('$name =>'),
        isTrue,
        reason: '背景策略必须为 $name 显式给档，不能靠通配兜底',
      );
    }
    expect(
      bindings.contains('_ => false,'),
      isFalse,
      reason: '通配 false 就是被 N5 取消的静默默认值',
    );
  });

  test('已声明的分支取值正常，不触发未登记断言', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 文件分支会 watch 真实控制器，此处只验其余三条的显式臂。
    for (final branch in [
      MobileNavigationConfig.portalBranch,
      MobileNavigationConfig.libraryBranch,
      MobileNavigationConfig.readerBranch,
    ]) {
      expect(
        container.read(mobileShellSubpageActiveProvider(branch)),
        isFalse,
        reason: '分支 $branch 未让位',
      );
      expect(
        container.read(mobileShellSelectionActiveProvider(branch)),
        isFalse,
        reason: '分支 $branch 未占用多选',
      );
      expect(MobileNavigationConfig.backdropPolicyForBranch(branch), isNotNull);
    }
  });

  Object? captureError(void Function() body) {
    try {
      body();
    } catch (error) {
      return error;
    }
    return null;
  }

  test('未登记的分支编号当场抛错，而不是静默取兜底值', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const undeclared = 99;

    // Provider 体内的异常被 Riverpod 包成 ProviderException，所以判据取
    // 「有没有抛错 + 报错有没有点出这个分支号」，不绑定异常类型。
    final probes = <String, void Function()>{
      '子页让位':
          () => container.read(mobileShellSubpageActiveProvider(undeclared)),
      '多选占用':
          () => container.read(mobileShellSelectionActiveProvider(undeclared)),
      '背景策略': () => MobileNavigationConfig.backdropPolicyForBranch(undeclared),
    };
    for (final probe in probes.entries) {
      final error = captureError(probe.value);
      expect(error, isNotNull, reason: '${probe.key} 漏登记必须当场可见');
      expect(
        error.toString(),
        contains('$undeclared'),
        reason: '${probe.key} 的报错必须点出未登记的分支编号',
      );
    }
  });
}
