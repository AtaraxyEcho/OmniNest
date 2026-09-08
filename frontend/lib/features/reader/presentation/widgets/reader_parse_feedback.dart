import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

/// 监听阅读条目解析状态变化，解析失败时弹出提示。
///
/// 书库/书架页面共用；包在页面内容外层即可，不参与布局。
class ReaderParseFeedback extends ConsumerStatefulWidget {
  const ReaderParseFeedback({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ReaderParseFeedback> createState() =>
      _ReaderParseFeedbackState();
}

class _ReaderParseFeedbackState extends ConsumerState<ReaderParseFeedback> {
  Set<String> _importingIds = const {};
  final Set<String> _reportedParseFailureIds = <String>{};

  void _reportParseTransitions() {
    final state =
        ref.read(readerCenterControllerProvider).asData?.value ??
        ReaderCenterState.empty();
    final previousImportingIds = _importingIds;
    final parsing = state.items.where((item) => item.isParsing).toList();
    final importingIds = parsing.map((item) => item.id).toSet();
    _importingIds = importingIds;
    _reportedParseFailureIds.removeAll(importingIds);

    for (final item in state.items) {
      final failedThisRun =
          previousImportingIds.contains(item.id) &&
          !importingIds.contains(item.id) &&
          (item.isFailed || item.isPartialFailed);
      if (failedThisRun && _reportedParseFailureIds.add(item.id)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final l10n = AppLocalizations.of(context);
          final reason = item.parseErrorMessage?.trim();
          showReaderSnackBar(
            context,
            l10n.readerImportFailedWithReason(
              item.title,
              reason == null || reason.isEmpty
                  ? l10n.readerComicImportFailed
                  : reason,
            ),
            duration: const Duration(seconds: 6),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(readerImportMonitorProvider);
    ref.watch(readerCenterControllerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportParseTransitions();
    });
    return widget.child;
  }
}
