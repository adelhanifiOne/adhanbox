import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/adhanbox_provider.dart';
import '../theme/app_theme.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({Key? key}) : super(key: key);

  String _read(Map<String, dynamic> status, List<String> keys, {String fallback = 'N/A'}) {
    for (final k in keys) {
      final v = status[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
      }
    }
    return fallback;
  }

  String _readLocation(Map<String, dynamic> status) {
    final lat = _read(status, ['latitude', 'lat'], fallback: '');
    final lon = _read(status, ['longitude', 'lon'], fallback: '');
    if (lat.isEmpty || lon.isEmpty) return 'N/A';
    return '$lat°, $lon°';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(deviceStatusProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero Header ──
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppTheme.emeraldDeep,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _AboutHeader(),
            ),
            title: Text(
              'À propos',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
            ),
          ),

          // ── Content ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // App description
                _AboutCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('AdhanBox', style: Theme.of(context).textTheme.headlineMedium),
                            _VersionBadge(label: 'v1.0.0'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Compagnon intelligent pour votre appareil de prière connecté. '
                          'Consultez les horaires, personnalisez l\'adhan et créez l\'ambiance '
                          'parfaite avec les LED.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.06),

                const SizedBox(height: 16),

                // Device info
                _AboutCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: Row(
                          children: [
                            const Icon(Icons.memory_rounded, color: AppTheme.emerald, size: 20),
                            const SizedBox(width: 10),
                            Text('Appareil connecté', style: Theme.of(context).textTheme.titleLarge),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 20),
                      statusAsync.when(
                        data: (status) => _DeviceInfoList(status: status, reader: _read, locationReader: _readLocation),
                        loading: () => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator(color: AppTheme.emerald)),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(e.toString(), style: const TextStyle(color: Colors.red, fontSize: 13))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.06),

                const SizedBox(height: 16),

                // Features
                _AboutCard(
                  child: Column(
                    children: [
                      _AboutListTile(
                        icon: Icons.schedule_rounded,
                        iconColor: AppTheme.emerald,
                        title: 'Horaires précis',
                        subtitle: 'Calcul local + Mawaqit en ligne',
                        showDivider: true,
                      ),
                      _AboutListTile(
                        icon: Icons.light_rounded,
                        iconColor: AppTheme.gold,
                        title: 'LED intelligentes',
                        subtitle: '12 scénarios d\'ambiance',
                        showDivider: true,
                      ),
                      _AboutListTile(
                        icon: Icons.music_note_rounded,
                        iconColor: AppTheme.fajrColor,
                        title: 'Adhans personnalisés',
                        subtitle: 'Choix de voix d\'adhans personnalisées',
                        showDivider: false,
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.06),

                const SizedBox(height: 24),

                // Footer
                Center(
                  child: Text(
                    '© 2026 AdhanBox · Tous droits réservés',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ).animate().fadeIn(delay: 400.ms),

                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Fait avec ❤️ pour la communauté',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ).animate().fadeIn(delay: 450.ms),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── DEVICE INFO LIST ───────────────────────────
class _DeviceInfoList extends StatelessWidget {
  final Map<String, dynamic> status;
  final String Function(Map<String, dynamic>, List<String>, {String fallback}) reader;
  final String Function(Map<String, dynamic>) locationReader;
  const _DeviceInfoList({required this.status, required this.reader, required this.locationReader});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Firmware', reader(status, ['firmware', 'version'])),
      ('Adresse IP', reader(status, ['ip'])),
      ('Heure appareil', reader(status, ['rtc_time', 'rtc'])),
      ('Position', locationReader(status)),
    ];

    return Column(
      children: items.asMap().entries.map((e) {
        final isLast = e.key == items.length - 1;
        return _InfoRow(
          label: e.value.$1,
          value: e.value.$2,
          showDivider: !isLast,
        );
      }).toList(),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool showDivider;
  const _InfoRow({required this.label, required this.value, this.showDivider = true});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 20,
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
      ],
    );
  }
}

// ─────────────────────────── HEADER ───────────────────────────
class _AboutHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF064E3B), Color(0xFF065F46), Color(0xFF047857)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _AboutPatternPainter())),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                  ),
                  child: const Icon(Icons.mosque_rounded, size: 46, color: Colors.white),
                ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
                const SizedBox(height: 16),
                Text(
                  'AdhanBox',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Horaires de Prière Intelligents',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── COMPONENTS ───────────────────────────
class _AboutCard extends StatelessWidget {
  final Widget child;
  const _AboutCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: child,
    );
  }
}

class _VersionBadge extends StatelessWidget {
  final String label;
  const _VersionBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.emerald.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.emerald.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(color: AppTheme.emerald, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AboutListTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool showDivider;
  const _AboutListTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(
                Icons.check_circle_rounded,
                color: AppTheme.emerald.withOpacity(0.7),
                size: 18,
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 70,
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
      ],
    );
  }
}

// ─────────────────────────── PATTERN ───────────────────────────
class _AboutPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (double x = 0; x < size.width + 60; x += 60) {
      for (double y = 0; y < size.height + 60; y += 60) {
        _drawOctagram(canvas, paint, Offset(x, y), 20);
      }
    }
  }

  void _drawOctagram(Canvas canvas, Paint paint, Offset c, double r) {
    final path = Path();
    for (int i = 0; i < 16; i++) {
      final angle = (i * math.pi / 8) - math.pi / 2;
      final rad = i % 2 == 0 ? r : r * 0.42;
      final x = c.dx + rad * math.cos(angle);
      final y = c.dy + rad * math.sin(angle);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
