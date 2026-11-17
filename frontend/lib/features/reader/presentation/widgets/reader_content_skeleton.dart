import 'package:flutter/material.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 章节加载指示：居中转圈，不再渲染与正文同形的段落骨架。
class ReaderContentSkeleton extends StatelessWidget {
  const ReaderContentSkeleton({required this.settings, super.key});

  final ReaderViewSettings settings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        key: const Key('readerContentSkeleton'),
        dimension: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: settings.onSurfaceColor.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
