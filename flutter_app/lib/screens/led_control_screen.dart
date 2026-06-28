import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/adhanbox_provider.dart';
import '../theme/app_theme.dart';

// Scène 0 = éteint. Scènes 1-6 = couleurs fixes du firmware. 8-12 = animations.
const int _kSceneOff = 0;
const int _kSceneDefault = 6; // jaune par défaut à l'allumage

class LedControlScreen extends ConsumerStatefulWidget {
  const LedControlScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LedControlScreen> createState() => _LedControlScreenState();
}

class _LedControlScreenState extends ConsumerState<LedControlScreen> {
  // Scène actuellement affichée (0 = éteint)
  int _currentScene = _kSceneOff;
  // Dernière scène allumée, restaurée quand on rallume
  int _lastOnScene = _kSceneDefault;
  double _brightness = 50;
  bool _isSendingBrightness = false;
  int _tab = 0; // 0 = Couleur, 1 = Scénarios

  // Les 6 couleurs disponibles (placées sur la roue chromatique)
  static const _colors = [
    _Scene(id: 1, label: 'Rouge',  color: Color(0xFFEF4444)),
    _Scene(id: 6, label: 'Jaune',  color: Color(0xFFF59E0B)),
    _Scene(id: 5, label: 'Vert',   color: Color(0xFF10B981)),
    _Scene(id: 3, label: 'Bleu',   color: Color(0xFF3B82F6)),
    _Scene(id: 4, label: 'Violet', color: Color(0xFF8B5CF6)),
    _Scene(id: 2, label: 'Rose',   color: Color(0xFFEC4899)),
  ];

  // Les scénarios animés
  static const _scenarios = [
    _Scene(id: 8,  label: 'Arc-en-ciel', color: Color(0xFFEC4899), icon: Icons.auto_awesome_rounded),
    _Scene(id: 9,  label: 'Dégradé',     color: Color(0xFF6366F1), icon: Icons.gradient_rounded),
    _Scene(id: 10, label: 'Prière',      color: Color(0xFF059669), icon: Icons.mosque_rounded),
    _Scene(id: 11, label: 'Respiration', color: Color(0xFF06B6D4), icon: Icons.air_rounded),
    _Scene(id: 12, label: 'Bougie',      color: Color(0xFFF59E0B), icon: Icons.local_fire_department_rounded),
  ];

  bool get _isOn => _currentScene != _kSceneOff;

