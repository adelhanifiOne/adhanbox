import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/prayer_time.dart';
import '../providers/adhanbox_provider.dart';
import '../theme/app_theme.dart';
import 'calculation_setup_screen.dart';

class PrayerTimesScreen extends ConsumerWidget {
  const PrayerTimesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayerTimesAsync = ref.watch(adjustedPrayerTimesProvider);

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
            // ── App Bar ──
            SliverAppBar(
              pinned: true,
              title: Text('Horaires de Prière', style: Theme.of(context).appBarTheme.titleTextStyle),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Actualiser',
                  onPressed: () {
                    ref.invalidate(prayerTimesProvider);
                    ref.invalidate(prayerOffsetsProvider);
                    ref.invalidate(adjustedPrayerTimesProvider);
                  },
                ),
              ],
            ),

            // ── Date Header ──
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _DateBadge(),
              ),
            ),

            // ── Prayer List ──
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: prayerTimesAsync.when(
                data: (times) => _PrayerListSliver(times: times),
                loading: () => const SliverToBoxAdapter(child: _LoadingState()),
                error: (e, _) => SliverToBoxAdapter(child: _ErrorState(error: e.toString())),
              ),
            ),

            // ── Config Cards ──
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 32),
              sliver: SliverToBoxAdapter(child: _ConfigSection()),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── DATE BADGE ───────────────────────────
class _DateBadge extends StatelessWidget {
  static const _days = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
  static const _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];
  static const _hijriMonths = [
    'Muharram', 'Safar', 'Rabi\' I', 'Rabi\' II',
    'Joumada I', 'Joumada II', 'Rajab', 'Sha\'ban',
    'Ramadan', 'Chawwal', 'Dhou\'l-Qi\'da', 'Dhou\'l-Hijja',
  ];

  // Converts a Gregorian date to Hijri using the standard astronomical algorithm.
  static Map<String, int> _toHijri(DateTime date) {
    int d = date.day, m = date.month, y = date.year;
    if (m < 3) { y--; m += 12; }
    final int a = y ~/ 100;
    final int b = 2 - a + a ~/ 4;
    final int jd = (365.25 * (y + 4716)).toInt() + (30.6001 * (m + 1)).toInt() + d + b - 1524;

    int l = jd - 1948440 + 10632;
    final int n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final int j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
        (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l - ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
        (j ~/ 16) * ((15238 * j) ~/ 43) + 29;
    final int hm = (24 * l) ~/ 709;
    final int hd = l - (709 * hm) ~/ 24;
    final int hy = 30 * n + j - 30;
    return {'year': hy, 'month': hm, 'day': hd};
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dayName = _days[(now.weekday - 1) % 7];
    final fullDate = '${now.day} ${_months[now.month - 1]} ${now.year}';
    final hijri = _toHijri(now);
    final hijriDate = '${hijri['day']} ${_hijriMonths[(hijri['month']! - 1).clamp(0, 11)]} ${hijri['year']} H';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.emerald.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.emerald.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.emerald,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '${now.day}',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dayName, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.emerald)),
              Text(fullDate, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.nightlight_round, size: 11, color: AppTheme.gold),
                  const SizedBox(width: 4),
                  Text(
                    hijriDate,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.gold,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── PRAYER LIST ───────────────────────────
class _PrayerListSliver extends StatelessWidget {
  final PrayerTimes times;
  const _PrayerListSliver({required this.times});

  int _nextIndex() {
    final nowMins = DateTime.now().hour * 60 + DateTime.now().minute;
    for (int i = 0; i < times.times.length; i++) {
      final parts = times.times[i].calculatedTime.split(':');
      if (parts.length != 2) continue;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null && (h * 60 + m) > nowMins) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final nextIdx = _nextIndex();
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          final prayer = times.times[i];
          final isNext = i == nextIdx;
          final isPast = i < nextIdx;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PrayerDetailCard(
              prayer: prayer,
              isNext: isNext,
              isPast: isPast,
            )
                .animate()
                .fadeIn(delay: Duration(milliseconds: 60 * i))
                .slideY(begin: 0.08, curve: Curves.easeOut),
          );
        },
        childCount: times.times.length,
      ),
    );
  }
}

class _PrayerDetailCard extends StatelessWidget {
  final PrayerTime prayer;
  final bool isNext;
  final bool isPast;
  const _PrayerDetailCard({required this.prayer, required this.isNext, required this.isPast});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = AppTheme.prayerColor(prayer.name);
    final icon = AppTheme.prayerIcon(prayer.name);
    final opacity = isPast ? 0.45 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isNext
              ? LinearGradient(
                  colors: [
                    AppTheme.emerald.withOpacity(isDark ? 0.18 : 0.1),
                    AppTheme.emerald.withOpacity(isDark ? 0.06 : 0.04),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: isNext ? null : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
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
            // Icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            // Name & status
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
                  const SizedBox(height: 2),
                  if (isNext)
                    _StatusBadge(label: 'Prochaine', color: AppTheme.emerald)
                  else if (isPast)
                    _StatusBadge(label: 'Passée', color: AppTheme.darkTextMuted)
                  else
                    _StatusBadge(label: 'À venir', color: color.withOpacity(0.7)),
                ],
              ),
            ),
            // Time
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  prayer.calculatedTime,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isNext
                        ? AppTheme.emerald
                        : (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary),
                  ),
                ),
                if (prayer.mawaqitTime != null && prayer.mawaqitTime != prayer.calculatedTime)
                  Text(
                    'Mawaqit: ${prayer.mawaqitTime}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.gold),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─────────────────────────── CONFIG SECTION ───────────────────────────
class _ConfigSection extends ConsumerWidget {
  const _ConfigSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Configuration', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        _ConfigCard(
          icon: Icons.calculate_rounded,
          color: AppTheme.emerald,
          title: 'Méthode de calcul',
          subtitle: 'Ajustez la méthode et les angles',
          onTap: (ctx) async {
            await Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => const CalculationSetupScreen()),
            );
            ref.invalidate(prayerTimesProvider);
            ref.invalidate(prayerOffsetsProvider);
          },
        ),
      ],
    );
  }
}

class _ConfigCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final void Function(BuildContext) onTap;
  const _ConfigCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => onTap(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
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
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── STATES ───────────────────────────
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Center(child: CircularProgressIndicator(color: AppTheme.emerald)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.red, size: 40),
          const SizedBox(height: 12),
          Text('Impossible de charger les horaires', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(error, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
