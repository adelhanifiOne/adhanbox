import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/adhanbox_provider.dart';
import '../theme/app_theme.dart';

class LedControlScreen extends ConsumerStatefulWidget {
  const LedControlScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LedControlScreen> createState() => _LedControlScreenState();
}

class _LedControlScreenState extends ConsumerState<LedControlScreen> {
  int _selectedScenario = 0;
  double _brightness = 50;
  bool _isSendingScenario = false;
  bool _isSendingBrightness = false;

  static const _scenarios = [
    _Scenario(id: 0, label: 'Éteint',     icon: Icons.power_settings_new_rounded, color: Color(0xFF475569)),
    _Scenario(id: 1, label: 'Rouge',       icon: Icons.circle, color: Color(0xFFEF4444)),
    _Scenario(id: 2, label: 'Rose',        icon: Icons.circle, color: Color(0xFFEC4899)),
    _Scenario(id: 3, label: 'Bleu',        icon: Icons.circle, color: Color(0xFF3B82F6)),
    _Scenario(id: 4, label: 'Violet',      icon: Icons.circle, color: Color(0xFF8B5CF6)),
    _Scenario(id: 5, label: 'Vert',        icon: Icons.circle, color: Color(0xFF10B981)),
    _Scenario(id: 6, label: 'Jaune',       icon: Icons.circle, color: Color(0xFFF59E0B)),
    _Scenario(id: 8, label: 'Arc-en-ciel', icon: Icons.auto_awesome_rounded, color: Color(0xFFEC4899)),
    _Scenario(id: 9, label: 'Dégradé',     icon: Icons.gradient_rounded, color: Color(0xFF6366F1)),
    _Scenario(id: 10, label: 'Prière',     icon: Icons.mosque_rounded, color: Color(0xFF059669)),
    _Scenario(id: 11, label: 'Respiration',icon: Icons.air_rounded, color: Color(0xFF06B6D4)),
    _Scenario(id: 12, label: 'Bougie',     icon: Icons.local_fire_department_rounded, color: Color(0xFFF59E0B)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text('Ambiance LED', style: Theme.of(context).appBarTheme.titleTextStyle),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── LED Preview ──
                  _LedPreview(scenario: _scenarios[_selectedScenario], brightness: _brightness)
                      .animate()
                      .fadeIn(duration: 400.ms),

                  const SizedBox(height: 24),

                  // ── Brightness ──
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

                  // ── Scenarios ──
                  Text('Scénario', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.92,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final sc = _scenarios[i];
                  final isSelected = _selectedScenario == i;
                  return _ScenarioCard(
                    scenario: sc,
                    isSelected: isSelected,
                    isSending: isSelected && _isSendingScenario,
                    onTap: () async {
                      setState(() { _selectedScenario = i; _isSendingScenario = true; });
                      try {
                        final api = ref.read(adhanboxApiProvider);
                        if (api != null) await api.setLedScenario(sc.id);
                      } catch (_) {} finally {
                        if (mounted) setState(() => _isSendingScenario = false);
                      }
                    },
                  ).animate().fadeIn(delay: Duration(milliseconds: 30 * i)).scale(
                    begin: const Offset(0.9, 0.9),
                    duration: 250.ms,
                    curve: Curves.easeOut,
                  );
                },
                childCount: _scenarios.length,
              ),
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

// ─────────────────────────── LED PREVIEW ───────────────────────────
class _LedPreview extends StatelessWidget {
  final _Scenario scenario;
  final double brightness;
  const _LedPreview({required this.scenario, required this.brightness});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOff = scenario.id == 0;
    final opacity = (brightness / 100).clamp(0.1, 1.0);

    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        gradient: isOff
            ? LinearGradient(
                colors: [
                  isDark ? AppTheme.darkCard : AppTheme.lightCard,
                  isDark ? AppTheme.darkSurface : AppTheme.lightBg,
                ],
              )
            : _gradientForScenario(scenario, opacity),
      ),
      child: Stack(
        children: [
          // Glow effect
          if (!isOff)
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: scenario.color.withOpacity(0.5 * opacity),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          // Label
          Positioned(
            left: 20,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scenario.label,
                  style: GoogleFonts.poppins(
                    color: isOff
                        ? (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)
                        : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    shadows: isOff ? [] : [Shadow(color: Colors.black26, blurRadius: 8)],
                  ),
                ),
                Text(
                  'Luminosité: ${brightness.toInt()}%',
                  style: GoogleFonts.inter(
                    color: isOff
                        ? (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)
                        : Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Icon
          Positioned(
            right: 20,
            top: 0,
            bottom: 0,
            child: Center(
              child: Icon(
                scenario.icon,
                size: 32,
                color: isOff
                    ? (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)
                    : Colors.white.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LinearGradient _gradientForScenario(_Scenario sc, double opacity) {
    if (sc.id == 8) {
      // Rainbow
      return LinearGradient(
        colors: [
          Colors.red.withOpacity(opacity),
          Colors.orange.withOpacity(opacity),
          Colors.yellow.withOpacity(opacity),
          Colors.green.withOpacity(opacity),
          Colors.blue.withOpacity(opacity),
          Colors.purple.withOpacity(opacity),
        ],
      );
    }
    return LinearGradient(
      colors: [
        sc.color.withOpacity(opacity),
        sc.color.withOpacity(opacity * 0.6),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
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
              value: brightness,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: onChanged,
            ),
          ),
          const Icon(Icons.brightness_high_rounded, size: 20, color: AppTheme.darkTextPrimary),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            child: isSending
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald),
                    ),
                  )
                : Text(
                    '${brightness.toInt()}%',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── SCENARIO CARD ───────────────────────────
class _ScenarioCard extends StatelessWidget {
  final _Scenario scenario;
  final bool isSelected;
  final bool isSending;
  final VoidCallback onTap;
  const _ScenarioCard({
    required this.scenario,
    required this.isSelected,
    required this.isSending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOff = scenario.id == 0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 200.ms,
        decoration: BoxDecoration(
          color: isSelected
              ? scenario.color.withOpacity(isDark ? 0.22 : 0.14)
              : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? scenario.color.withOpacity(0.7)
                : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: scenario.color.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4))]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSending)
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2, color: scenario.color),
              )
            else if (isOff)
              Icon(scenario.icon, size: 28, color: isSelected ? scenario.color : AppTheme.darkTextMuted)
            else
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scenario.id == 8
                      ? null
                      : scenario.color.withOpacity(isSelected ? 1.0 : 0.7),
                  gradient: scenario.id == 8
                      ? const LinearGradient(colors: [Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple])
                      : null,
                  boxShadow: isSelected
                      ? [BoxShadow(color: scenario.color.withOpacity(0.5), blurRadius: 8)]
                      : [],
                ),
                child: scenario.id >= 8
                    ? Icon(scenario.icon, size: 18, color: Colors.white)
                    : null,
              ),
            const SizedBox(height: 8),
            Text(
              scenario.label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected
                    ? scenario.color
                    : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── MODEL ───────────────────────────
class _Scenario {
  final int id;
  final String label;
  final IconData icon;
  final Color color;
  const _Scenario({required this.id, required this.label, required this.icon, required this.color});
}
