import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/adhanbox_provider.dart';
import '../theme/app_theme.dart';

const int _kSceneOff = 0;
const int _kSceneDefault = 6; // jaune par défaut

class LedControlScreen extends ConsumerStatefulWidget {
  const LedControlScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LedControlScreen> createState() => _LedControlScreenState();
}

class _LedControlScreenState extends ConsumerState<LedControlScreen> {
  int _currentScene = _kSceneOff;     // 0 = éteint
  int _lastOnScene = _kSceneDefault;
  Color? _customColor;                // couleur RGB libre active (prime sur la scène)
  Color _lastOnColor = const Color(0xFFF59E0B);
  double _brightness = 50;
  bool _isSendingBrightness = false;
  int _tab = 0; // 0 = Couleur, 1 = Scénarios

  static const _scenarios = [
    _Scene(id: 8,  label: 'Arc-en-ciel', color: Color(0xFFEC4899), icon: Icons.auto_awesome_rounded),
    _Scene(id: 9,  label: 'Dégradé',     color: Color(0xFF6366F1), icon: Icons.gradient_rounded),
    _Scene(id: 10, label: 'Prière',      color: Color(0xFF059669), icon: Icons.mosque_rounded),
    _Scene(id: 11, label: 'Respiration', color: Color(0xFF06B6D4), icon: Icons.air_rounded),
    _Scene(id: 12, label: 'Bougie',      color: Color(0xFFF59E0B), icon: Icons.local_fire_department_rounded),
  ];

  bool get _isOn => _customColor != null || _currentScene != _kSceneOff;

  String get _stateLabel {
    if (!_isOn) return 'Éteint';
    if (_customColor != null) return 'Couleur personnalisée';
    final s = _scenarios.where((e) => e.id == _currentScene);
    return s.isNotEmpty ? s.first.label : 'Allumé';
  }

  Color get _previewColor => _customColor ?? const Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadState());
  }

  Future<void> _loadState() async {
    final api = ref.read(adhanboxApiProvider);
    if (api == null) return;
    try {
      final b = await api.getLedBrightness();
      if (mounted) setState(() => _brightness = b.toDouble());
    } catch (_) {}
  }

  Future<void> _applyScene(int scene) async {
    setState(() {
      _currentScene = scene;
      _customColor = null;
      if (scene != _kSceneOff) _lastOnScene = scene;
    });
    final api = ref.read(adhanboxApiProvider);
    if (api == null) return;
    try {
      await api.setLedScenario(scene);
    } catch (_) {}
  }

  Future<void> _applyColor(Color c) async {
    setState(() {
      _customColor = c;
      _lastOnColor = c;
      if (_currentScene == _kSceneOff) _currentScene = 1;
    });
    final api = ref.read(adhanboxApiProvider);
    if (api == null) return;
    try {
      await api.setLedRgb(c.red, c.green, c.blue);
    } catch (_) {}
  }

  void _togglePower() {
    if (_isOn) {
      _applyScene(_kSceneOff);
    } else {
      // Restaure la dernière couleur si on était en mode couleur, sinon la dernière scène
      if (_tab == 0) {
        _applyColor(_lastOnColor);
      } else {
        _applyScene(_lastOnScene == _kSceneOff ? _kSceneDefault : _lastOnScene);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            title: Text('Lumière', style: Theme.of(context).appBarTheme.titleTextStyle),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _LedPreview(color: _previewColor, label: _stateLabel, brightness: _brightness, isOn: _isOn, isScenario: _customColor == null && _currentScene == 8)
                    .animate().fadeIn(duration: 350.ms),
                const SizedBox(height: 24),

                Center(child: _PowerButton(isOn: _isOn, onTap: _togglePower)),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _isOn ? 'Allumé · $_stateLabel' : 'Éteint',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _isOn ? AppTheme.emerald : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Text('Luminosité', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                _BrightnessSlider(
                  brightness: _brightness,
                  isSending: _isSendingBrightness,
                  onChanged: (v) async {
                    setState(() { _brightness = v; _isSendingBrightness = true; });
                    try {
                      final api = ref.read(adhanboxApiProvider);
                      if (api != null) await api.setLedBrightness(v.toInt());
                    } catch (_) {} finally {
                      if (mounted) setState(() => _isSendingBrightness = false);
                    }
                  },
                ),
                const SizedBox(height: 28),

                _SegTabs(
                  index: _tab,
                  labels: const ['Couleur', 'Scénarios'],
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 20),

                if (_tab == 0)
                  _HsvWheel(selected: _customColor, onPick: _applyColor)
                else
                  _ScenarioGrid(scenarios: _scenarios, selectedId: _customColor == null ? _currentScene : -1, onPick: _applyScene),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── POWER BUTTON ───────────────────────────
class _PowerButton extends StatelessWidget {
  final bool isOn;
  final VoidCallback onTap;
  const _PowerButton({required this.isOn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 110, height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isOn ? AppTheme.emerald : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
          border: Border.all(color: isOn ? AppTheme.emerald : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder), width: 2),
          boxShadow: isOn ? [BoxShadow(color: AppTheme.emerald.withOpacity(0.45), blurRadius: 28, spreadRadius: 4)] : [],
        ),
        child: Icon(Icons.power_settings_new_rounded, size: 48,
            color: isOn ? Colors.white : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)),
      ),
    );
  }
}

