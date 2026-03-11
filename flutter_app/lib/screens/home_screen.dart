import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/prayer_time.dart';
import '../services/connection_service.dart';
import '../services/adhanbox_api.dart';
import '../providers/adhanbox_provider.dart';
import '../theme/app_theme.dart';
import 'device_setup_screen.dart';
import 'calculation_setup_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoConnectAsync = ref.watch(autoReconnectProvider);
    return autoConnectAsync.when(
      data: (deviceIp) => deviceIp == null
          ? _NoDeviceScreen(ref: ref)
          : _MainHomeScreen(ref: ref),
      loading: () => const _SplashScreen(),
      error: (_, __) => _ErrorScreen(ref: ref),
    );
  }
}

// ─────────────────────────── SPLASH ───────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MosqueIcon(size: 80)
                .animate()
                .scale(duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 28),
            Text('AdhanBox', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            Text('Connexion en cours...', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 36),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── NO DEVICE ───────────────────────────
class _NoDeviceScreen extends StatelessWidget {
  final WidgetRef ref;
  const _NoDeviceScreen({required this.ref});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 64),
              _MosqueIcon(size: 96)
                  .animate()
                  .scale(duration: 500.ms, curve: Curves.elasticOut)
                  .then()
                  .shimmer(duration: 1600.ms, color: AppTheme.emerald.withOpacity(0.25)),
              const SizedBox(height: 32),
              Text('AdhanBox', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 8),
              Text(
                'Votre compagnon de prière intelligent',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              _FeatureTile(
                icon: Icons.access_time_rounded,
                color: AppTheme.emerald,
                title: 'Horaires précis',
                subtitle: 'Calcul automatique selon votre position',
              ).animate().fadeIn(delay: 150.ms).slideX(begin: -0.15),
              const SizedBox(height: 14),
              _FeatureTile(
                icon: Icons.light_rounded,
                color: AppTheme.gold,
                title: 'Ambiance LED',
                subtitle: 'Éclairage personnalisé pour chaque moment',
              ).animate().fadeIn(delay: 250.ms).slideX(begin: -0.15),
              const SizedBox(height: 14),
              _FeatureTile(
                icon: Icons.music_note_rounded,
                color: AppTheme.fajrColor,
                title: 'Adhan personnalisé',
                subtitle: 'Choisissez votre appel à la prière',
              ).animate().fadeIn(delay: 350.ms).slideX(begin: -0.15),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Configurer mon appareil'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ).animate().fadeIn(delay: 450.ms).slideY(begin: 0.2),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _showHelp(context),
                icon: const Icon(Icons.help_outline_rounded, size: 18),
                label: const Text('Comment configurer ?'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Configuration AdhanBox'),
        content: const Text(
          '1. Allumez votre AdhanBox\n\n'
          '2. L\'appareil crée un réseau WiFi "AdhanBox"\n\n'
          '3. Appuyez sur "Configurer mon appareil"\n\n'
          '4. Suivez l\'assistant pas à pas\n\n'
          '5. L\'appareil rejoindra votre WiFi maison',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Compris')),
        ],
      ),
    );
  }
}

// ─────────────────────────── ERROR SCREEN ───────────────────────────
class _ErrorScreen extends StatelessWidget {
  final WidgetRef ref;
  const _ErrorScreen({required this.ref});

