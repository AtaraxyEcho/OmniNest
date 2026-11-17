import 'package:flutter/material.dart';

/// 播放计划加载或失败时显示的退出按钮。
class MoviePlayerFallbackBackButton extends StatelessWidget {
  const MoviePlayerFallbackBackButton({
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: Colors.black.withValues(alpha: 0.52),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              icon: const Icon(Icons.arrow_back_rounded),
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 播放器缓冲状态覆盖层。
class MoviePlayerBufferingIndicator extends StatelessWidget {
  const MoviePlayerBufferingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white70),
    );
  }
}
