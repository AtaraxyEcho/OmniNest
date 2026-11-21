part of 'desktop_np_style_panel.dart';

/// 双区颜料编辑器（复刻样例 `PaintEditor`：整行统一 / 上下分区 + `Aa 歌词` 实时着色预览 + ZoneEditor）。
class _PaintEditor extends StatelessWidget {
  const _PaintEditor({required this.paint, required this.onChanged});

  final DesktopNpPaint paint;
  final ValueChanged<DesktopNpPaint> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SplitModeCard(
                title: l10n.desktopNpWholeLine,
                subtitle: isZh ? '整行纯色或渐变' : 'One solid or gradient',
                halves: false,
                selected: !paint.split,
                onTap:
                    () => onChanged(
                      paint.copyWith(split: false, bottom: paint.top),
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SplitModeCard(
                title: l10n.desktopNpHalves,
                subtitle: isZh ? '上下各自独立配色' : 'Two independent halves',
                halves: true,
                selected: paint.split,
                onTap: () => onChanged(paint.copyWith(split: true)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // `Aa 歌词` 实时着色预览
        Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DesktopNpStylePanel._line),
          ),
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => paint.createShader(rect),
            child: Text(
              'Aa 歌词',
              style: DesktopType.sectionTitle(Colors.white).copyWith(
                fontSize: _npGlyphSize,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (paint.split) ...[
          _ZoneEditor(
            label: isZh ? '上半区' : 'Upper half',
            zone: paint.top,
            onChanged: (top) => onChanged(paint.copyWith(top: top)),
          ),
          const SizedBox(height: 8),
          _ZoneEditor(
            label: isZh ? '下半区' : 'Lower half',
            zone: paint.bottom,
            onChanged: (bot) => onChanged(paint.copyWith(bottom: bot)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.desktopNpSplitPos,
                  style: DesktopType.caption(DesktopNpStylePanel._text),
                ),
              ),
              Text(
                '${paint.splitPos}%',
                style: DesktopType.numeric(
                  Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          DesktopSlider(
            value: paint.splitPos.toDouble(),
            min: 10,
            max: 90,
            trackColor: Colors.white.withValues(alpha: 0.22),
            fillColor: skin.accent,
            thumbColor: Colors.white,
            thumbAlwaysVisible: true,
            onChanged:
                (v) => onChanged(
                  paint.copyWith(splitPos: v.round().clamp(10, 90)),
                ),
          ),
        ] else
          _ZoneEditor(
            label: isZh ? '整行歌词' : 'Whole lyric',
            zone: paint.top,
            onChanged:
                (top) => onChanged(paint.copyWith(top: top, bottom: top)),
          ),
      ],
    );
  }
}

class _ZoneEditor extends StatelessWidget {
  const _ZoneEditor({
    required this.label,
    required this.zone,
    required this.onChanged,
  });

  final String label;
  final DesktopNpZone zone;
  final ValueChanged<DesktopNpZone> onChanged;

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesktopNpStylePanel._line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: zone.toLinearGradient(),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: DesktopType.dense(
                  DesktopNpStylePanel._text,
                ).copyWith(fontSize: _npLabelSize),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _DarkSeg(
            labels: <String>[isZh ? '纯色' : 'Solid', isZh ? '渐变' : 'Gradient'],
            index: zone.gradient ? 1 : 0,
            small: true,
            onChanged: (idx) {
              final g = idx == 1;
              onChanged(
                zone.copyWith(gradient: g, end: g ? zone.end : zone.start),
              );
            },
          ),
          const SizedBox(height: 8),
          DesktopColorField(
            label:
                zone.gradient
                    ? (isZh ? '起始色' : 'Start colour')
                    : (isZh ? '颜色' : 'Colour'),
            value: zone.start,
            onChanged:
                (c) => onChanged(
                  zone.copyWith(start: c, end: zone.gradient ? zone.end : c),
                ),
          ),
          if (zone.gradient) ...[
            const SizedBox(height: 8),
            DesktopColorField(
              label: isZh ? '结束色' : 'End colour',
              value: zone.end,
              onChanged: (c) => onChanged(zone.copyWith(end: c)),
            ),
          ],
        ],
      ),
    );
  }
}

class _SplitModeCard extends StatelessWidget {
  const _SplitModeCard({
    required this.title,
    required this.subtitle,
    required this.halves,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool halves;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: DesktopMotion.of(context, DesktopMotion.fast),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: selected ? 0.16 : 0.07),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color:
                selected
                    ? Colors.white.withValues(alpha: 0.45)
                    : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color:
                      selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.65),
                  width: 1.5,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops:
                      halves ? const <double>[0.5, 0.5] : const <double>[0, 1],
                  colors: <Color>[
                    selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.65),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.dense(
                      selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.80),
                    ).copyWith(
                      fontSize: _npBadgeSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.nano(
                      Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