  @override
  Widget build(BuildContext context) {
    final ipController = TextEditingController();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 64),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_off_rounded, size: 44, color: Colors.orange),
              ).animate().scale(duration: 400.ms),
              const SizedBox(height: 24),
              Text('Appareil introuvable', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 10),
              Text(
                'Vérifiez que votre AdhanBox est allumée\net connectée au même réseau WiFi.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: 'Adresse IP manuelle',
                  hintText: '192.168.1.x',
                  prefixIcon: Icon(Icons.router_rounded),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final ip = ipController.text.trim();
                    if (ip.isEmpty) return;
                    final api = AdhanBoxAPI(baseUrl: 'http://$ip');
                    try {
                      await api.getStatus().timeout(const Duration(seconds: 5));
                      await saveDeviceIp(ref, ip);
                      try { await api.setRtcTime(DateTime.now()); } catch (_) {}
                      ref.invalidate(autoReconnectProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Connecté avec succès !'),
                            backgroundColor: AppTheme.emerald,
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Impossible de joindre $ip')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.connect_without_contact_rounded),
                  label: const Text('Se connecter'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(autoReconnectProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Relancer la détection'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
                ),
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Configuration avancée'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── MAIN HOME ───────────────────────────
class _MainHomeScreen extends ConsumerWidget {
  final WidgetRef ref;
  const _MainHomeScreen({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayerTimesAsync = ref.watch(adjustedPrayerTimesProvider);
    final connectionState = ref.watch(connectionStateProvider);
    final isDisconnected = connectionState.status == ConnectionStatus.disconnected ||
        connectionState.status == ConnectionStatus.error;

    return Scaffold(
      body: RefreshIndicator(
        color: AppTheme.emerald,
        onRefresh: () async {
          ref.invalidate(prayerTimesProvider);
          ref.invalidate(prayerOffsetsProvider);
          ref.invalidate(adjustedPrayerTimesProvider);
        },
        child: CustomScrollView(
          slivers: [
            // ── Gradient Header ──
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              floating: false,
              backgroundColor: AppTheme.emeraldDeep,
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: _HeaderBackground(
                  prayerTimesAsync: prayerTimesAsync,
                ),
              ),
              title: Row(
                children: [
                  const _MosqueIcon(size: 26, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    'AdhanBox',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              actions: [
                _ConnectionChip(state: connectionState),
                IconButton(
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
                  ),
                ),
              ],
            ),

            // ── Disconnected Banner ──
            if (isDisconnected)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _DisconnectedBanner(ref: ref),
                ),
              ),

            // ── Prayer List ──
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              sliver: prayerTimesAsync.when(
                data: (times) => _PrayerSliver(
                  times: times,
                  onOpenSetup: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CalculationSetupScreen()),
                    );
                    ref.invalidate(prayerTimesProvider);
                    ref.invalidate(prayerOffsetsProvider);
                  },
                ),
                loading: () => const SliverToBoxAdapter(child: _SkeletonList()),
                error: (e, _) => SliverToBoxAdapter(child: _InlineError(message: e.toString())),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── HEADER BACKGROUND ───────────────────────────
class _HeaderBackground extends StatelessWidget {
  final AsyncValue<PrayerTimes> prayerTimesAsync;
  const _HeaderBackground({required this.prayerTimesAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF064E3B), Color(0xFF065F46), Color(0xFF059669)],
        ),
      ),
      child: Stack(
        children: [
          // Subtle geometric pattern
          Positioned.fill(child: CustomPaint(painter: _GeomPainter())),
          // Next prayer info
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: prayerTimesAsync.when(
              data: (t) => _NextPrayerInfo(times: t),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextPrayerInfo extends StatelessWidget {
  final PrayerTimes times;
  const _NextPrayerInfo({required this.times});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMins = now.hour * 60 + now.minute;
    PrayerTime? next;
    int minsLeft = 0;

    for (final p in times.times) {
      final parts = p.calculatedTime.split(':');
      if (parts.length != 2) continue;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) continue;
      final mins = h * 60 + m;
      if (mins > nowMins) {
        next = p;
        minsLeft = mins - nowMins;
        break;
      }
    }
    next ??= times.times.isNotEmpty ? times.times.first : null;
    if (next == null) return const SizedBox.shrink();

    final h = minsLeft ~/ 60;
    final m = minsLeft % 60;
    final countdown = h > 0 ? '${h}h ${m}min' : '${m} min';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Prochaine prière',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          next.name,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _Pill(
              icon: Icons.access_time_rounded,
              label: next.calculatedTime,
              bg: Colors.white.withOpacity(0.18),
              fg: Colors.white,
            ),
            const SizedBox(width: 8),
            _Pill(
              icon: Icons.hourglass_bottom_rounded,
              label: 'Dans $countdown',
              bg: AppTheme.gold.withOpacity(0.28),
              fg: AppTheme.goldLight,
            ),
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  const _Pill({required this.icon, required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(color: fg, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── PRAYER SLIVER ───────────────────────────
class _PrayerSliver extends StatelessWidget {
  final PrayerTimes times;
  final VoidCallback? onOpenSetup;
  const _PrayerSliver({required this.times, this.onOpenSetup});

  int _findNextIndex() {
    final nowMins = DateTime.now().hour * 60 + DateTime.now().minute;
    for (int i = 0; i < times.times.length; i++) {
      final parts = times.times[i].calculatedTime.split(':');
      if (parts.length != 2) continue;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null && h * 60 + m > nowMins) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final prayers = times.times;
    final nextIndex = _findNextIndex();
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Aujourd'hui", style: Theme.of(ctx).textTheme.headlineMedium),
                  TextButton.icon(
                    onPressed: onOpenSetup ?? () => Navigator.of(ctx).push(
                      MaterialPageRoute(builder: (_) => const CalculationSetupScreen()),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 15),
                    label: const Text('Ajuster'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                ],
              ),
            );
          }
          final prayer = prayers[i - 1];
          final isNext = (i - 1) == nextIndex;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PrayerCard(prayer: prayer, isNext: isNext)
                .animate()
                .fadeIn(delay: Duration(milliseconds: 60 * i))
                .slideY(begin: 0.08, curve: Curves.easeOut),
          );
        },
        childCount: prayers.length + 1,
      ),
    );
  }
}

class _PrayerCard extends StatelessWidget {
  final PrayerTime prayer;
  final bool isNext;
  const _PrayerCard({required this.prayer, required this.isNext});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = AppTheme.prayerColor(prayer.name);
    final icon = AppTheme.prayerIcon(prayer.name);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isNext
            ? AppTheme.emerald.withOpacity(isDark ? 0.12 : 0.07)
            : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isNext
              ? AppTheme.emerald.withOpacity(0.5)
              : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          width: isNext ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prayer.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isNext ? AppTheme.emerald : null,
                    fontWeight: isNext ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (isNext)
                  Text(
                    'Prochaine',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.emerald),
                  ),
              ],
            ),
          ),
          Text(
            prayer.calculatedTime,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isNext
                  ? AppTheme.emerald
                  : (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── HELPERS ───────────────────────────
class _ConnectionChip extends StatelessWidget {
  final ESP32ConnectionState state;
  const _ConnectionChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (state.status) {
      ConnectionStatus.connected => (AppTheme.emeraldLight, Icons.wifi_rounded),
      ConnectionStatus.disconnected => (Colors.orange, Icons.wifi_off_rounded),
      ConnectionStatus.checking => (Colors.blue[300]!, Icons.wifi_find_rounded),
      ConnectionStatus.error => (Colors.red[300]!, Icons.error_outline_rounded),
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          state.isChecking
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                )
              : Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ],
      ),
    );
  }
}

