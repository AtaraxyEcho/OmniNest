import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';

/// 编辑视觉窗口的歌词颜色字段：点击色块打开调色盘弹窗。
///
/// 颜色以 [LyricPaint] 表达，可选纯色或上下渐变；弹窗提供主流音乐应用
/// 风格的预设色板、当前主题派生色、二维饱和度亮度取色面、色相条与
/// HEX 输入，渐变时两个端点共用同一套取色控件。
class MusicVisualPaintField extends StatelessWidget {
  const MusicVisualPaintField({
    super.key,
    required this.palette,
    required this.label,
    required this.value,
    required this.defaultValue,
    required this.onChanged,
    this.scopeLabel,
  });

  final MusicImmersivePalette palette;
  final String label;
  final LyricPaint value;

  /// 「恢复默认色」使用的字段默认值。
  final LyricPaint defaultValue;
  final ValueChanged<LyricPaint> onChanged;

  /// 生效范围徽标文案（桌面/移动端/通用），为空时不渲染徽标。
  final String? scopeLabel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: palette.text))),
          if (scopeLabel != null)
            MusicVisualScopeBadge(palette: palette, label: scopeLabel!),
        ],
      ),
      trailing: Semantics(
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openPicker(context),
          child: Container(
            width: 42,
            height: 30,
            decoration: BoxDecoration(
              color: value.isGradient ? null : Color(value.primary),
              gradient:
                  value.isGradient
                      ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Color(value.primary),
                          Color(value.secondary),
                        ],
                      )
                      : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
            ),
          ),
        ),
      ),
      onTap: () => _openPicker(context),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showDialog<LyricPaint>(
      context: context,
      builder:
          (context) => _VisualPaintDialog(
            palette: palette,
            title: label,
            initialPaint: value,
            defaultPaint: defaultValue,
          ),
    );
    if (selected != null) {
      onChanged(selected);
    }
  }
}

/// 预设色板：白灰、黑金、暖色、冷色四组主流音乐应用常用色。
const List<Color> _visualPresetColors = <Color>[
  // 白灰系
  Color(0xFFFFFFFF),
  Color(0xFFDCE6E8),
  Color(0xFFA8B8BD),
  Color(0xFF8DA2A7),
  // 金色系（黑金经典）
  Color(0xFFF2D986),
  Color(0xFFD9B36C),
  Color(0xFFB08D57),
  // 暖色系
  Color(0xFFF2C55C),
  Color(0xFFF0A46B),
  Color(0xFFE87878),
  Color(0xFFDD4A4A),
  Color(0xFFE97FA9),
  // 冷色系
  Color(0xFF72D6C9),
  Color(0xFF31C27C),
  Color(0xFF83C982),
  Color(0xFF58B7D9),
  Color(0xFF4A90D9),
  Color(0xFF6F92E8),
  Color(0xFFA78BE8),
];

class _VisualPaintDialog extends StatefulWidget {
  const _VisualPaintDialog({
    required this.palette,
    required this.title,
    required this.initialPaint,
    required this.defaultPaint,
  });

  final MusicImmersivePalette palette;
  final String title;
  final LyricPaint initialPaint;
  final LyricPaint defaultPaint;

  @override
  State<_VisualPaintDialog> createState() => _VisualPaintDialogState();
}

class _VisualPaintDialogState extends State<_VisualPaintDialog> {
  late LyricPaintMode _mode;

  /// 两端颜色。**每次修改都整体替换列表**：`LinearGradient`/`BoxDecoration`
  /// 以 `listEquals` 比较颜色，若原地改写同一个列表实例，新旧 decoration
  /// 判定为相等，渐变预览不会重绘（旧实现调整上色/下色时预览不跟随）。
  late List<Color> _colors;
  late final TextEditingController _hexController;

  /// 渐变态下正在编辑的端点：0 为上色，1 为下色。
  int _activeStop = 0;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialPaint.mode;
    _colors = <Color>[
      Color(widget.initialPaint.primary),
      Color(widget.initialPaint.secondary),
    ];
    _hexController = TextEditingController(text: _formatHex(_activeColor));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _activeColor =>
      _colors[_mode == LyricPaintMode.solid ? 0 : _activeStop];