  _Scene get _activeScene {
    final all = [..._colors, ..._scenarios];
    return all.firstWhere((s) => s.id == _currentScene,
        orElse: () => const _Scene(id: 0, label: 'Éteint', color: Color(0xFF475569)));
  }

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
    try {
      final status = await api.getLedStatus();
      final sc = (status['scenario'] as num?)?.toInt();
      if (sc != null && mounted) {
        setState(() {
          _currentScene = sc;
          if (sc != _kSceneOff) _lastOnScene = sc;
        });
      }
    } catch (_) {}
  }

  Future<void> _applyScene(int scene) async {
    setState(() {
      _currentScene = scene;
      if (scene != _kSceneOff) _lastOnScene = scene;
    });
    final api = ref.read(adhanboxApiProvider);
    if (api == null) return;
    try {
      await api.setLedScenario(scene);
    } catch (_) {}
  }

  void _togglePower() {
    _applyScene(_isOn ? _kSceneOff : _lastOnScene);
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
                // ── Aperçu ──
                _LedPreview(scene: _activeScene, brightness: _brightness, isOn: _isOn)
                    .animate().fadeIn(duration: 350.ms),
                const SizedBox(height: 24),

                // ── Bouton power ──
                Center(child: _PowerButton(isOn: _isOn, onTap: _togglePower)),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _isOn ? 'Allumé · ${_activeScene.label}' : 'Éteint',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _isOn ? AppTheme.emerald : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Luminosité ──
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

                // ── Onglets Couleur / Scénarios ──
                _SegTabs(
                  index: _tab,
                  labels: const ['Couleur', 'Scénarios'],
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 20),

                if (_tab == 0)
                  _ColorWheel(
                    colors: _colors,
                    selectedId: _currentScene,
                    onPick: _applyScene,
                  )
                else
                  _ScenarioGrid(
                    scenarios: _scenarios,
                    selectedId: _currentScene,
                    onPick: _applyScene,
                  ),
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
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isOn ? AppTheme.emerald : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
          border: Border.all(
            color: isOn ? AppTheme.emerald : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            width: 2,
          ),
          boxShadow: isOn
              ? [BoxShadow(color: AppTheme.emerald.withOpacity(0.45), blurRadius: 28, spreadRadius: 4)]
              : [],
        ),
        child: Icon(
          Icons.power_settings_new_rounded,
          size: 48,
          color: isOn ? Colors.white : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
        ),
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
                decoration: BoxDecoration(
                  color: sel ? AppTheme.emerald : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────── COLOR WHEEL ───────────────────────────
// Roue chromatique : tape n'importe où, ça s'aligne sur la couleur
// disponible la plus proche (le firmware ne gère que ces teintes).
class _ColorWheel extends StatelessWidget {
  final List<_Scene> colors;
  final int selectedId;
  final ValueChanged<int> onPick;
  const _ColorWheel({required this.colors, required this.selectedId, required this.onPick});

  void _handle(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final v = local - center;
    if (v.distance < 8) return;
    // Angle du toucher (0 = droite, sens horaire)
    var angle = math.atan2(v.dy, v.dx);
    if (angle < 0) angle += 2 * math.pi;
    final step = 2 * math.pi / colors.length;
    final idx = (((angle + step / 2) / step).floor()) % colors.length;
    onPick(colors[idx].id);
  }

  @override
  Widget build(BuildContext context) {
    const size = 240.0;
    return Center(
      child: LayoutBuilder(builder: (ctx, _) {
        return GestureDetector(
          onTapDown: (d) => _handle(d.localPosition, const Size(size, size)),
          onPanUpdate: (d) => _handle(d.localPosition, const Size(size, size)),
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _WheelPainter(colors: colors, selectedId: selectedId),
            ),
          ),
        );
      }),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<_Scene> colors;
  final int selectedId;
  _WheelPainter({required this.colors, required this.selectedId});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final ringWidth = radius * 0.34;
    final step = 2 * math.pi / colors.length;

    // Anneau coloré segmenté
    for (var i = 0; i < colors.length; i++) {
      final start = i * step - step / 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..color = colors[i].color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - ringWidth / 2),
        start, step, false, paint,
      );
    }

    // Pastilles + marqueur de sélection
    for (var i = 0; i < colors.length; i++) {
      final ang = i * step;
      final r = radius - ringWidth / 2;
      final pos = center + Offset(math.cos(ang) * r, math.sin(ang) * r);
      final selected = colors[i].id == selectedId;
      if (selected) {
        canvas.drawCircle(pos, ringWidth * 0.42, Paint()..color = Colors.white);
        canvas.drawCircle(pos, ringWidth * 0.30, Paint()..color = colors[i].color);
      }
    }

    // Centre : couleur active ou gris
    final active = colors.where((c) => c.id == selectedId);
    final centerColor = active.isNotEmpty ? active.first.color : const Color(0xFF475569);
    canvas.drawCircle(center, radius - ringWidth - 10,
        Paint()..color = centerColor.withOpacity(active.isNotEmpty ? 1 : 0.25));
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.selectedId != selectedId;
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
        crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.95,
      ),
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
              border: Border.all(
                color: selected ? sc.color.withOpacity(0.7) : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(sc.icon ?? Icons.circle, size: 30, color: sc.color),
                const SizedBox(height: 8),
                Text(sc.label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? sc.color : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                    )),
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
  final _Scene scene;
  final double brightness;
  final bool isOn;
  const _LedPreview({required this.scene, required this.brightness, required this.isOn});

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
            ? LinearGradient(colors: [
                isDark ? AppTheme.darkCard : AppTheme.lightCard,
                isDark ? AppTheme.darkSurface : AppTheme.lightBg,
              ])
            : (scene.id == 8
                ? LinearGradient(colors: [
                    Colors.red.withOpacity(opacity), Colors.orange.withOpacity(opacity),
                    Colors.yellow.withOpacity(opacity), Colors.green.withOpacity(opacity),
                    Colors.blue.withOpacity(opacity), Colors.purple.withOpacity(opacity),
                  ])
                : LinearGradient(
                    colors: [scene.color.withOpacity(opacity), scene.color.withOpacity(opacity * 0.6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  )),
      ),
      child: Stack(children: [
        if (isOn)
          Center(
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: scene.color.withOpacity(0.5 * opacity), blurRadius: 40, spreadRadius: 10)],
              ),
            ),
          ),
        Positioned(
          left: 20, bottom: 16,
          child: Text(
            isOn ? scene.label : 'Éteint',
            style: GoogleFonts.poppins(
              color: isOn ? Colors.white : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
              fontSize: 18, fontWeight: FontWeight.w600,
              shadows: isOn ? [const Shadow(color: Colors.black26, blurRadius: 8)] : [],
            ),
          ),
        ),
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
      child: Row(
        children: [
          const Icon(Icons.brightness_low_rounded, size: 20, color: AppTheme.darkTextMuted),
          Expanded(
            child: Slider(
              value: brightness, min: 0, max: 100, divisions: 20, onChanged: onChanged,
            ),
          ),
          const Icon(Icons.brightness_high_rounded, size: 20, color: AppTheme.darkTextPrimary),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            child: isSending
                ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald)))
                : Text('${brightness.toInt()}%', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          ),
        ],
      ),
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