class _DisconnectedBanner extends ConsumerWidget {
  final WidgetRef ref;
  const _DisconnectedBanner({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'AdhanBox hors ligne',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.orange),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(connectionStateProvider.notifier).checkNow(),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    ).animate().slideY(begin: -0.1).fadeIn();
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: 74,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
              borderRadius: BorderRadius.circular(16),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(duration: 1200.ms, color: AppTheme.emerald.withOpacity(0.06)),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _FeatureTile({required this.icon, required this.color, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 22),
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
        ],
      ),
    );
  }
}

// ─────────────────────────── MOSQUE ICON ───────────────────────────
class _MosqueIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _MosqueIcon({this.size = 48, this.color = AppTheme.emerald});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.mosque_rounded, size: size * 0.5, color: color),
    );
  }
}

// ─────────────────────────── GEOMETRIC PATTERN ───────────────────────────
class _GeomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.045)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    const step = 56.0;
    for (double x = 0; x < size.width + step; x += step) {
      for (double y = 0; y < size.height + step; y += step) {
        _drawStar(canvas, paint, Offset(x, y), 18);
      }
    }
  }

  void _drawStar(Canvas canvas, Paint paint, Offset center, double r) {
    const n = 8;
    final path = Path();
    for (int i = 0; i < n * 2; i++) {
      final angle = (i * math.pi / n) - math.pi / 2;
      final radius = i % 2 == 0 ? r : r * 0.42;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
