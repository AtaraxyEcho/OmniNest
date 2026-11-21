import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_np_style.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';

/// 内联可折叠 HSV 选色器（完整复刻新版样例 `ColorPicker.tsx`）：
/// 触发行展示色块 + `#RRGGBB` + 旋转箭头，展开后在抽屉内联呈现二维 SV 画布、
/// 360° 色相条、HEX 输入框、可选自定义预设色点、14 枚基础色点及最近使用色。
class DesktopColorField extends StatefulWidget {
  const DesktopColorField({
    required this.value,
    required this.onChanged,
    required this.label,
    this.swatches,
    super.key,
  });

  final Color value;
  final ValueChanged<Color> onChanged;
  final String label;
  final List<Color>? swatches;

  @override
  State<DesktopColorField> createState() => _DesktopColorFieldState();
}

class _DesktopColorFieldState extends State<DesktopColorField> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final hex = colorToHex(widget.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: DesktopMotion.of(context, DesktopMotion.fast),
            height: 34,
            padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _open ? 0.12 : 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: _open ? 0.40 : 0.12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: widget.value,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hex,
                    style: DesktopType.numeric(
                      Colors.white.withValues(alpha: 0.88),
                    ).copyWith(letterSpacing: 0.7),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0.0,
                  duration: DesktopMotion.of(context, DesktopMotion.fast),
                  child: Icon(
                    DesktopIcons.chevDown,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 8),
          DesktopColorPicker(
            value: widget.value,
            onChanged: widget.onChanged,
            swatches: widget.swatches,
          ),
        ],
      ],
    );
  }
}

/// 选色器主体（样例 `ColorPicker.tsx`）：二维 SV 画布 + 色相条 + HEX 输入 + 预设色 + 最近色。
class DesktopColorPicker extends StatefulWidget {
  const DesktopColorPicker({
    required this.value,
    required this.onChanged,
    this.swatches,
    super.key,
  });

  final Color value;
  final ValueChanged<Color> onChanged;
  final List<Color>? swatches;

  static const List<Color> baseSwatches = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFF1F3F5),
    Color(0xFFC9D1D9),
    Color(0xFF8B949E),
    Color(0xFF3C4147),
    Color(0xFF000000),
    Color(0xFFFF6B6B),
    Color(0xFFFF9F68),
    Color(0xFFFFD166),
    Color(0xFFB9FBC0),
    Color(0xFF7BDFF2),
    Color(0xFFA0C4FF),
    Color(0xFFCDB4FF),
    Color(0xFFFF8FA3),
  ];

  @override
  State<DesktopColorPicker> createState() => _DesktopColorPickerState();
}

class _DesktopColorPickerState extends State<DesktopColorPicker> {
  static const String _recentKey = 'omninest.desktop.npRecentColors';

  late HSVColor _hsv;
  late TextEditingController _hexController;
  Color _ownColor = const Color(0xFFFFFFFF);
  List<Color> _recent = const <Color>[];

  @override
  void initState() {
    super.initState();
    _ownColor = widget.value;
    _hsv = HSVColor.fromColor(widget.value);
    _hexController = TextEditingController(text: colorToHex(widget.value));
    unawaited(_loadRecent());
  }