  LyricPaint get _resolved =>
      _mode == LyricPaintMode.solid
          ? LyricPaint.solid(_colors.first.toARGB32())
          : LyricPaint.vertical(_colors[0].toARGB32(), _colors[1].toARGB32());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 弹窗统一复用深色主题样式：与编辑面板共用固定深色 Theme 与调色板，
    // 内嵌输入框、按钮等表单件也随深色 Theme 渲染，不随宿主主题切换。
    return Theme(
      data: musicVisualEditorDarkTheme,
      child: AlertDialog(
        backgroundColor: const Color(0xFF111A20),
        title: Text(
          widget.title,
          style: TextStyle(color: musicVisualEditorDarkPalette.text),
        ),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCaption(l10n.musicVisualizerColorPaintMode),
                _PaintModeToggle(
                  mode: _mode,
                  solidLabel: l10n.musicVisualizerColorPaintSolid,
                  gradientLabel: l10n.musicVisualizerColorPaintGradient,
                  onChanged: _applyMode,
                ),
                if (_mode == LyricPaintMode.verticalGradient) ...[
                  const SizedBox(height: 14),
                  _buildCaption(l10n.musicVisualizerColorPaintStops),
                  _buildGradientStops(l10n),
                ],
                const SizedBox(height: 14),
                _buildCaption(l10n.musicVisualizerColorPreset),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _visualPresetColors.map(_buildSwatch).toList(),
                ),
                const SizedBox(height: 12),
                _buildCaption(l10n.musicVisualizerColorTheme),
                Wrap(
                  spacing: 10,
                  children: [
                    _buildSwatch(musicVisualEditorDarkPalette.accent),
                    _buildSwatch(musicVisualEditorDarkPalette.accentAlt),
                    _buildSwatch(musicVisualEditorDarkPalette.text),
                    _buildSwatch(musicVisualEditorDarkPalette.surfaceStrong),
                  ],
                ),
                const SizedBox(height: 16),
                _buildCaption(_customCaption(l10n)),
                _VisualSvPanel(
                  color: HSVColor.fromColor(_activeColor),
                  semanticLabel: l10n.musicVisualizerColorCustom,
                  onChanged: _applyColor,
                ),
                const SizedBox(height: 10),
                _VisualHueBar(
                  color: HSVColor.fromColor(_activeColor),
                  semanticLabel: l10n.musicVisualizerColorHue,
                  onChanged:
                      (hue) => _applyColor(
                        HSVColor.fromColor(_activeColor).withHue(hue),
                      ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 32,
                      decoration: BoxDecoration(
                        color:
                            _mode == LyricPaintMode.solid
                                ? _colors.first
                                : null,
                        gradient:
                            _mode == LyricPaintMode.verticalGradient
                                ? LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: _colors,
                                )
                                : null,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.34),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('music-visual-color-hex'),
                        controller: _hexController,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[#0-9a-fA-F]'),
                          ),
                          LengthLimitingTextInputFormatter(9),
                        ],
                        // 与全库标准输入框一致：仅传 labelText，
                        // 填充、描边、文字色全部交给全局 InputDecorationTheme。
                        decoration: InputDecoration(
                          labelText: l10n.musicVisualizerColorHex,
                          isDense: true,
                        ),
                        onChanged: _handleHexChanged,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: l10n.musicVisualizerColorResetDefault,
                      onPressed: _resetToDefault,
                      icon: Icon(
                        Icons.restart_alt_rounded,
                        color: musicVisualEditorDarkPalette.text,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const ValueKey('music-visual-color-confirm'),
            onPressed: () => Navigator.of(context).pop(_resolved),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
  }

  /// 自定义取色区的标题：渐变时点明正在调节的端点。
  String _customCaption(AppLocalizations l10n) {
    if (_mode == LyricPaintMode.solid) {
      return l10n.musicVisualizerColorCustom;
    }
    return l10n.musicVisualizerColorCustomStop(
      _activeStop == 0
          ? l10n.musicVisualizerColorPaintTop
          : l10n.musicVisualizerColorPaintBottom,
    );
  }

  Widget _buildCaption(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: musicVisualEditorDarkPalette.text.withValues(alpha: 0.62),
          fontSize: AppTypography.bodySmall,
        ),
      ),
    );
  }

  /// 渐变端点选择：左侧实时预览上下渐变，右侧两个端点色块供切换编辑对象。
  Widget _buildGradientStops(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: Container(
            key: const ValueKey('music-visual-color-gradient-preview'),
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _colors,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _GradientStopButton(
          key: const ValueKey('music-visual-color-stop-top'),
          label: l10n.musicVisualizerColorPaintTop,
          color: _colors[0],
          selected: _activeStop == 0,
          onTap: () => _selectStop(0),
        ),
        const SizedBox(width: 8),
        _GradientStopButton(
          key: const ValueKey('music-visual-color-stop-bottom'),
          label: l10n.musicVisualizerColorPaintBottom,
          color: _colors[1],
          selected: _activeStop == 1,
          onTap: () => _selectStop(1),
        ),
      ],
    );
  }

  Widget _buildSwatch(Color preset) {
    final selected = preset.toARGB32() == _activeColor.toARGB32();
    return Tooltip(
      message: _formatHex(preset),
      child: Semantics(
        button: true,
        selected: selected,
        label: _formatHex(preset),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _applyColor(HSVColor.fromColor(preset)),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: preset,
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    selected
                        ? musicVisualEditorDarkPalette.text
                        : Colors.white.withValues(alpha: 0.22),
                width: selected ? 3 : 1,
              ),
            ),
            child:
                selected
                    ? Icon(
                      Icons.check_rounded,
                      size: 15,
                      color:
                          preset.computeLuminance() > 0.52
                              ? Colors.black
                              : Colors.white,
                    )
                    : null,
          ),
        ),
      ),
    );
  }

  void _applyMode(LyricPaintMode mode) {
    if (mode == _mode) {
      return;
    }
    setState(() {
      _mode = mode;
      _activeStop = 0;
    });
    _syncHexField();
  }

  void _selectStop(int index) {
    if (_activeStop == index) {
      return;
    }
    setState(() => _activeStop = index);
    _syncHexField();
  }

  void _applyColor(HSVColor next) {
    _writeColor(
      _mode == LyricPaintMode.solid ? 0 : _activeStop,
      next.toColor(),
    );
    // 取色面板/色相条/预设点选即时回写 HEX 文本框：桌面端点击取色面
    // 不会让文本框失焦，旧实现依赖失焦同步导致色值持续显示旧值。
    _syncHexField();
  }

  void _resetToDefault() {
    setState(() {
      _mode = widget.defaultPaint.mode;
      _colors = <Color>[
        Color(widget.defaultPaint.primary),
        Color(widget.defaultPaint.secondary),
      ];
      _activeStop = 0;
    });
    _syncHexField();
  }

  void _handleHexChanged(String text) {
    final parsed = _parseHex(text);
    if (parsed == null) {
      return;
    }
    _writeColor(_mode == LyricPaintMode.solid ? 0 : _activeStop, parsed);
  }

  /// 写入某一端颜色：复制出新列表再替换，保证渐变装饰按值比较时判定为变化。
  void _writeColor(int index, Color color) {
    final next = List<Color>.of(_colors);
    next[index] = color;
    setState(() => _colors = next);
  }

  void _syncHexField() {
    final formatted = _formatHex(_activeColor);
    if (_hexController.text.toUpperCase() != formatted.toUpperCase()) {
      _hexController.text = formatted;
    }
  }

  static Color? _parseHex(String input) {
    var text = input.trim();
    if (text.startsWith('#')) {
      text = text.substring(1);
    }
    // 6 位视为不透明，8 位为 RRGGBBAA：与 [_formatHex] 对称，
    // 主题派生色等带 alpha 的颜色往返不再漂移。
    if (text.length == 6) {
      text = 'FF$text';
    }
    if (text.length != 8) {
      return null;
    }
    final value = int.tryParse(text, radix: 16);
    if (value == null) {
      return null;
    }
    return Color(value);
  }

  static String _formatHex(Color color) {
    final argb = color.toARGB32();
    final alpha = (argb >> 24) & 0xFF;
    final digits = argb.toRadixString(16).padLeft(8, '0').toUpperCase();
    return alpha == 0xFF ? '#${digits.substring(2)}' : '#$digits';
  }
}

