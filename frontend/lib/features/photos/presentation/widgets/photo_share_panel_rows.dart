part of 'photo_share_panel.dart';

/// 分享设置的行控件。
///
/// 有效期档位用胶囊单选：四档是有限且全部的取值，平铺出来一眼看得到边界，
/// 不需要下拉再展开一次。
class _ShareExpiryChips extends StatelessWidget {
  const _ShareExpiryChips({
    required this.value,
    required this.enabled,
    required this.onSelected,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = <(String, String)>[
      ('1d', l10n.photosShareExpiry1d),
      ('7d', l10n.photosShareExpiry7d),
      ('30d', l10n.photosShareExpiry30d),
      ('never', l10n.photosShareExpiryNever),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.photosShareExpiryOption,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: AppTypography.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        // 用 Wrap 而非等分 Row：英文档名长短不一，等分宽度会让最长一档被截断。
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in entries)
              _ShareExpiryChip(
                label: entry.$2,
                selected: entry.$1 == value,
                enabled: enabled,
                onTap: () => onSelected(entry.$1),
              ),
          ],
        ),
      ],
    );
  }
}

class _ShareExpiryChip extends StatelessWidget {
  const _ShareExpiryChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color:
            selected
                ? SeverityColors.goodFaint
                : Colors.white.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color:
                selected
                    ? SeverityColors.good.withValues(alpha: 0.60)
                    : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                color:
                    !enabled
                        ? Colors.white.withValues(alpha: 0.28)
                        : selected
                        ? SeverityColors.good
                        : Colors.white.withValues(alpha: 0.62),
                fontSize: AppTypography.labelSmall,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 设置开关行：iOS 胶囊 36×22，开态绿色。
class _ShareToggleRow extends StatelessWidget {
  const _ShareToggleRow({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      label: label,
      child: GestureDetector(
        onTap: enabled ? () => onChanged(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
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
                AnimatedContainer(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