  @override
  void didUpdateWidget(DesktopColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _ownColor) {
      _ownColor = widget.value;
      _hsv = HSVColor.fromColor(widget.value);
      final hex = colorToHex(widget.value);
      if (_hexController.text.toUpperCase() != hex) {
        _hexController.text = hex;
      }
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recentKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final parsed = <Color>[];
      for (final item in decoded) {
        final color = parseHexColor(item?.toString());
        if (color != null) parsed.add(color);
      }
      if (mounted) {
        setState(() => _recent = List<Color>.unmodifiable(parsed.take(8)));
      }
    } on Object {
      // 忽略损坏的本地历史色。
    }
  }

  Future<void> _rememberColor(Color color) async {
    final hex = colorToHex(color);
    final next = <Color>[
      color,
      for (final c in _recent)
        if (colorToHex(c) != hex) c,
    ].take(8).toList(growable: false);
    if (mounted) {
      setState(() => _recent = next);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _recentKey,
        jsonEncode(next.map(colorToHex).toList(growable: false)),
      );
    } on Object {
      // 忽略持久化错误。
    }
  }

  void _commitHsv(HSVColor next) {
    final color = next.toColor();
    setState(() {
      _hsv = next;
      _ownColor = color;
      _hexController.text = colorToHex(color);
    });
    widget.onChanged(color);
  }

  void _pickSwatch(Color color) {
    setState(() {
      _hsv = HSVColor.fromColor(color);
      _ownColor = color;
      _hexController.text = colorToHex(color);
    });
    widget.onChanged(color);
    unawaited(_rememberColor(color));
  }

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');
    return Listener(
      onPointerUp: (_) => unawaited(_rememberColor(_ownColor)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SvSurface(
              hsv: _hsv,
              onChanged:
                  (s, v) => _commitHsv(_hsv.withSaturation(s).withValue(v)),
            ),
            const SizedBox(height: 12),
            _HueStrip(
              hue: _hsv.hue,
              onChanged: (h) => _commitHsv(_hsv.withHue(h)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _ownColor,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _hexController,
                      maxLength: 7,
                      style: DesktopType.numeric(
                        Colors.white,
                      ).copyWith(letterSpacing: 0.7),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.white),
                        ),
                      ),
                      onChanged: (text) {
                        final parsed = parseHexColor(text);
                        if (parsed != null) {
                          setState(() {
                            _hsv = HSVColor.fromColor(parsed);
                            _ownColor = parsed;
                          });
                          widget.onChanged(parsed);
                        }
                      },
                      onSubmitted: (_) {
                        _hexController.text = colorToHex(_ownColor);
                        unawaited(_rememberColor(_ownColor));
                      },
                    ),
                  ),
                ),
              ],
            ),
            if (widget.swatches != null && widget.swatches!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _SwatchWrap(
                colors: widget.swatches!,
                selected: _ownColor,
                onPick: _pickSwatch,
              ),
            ],
            const SizedBox(height: 10),
            _SwatchWrap(
              colors: DesktopColorPicker.baseSwatches,
              selected: _ownColor,
              onPick: _pickSwatch,
            ),
            if (_recent.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                isZh ? '最近使用' : 'RECENT',
                style: DesktopType.nano(
                  Colors.white.withValues(alpha: 0.45),
                ).copyWith(letterSpacing: 1.2),
              ),
              const SizedBox(height: 6),
              _SwatchWrap(
                colors: _recent,
                selected: _ownColor,
                onPick: _pickSwatch,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SvSurface extends StatelessWidget {
  const _SvSurface({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final void Function(double saturation, double value) onChanged;

  void _update(Offset localPosition, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final s = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final v = (1.0 - localPosition.dy / size.height).clamp(0.0, 1.0);
    onChanged(s, v);
  }

  @override
  Widget build(BuildContext context) {
    final pureHue = HSVColor.fromAHSV(1.0, hsv.hue, 1.0, 1.0).toColor();
    final thumbColor = hsv.toColor();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 150);
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: GestureDetector(
            onPanDown: (details) => _update(details.localPosition, size),
            onPanUpdate: (details) => _update(details.localPosition, size),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: <Color>[Colors.white, pureHue],
                          ),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (hsv.saturation * size.width) - 8,
                      top: ((1.0 - hsv.value) * size.height) - 8,
                      child: IgnorePointer(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: thumbColor,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
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
      },
    );
  }
}

class _HueStrip extends StatelessWidget {
  const _HueStrip({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  void _update(double dx, double width) {
    if (width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    onChanged(fraction * 359.99);
  }

  @override
  Widget build(BuildContext context) {
    final thumbColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onPanDown: (details) => _update(details.localPosition.dx, width),
            onPanUpdate: (details) => _update(details.localPosition.dx, width),
            child: SizedBox(
              height: 16,
              width: width,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 2,
                    bottom: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: const LinearGradient(
                          colors: <Color>[
                            Color(0xFFFF0000),
                            Color(0xFFFFFF00),
                            Color(0xFF00FF00),
                            Color(0xFF00FFFF),
                            Color(0xFF0000FF),
                            Color(0xFFFF00FF),
                            Color(0xFFFF0000),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: ((hue / 360.0).clamp(0.0, 1.0) * width) - 8,
                    child: IgnorePointer(
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: thumbColor,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
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
        );
      },
    );
  }
}

class _SwatchWrap extends StatelessWidget {
  const _SwatchWrap({
    required this.colors,
    required this.selected,
    required this.onPick,
  });

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    final selectedHex = colorToHex(selected);
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final color in colors)
          GestureDetector(
            onTap: () => onPick(color),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  color:
                      colorToHex(color) == selectedHex
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.28),
                  width: colorToHex(color) == selectedHex ? 2 : 1,
                ),
                boxShadow:
                    colorToHex(color) == selectedHex
                        ? const <BoxShadow>[
                          BoxShadow(
                            color: Color(0xFF14181C),
                            spreadRadius: 1.5,
                          ),
                          BoxShadow(color: Colors.white, spreadRadius: 3),
                        ]
                        : null,
              ),
            ),
          ),
      ],
    );
  }
}
