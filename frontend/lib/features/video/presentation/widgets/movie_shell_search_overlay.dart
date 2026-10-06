part of 'movie_shell.dart';

/// 非托管移动形态的影视搜索浮层：提交即写入中心控制器查询。
class _MovieSearchOverlay extends ConsumerStatefulWidget {
  const _MovieSearchOverlay();

  @override
  ConsumerState<_MovieSearchOverlay> createState() =>
      _MovieSearchOverlayState();
}

class _MovieSearchOverlayState extends ConsumerState<_MovieSearchOverlay> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 查询写入后关闭浮层：此前只弹路由不写查询，搜索按钮点了没有结果。
  void _submit() {
    ref
        .read(movieCenterControllerProvider.notifier)
        .setSearchQuery(_controller.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      decoration: BoxDecoration(
        color: context.videoColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: context.videoColors.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.videoSearchMovies,
                  style: TextStyle(
                    color: context.videoColors.onSurface,
                    fontSize: AppTypography.titleLarge,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.coreClose,
                icon: Icon(
                  Icons.close_rounded,
                  color: context.videoColors.onSurfaceVariant,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            style: TextStyle(
              color: context.videoColors.onSurface,
              fontSize: AppTypography.titleMedium,
            ),
            decoration: InputDecoration(
              hintText: l10n.videoSearchMovieHint,
              hintStyle: TextStyle(
                color: context.videoColors.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: context.videoColors.onSurfaceVariant,
              ),
              filled: true,
              fillColor: context.videoColors.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: context.videoColors.primaryContainer.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: context.videoColors.primaryContainer,
                foregroundColor: context.videoColors.onPrimaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(l10n.videoSearch),
            ),
          ),
        ],
      ),
    );
  }
}
