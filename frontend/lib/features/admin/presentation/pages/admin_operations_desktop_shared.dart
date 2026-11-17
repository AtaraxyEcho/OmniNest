part of 'admin_operations_pages.dart';

/// 管理台运维族桌面排版共用的小件（胶囊、字母头像、短时间、进度条）。

/// 行内状态/平台胶囊：文字可截断。`DesktopChip` 的 Row 不接受超宽标签，
/// 会话状态里有「Force-signed out」这类长文案，必须自带省略号。
class _DesktopPill extends StatelessWidget {
  const _DesktopPill({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(DesktopMetrics.radiusPill),
          border: Border.all(color: tone.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesktopType.chip(tone),
        ),
      ),
    );
  }
}

class _DesktopLetterAvatar extends StatelessWidget {
  const _DesktopLetterAvatar({required this.text, this.dim = false});

  final String text;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final initial =
        text.trim().isEmpty ? '?' : text.trim().characters.first.toUpperCase();
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dim ? skin.raise3 : skin.accentWash(0.18),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: DesktopType.caption(
          dim ? skin.text3 : skin.accent,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

String _shortDateTime(String? value) {
  if (value == null || value.isEmpty) {
    return '—';
  }
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) {
    return value;
  }
  String two(int part) => part.toString().padLeft(2, '0');
  return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
      '${two(parsed.hour)}:${two(parsed.minute)}';
}

class _DesktopProgress extends StatelessWidget {
  const _DesktopProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 4,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: skin.raise3)),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: ColoredBox(color: skin.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