// ─────────────────────────── SEGMENTED TABS ───────────────────────────
class _SegTabs extends StatelessWidget {
  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  const _SegTabs({required this.index, required this.labels, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final sel = i == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: sel ? AppTheme.emerald : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                child: Text(labels[i], textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────── HSV COLOR WHEEL ───────────────────────────
// Vraie roue chromatique : angle = teinte, distance au centre = saturation.
class _HsvWheel extends StatefulWidget {
  final Color? selected;
  final ValueChanged<Color> onPick;
  const _HsvWheel({required this.selected, required this.onPick});

  @override
  State<_HsvWheel> createState() => _HsvWheelState();
}

class _HsvWheelState extends State<_HsvWheel> {
  Offset? _marker; // position relative du marqueur (-1..1)

  void _handle(Offset local, double size) {
    final radius = size / 2;
    final center = Offset(radius, radius);
    var v = local - center;
    final dist = v.distance.clamp(0.0, radius);
    if (v.distance > radius) v = v * (radius / v.distance);
    var angle = math.atan2(v.dy, v.dx);
    if (angle < 0) angle += 2 * math.pi;
    final hue = angle * 180 / math.pi; // 0..360
    final sat = (dist / radius).clamp(0.0, 1.0);
    final color = HSVColor.fromAHSV(1, hue, sat, 1).toColor();
    setState(() => _marker = Offset(v.dx / radius, v.dy / radius));
    widget.onPick(color);
  }

  @override
  Widget build(BuildContext context) {
    const size = 250.0;
    return Center(
      child: GestureDetector(
        onTapDown: (d) => _handle(d.localPosition, size),
        onPanUpdate: (d) => _handle(d.localPosition, size),
        child: SizedBox(
          width: size, height: size,
          child: CustomPaint(painter: _WheelPainter(marker: _marker, selected: widget.selected)),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final Offset? marker;
  final Color? selected;
  _WheelPainter({required this.marker, required this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);

    // Roue : balayage de teintes (conique) + dégradé radial vers le blanc au centre
    const steps = 360;
    for (var i = 0; i < steps; i++) {
      final a0 = (i - 0.5) * math.pi / 180;
      final sweep = 1.2 * math.pi / 180;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, i.toDouble(), 1, 1).toColor()],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      paint.style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(Rect.fromCircle(center: center, radius: radius), a0, sweep, false)
        ..close();
      canvas.drawPath(path, paint);
    }

    // Marqueur de sélection
    if (marker != null) {
      final pos = center + Offset(marker!.dx * radius, marker!.dy * radius);
      canvas.drawCircle(pos, 16, Paint()..color = Colors.white);
      canvas.drawCircle(pos, 13, Paint()..color = selected ?? Colors.white);
      canvas.drawCircle(pos, 16, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black26);
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.marker != marker || old.selected != selected;
}

// ─────────────────────────── SCENARIO GRID ───────────────────────────
class _ScenarioGrid extends StatelessWidget {
  final List<_Scene> scenarios;
  final int selectedId;
  final ValueChanged<int> onPick;
  const _ScenarioGrid({required this.scenarios, required this.selectedId, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.95),
      itemCount: scenarios.length,
      itemBuilder: (ctx, i) {
        final sc = scenarios[i];
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final selected = sc.id == selectedId;
        return GestureDetector(
          onTap: () => onPick(sc.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: selected ? sc.color.withOpacity(isDark ? 0.22 : 0.14) : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? sc.color.withOpacity(0.7) : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder), width: selected ? 2 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(sc.icon ?? Icons.circle, size: 30, color: sc.color),
                const SizedBox(height: 8),
                Text(sc.label, style: GoogleFonts.inter(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? sc.color : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────── LED PREVIEW ───────────────────────────
class _LedPreview extends StatelessWidget {
  final Color color;
  final String label;
  final double brightness;
  final bool isOn;
  final bool isScenario;
  const _LedPreview({required this.color, required this.label, required this.brightness, required this.isOn, required this.isScenario});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opacity = (brightness / 100).clamp(0.15, 1.0);
    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        gradient: !isOn
            ? LinearGradient(colors: [isDark ? AppTheme.darkCard : AppTheme.lightCard, isDark ? AppTheme.darkSurface : AppTheme.lightBg])
            : (isScenario
                ? LinearGradient(colors: [
                    Colors.red.withOpacity(opacity), Colors.orange.withOpacity(opacity), Colors.yellow.withOpacity(opacity),
                    Colors.green.withOpacity(opacity), Colors.blue.withOpacity(opacity), Colors.purple.withOpacity(opacity)])
                : LinearGradient(colors: [color.withOpacity(opacity), color.withOpacity(opacity * 0.6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight)),
      ),
      child: Stack(children: [
        if (isOn)
          Center(child: Container(width: 80, height: 80,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withOpacity(0.5 * opacity), blurRadius: 40, spreadRadius: 10)]))),
        Positioned(left: 20, bottom: 16, child: Text(isOn ? label : 'Éteint',
            style: GoogleFonts.poppins(color: isOn ? Colors.white : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                fontSize: 18, fontWeight: FontWeight.w600, shadows: isOn ? [const Shadow(color: Colors.black26, blurRadius: 8)] : []))),
      ]),
    );
  }
}

// ─────────────────────────── BRIGHTNESS SLIDER ───────────────────────────
class _BrightnessSlider extends StatelessWidget {
  final double brightness;
  final bool isSending;
  final ValueChanged<double> onChanged;
  const _BrightnessSlider({required this.brightness, required this.isSending, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Row(children: [
        const Icon(Icons.brightness_low_rounded, size: 20, color: AppTheme.darkTextMuted),
        Expanded(child: Slider(value: brightness, min: 0, max: 100, divisions: 20, onChanged: onChanged)),
        const Icon(Icons.brightness_high_rounded, size: 20, color: AppTheme.darkTextPrimary),
        const SizedBox(width: 12),
        SizedBox(width: 48, child: isSending
            ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald)))
            : Text('${brightness.toInt()}%', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center)),
      ]),
    );
  }
}

// ─────────────────────────── MODEL ───────────────────────────
class _Scene {
  final int id;
  final String label;
  final Color color;
  final IconData? icon;
  const _Scene({required this.id, required this.label, required this.color, this.icon});
}
