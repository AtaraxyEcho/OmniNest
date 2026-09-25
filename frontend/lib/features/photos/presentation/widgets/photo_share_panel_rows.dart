part of 'photo_share_panel.dart';

/// 分享设置的行控件。
/// OPTIONS 选择行：整行下拉，右侧显示当前档位。
class _ShareSelectRow extends StatelessWidget {
  const _ShareSelectRow({
    required this.label,
    required this.value,
    required this.onSelected,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSelected;

  List<(String, String)> _entries(AppLocalizations l10n) {
    return [
      ('1d', l10n.photosShareExpiry1d),
      ('7d', l10n.photosShareExpiry7d),
      ('30d', l10n.photosShareExpiry30d),
      ('never', l10n.photosShareExpiryNever),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = _entries(l10n);
    final current = entries.firstWhere(
      (entry) => entry.$1 == value,
      orElse: () => entries.first,
    );
    return PopupMenuButton<String>(
      onSelected: onSelected,
      tooltip: '',
      color: PhotosChromeColors.sharePanelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      itemBuilder:
          (context) => [
            for (final entry in entries)
              PopupMenuItem(
                value: entry.$1,
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.$2,
                        style: TextStyle(
                          color:
                              entry.$1 == value
                                  ? SeverityColors.good
                                  : Colors.white.withValues(alpha: 0.80),
                          fontSize: AppTypography.bodyMedium,
                        ),
                      ),
                    ),
                    if (entry.$1 == value)
                      const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: SeverityColors.good,
                      ),
                  ],
                ),
              ),
          ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ),
            Text(
              current.$2,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: AppTypography.labelSmall,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.40),
            ),
          ],
        ),
      ),
    );
  }
}

/// OPTIONS 开关行：iOS 胶囊 36×22，开态绿色。
class _ShareToggleRow extends StatelessWidget {
  const _ShareToggleRow({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: AppTypography.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sublabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.30),
                      fontSize: AppTypography.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => onChanged(!value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 36,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color:
                      value
                          ? SeverityColors.goodFaint
                          : Colors.white.withValues(alpha: 0.15),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: PhotosChromeColors.shadow66,
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