/// 画法切换：纯色与上下渐变两个互斥选项。
class _PaintModeToggle extends StatelessWidget {
  const _PaintModeToggle({
    required this.mode,
    required this.solidLabel,
    required this.gradientLabel,
    required this.onChanged,
  });

  final LyricPaintMode mode;
  final String solidLabel;
  final String gradientLabel;
  final ValueChanged<LyricPaintMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PaintModeChip(
            key: const ValueKey('music-visual-color-mode-solid'),
            label: solidLabel,
            selected: mode == LyricPaintMode.solid,
            onTap: () => onChanged(LyricPaintMode.solid),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PaintModeChip(
            key: const ValueKey('music-visual-color-mode-gradient'),
            label: gradientLabel,
            selected: mode == LyricPaintMode.verticalGradient,
            onTap: () => onChanged(LyricPaintMode.verticalGradient),
          ),
        ),
      ],
    );
  }
}

class _PaintModeChip extends StatelessWidget {
  const _PaintModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = musicVisualEditorDarkPalette;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color:
                selected
                    ? palette.accent.withValues(alpha: 0.20)
                    : palette.text.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color:
                  selected
                      ? palette.accent.withValues(alpha: 0.72)
                      : Colors.white.withValues(alpha: 0.22),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: palette.text,
              fontSize: AppTypography.bodyMedium,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 渐变端点色块：点击切换正在编辑的端点。
class _GradientStopButton extends StatelessWidget {
  const _GradientStopButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = musicVisualEditorDarkPalette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 26,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color:
                        selected
                            ? palette.text
                            : Colors.white.withValues(alpha: 0.28),
                    width: selected ? 2.5 : 1,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: palette.text.withValues(alpha: selected ? 1 : 0.6),
                  fontSize: AppTypography.labelSmall,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 二维取色面：横轴饱和度、纵轴亮度，中间圆点为当前取值。
class _VisualSvPanel extends StatelessWidget {
  const _VisualSvPanel({
    required this.color,
    required this.semanticLabel,
    required this.onChanged,
  });

