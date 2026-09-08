part of 'movie_shell.dart';

/// 在屏幕中间显示影视搜索输入区域。
class _MovieSearchOverlay extends StatefulWidget {
  const _MovieSearchOverlay({required this.controller, required this.onSearch});

  final TextEditingController controller;
  final ValueChanged<String> onSearch;

  @override
  State<_MovieSearchOverlay> createState() => _MovieSearchOverlayState();
}

class _MovieSearchOverlayState extends State<_MovieSearchOverlay> {
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
            controller: widget.controller,
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
            onSubmitted: widget.onSearch,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onSearch(widget.controller.text),
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
