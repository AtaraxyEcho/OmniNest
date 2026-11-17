import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';

/// 将页面背景意图注册到应用级背景场景控制器。
class AppBackdropSceneScope extends ConsumerStatefulWidget {
  const AppBackdropSceneScope({
    required this.owner,
    required this.policy,
    required this.child,
    this.pathPrefix,
    super.key,
  });

  final String owner;
  final AppBackdropPolicy policy;

  /// 注册者所属路由分支前缀（如 `/video`）；宿主路由不在前缀下时该
  /// 注册不参与生效，用于 IndexedStack 常驻分支的可见性过滤。
  final String? pathPrefix;
  final Widget child;

  @override
  ConsumerState<AppBackdropSceneScope> createState() =>
      _AppBackdropSceneScopeState();
}

class _AppBackdropSceneScopeState extends ConsumerState<AppBackdropSceneScope> {
  late final AppBackdropSceneController _sceneController;
  int _syncGeneration = 0;
  int? _lease;

  @override
  void initState() {
    super.initState();
    _sceneController = ref.read(appBackdropSceneControllerProvider.notifier);
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant AppBackdropSceneScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner != widget.owner) {
      final oldLease = _lease;
      _lease = null;
      _scheduleRelease(oldWidget.owner, oldLease);
    }
    if (oldWidget.owner != widget.owner ||
        oldWidget.policy != widget.policy ||
        oldWidget.pathPrefix != widget.pathPrefix) {
      _scheduleSync();
    }
  }

  @override
  void dispose() {
    _syncGeneration++;
    _scheduleRelease(widget.owner, _lease);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _scheduleSync() {
    final generation = ++_syncGeneration;
    final owner = widget.owner;
    final policy = widget.policy;
    final pathPrefix = widget.pathPrefix;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _syncGeneration) {
        return;
      }
      _lease = _sceneController.request(owner, policy, pathPrefix: pathPrefix);
    });
  }

  void _scheduleRelease(String owner, int? lease) {
    if (lease == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sceneController.release(owner, lease: lease);
    });
  }
}