  final HSVColor color;
  final String semanticLabel;
  final ValueChanged<HSVColor> onChanged;

  static const double _thumbRadius = 9;

  @override
  Widget build(BuildContext context) {
    final hueColor = color.withSaturation(1).withValue(1).toColor();
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        key: const ValueKey('music-visual-color-sv-panel'),
        width: double.infinity,
        height: 150,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              void update(Offset local) {
                final saturation = (local.dx / constraints.maxWidth).clamp(
                  0.0,
                  1.0,
                );
                final value =
                    1 - (local.dy / constraints.maxHeight).clamp(0.0, 1.0);
                onChanged(color.withSaturation(saturation).withValue(value));
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => update(details.localPosition),
                onPanStart: (details) => update(details.localPosition),
                onPanUpdate: (details) => update(details.localPosition),
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: hueColor)),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.white,
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left:
                          (color.saturation * constraints.maxWidth -
                              _thumbRadius),
                      top:
                          ((1 - color.value) * constraints.maxHeight -
                              _thumbRadius),
                      child: IgnorePointer(
                        child: Container(
                          width: _thumbRadius * 2,
                          height: _thumbRadius * 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 色相条：彩虹渐变轨道，两端闭合。
class _VisualHueBar extends StatelessWidget {
  const _VisualHueBar({
    required this.color,
    required this.semanticLabel,
    required this.onChanged,
  });

  final HSVColor color;
  final String semanticLabel;
  final ValueChanged<double> onChanged;

  static const List<Color> _hueStops = <Color>[
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  static const double _thumbDiameter = 16;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        key: const ValueKey('music-visual-color-hue-bar'),
        width: double.infinity,
        height: 26,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: LayoutBuilder(
            builder: (context, constraints) {
              void update(Offset local) {
                final hue =
                    (local.dx / constraints.maxWidth).clamp(0.0, 1.0) * 360;
                onChanged(hue);
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => update(details.localPosition),
                onPanStart: (details) => update(details.localPosition),
                onPanUpdate: (details) => update(details.localPosition),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: _hueStops,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left:
                          (color.hue / 360 * constraints.maxWidth -
                              _thumbDiameter / 2),
                      top: (constraints.maxHeight - _thumbDiameter) / 2,
                      child: IgnorePointer(
                        child: Container(
                          width: _thumbDiameter,
                          height: _thumbDiameter,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                color.withSaturation(1).withValue(1).toColor(),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
