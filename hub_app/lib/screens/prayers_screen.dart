import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

class PrayersScreen extends ConsumerWidget {
  const PrayersScreen({super.key});

  static const _prayerIcons = {
    'Fajr':    Icons.wb_twilight_rounded,
    'Sunrise': Icons.wb_sunny_outlined,
    'Dhuhr':   Icons.light_mode_rounded,
    'Asr':     Icons.sunny_snowing,
    'Maghrib': Icons.nights_stay_outlined,
    'Isha':    Icons.nightlight_round,
  };

  static const _prayerColors = {
    'Fajr':    Color(0xFF0EA5E9),
    'Sunrise': Color(0xFFF59E0B),
    'Dhuhr':   Color(0xFF10B981),
    'Asr':     Color(0xFF8B5CF6),
    'Maghrib': Color(0xFFEF4444),
    'Isha':    Color(0xFF6366F1),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayers = ref.watch(prayerTimesProvider);
    final prefs = ref.watch(prefsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Horaires de prière'),
            pinned: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_rounded),
                onPressed: () => _showConfigSheet(context, ref),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _MethodBadge(method: prefs.calculationMethod, madhab: prefs.madhab),
                const SizedBox(height: 16),
                prayers.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorCard(message: e.toString()),
                  data: (data) => Column(
                    children: data.prayers.asMap().entries.map((entry) =>
                      _PrayerCard(
                        prayer: entry.value,
                        icon: _prayerIcons[entry.value.name] ?? Icons.access_time,
                        color: _prayerColors[entry.value.name] ?? AppColors.emerald,
                        index: entry.key,
                      )
                    ).toList(),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showConfigSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ConfigSheet(ref: ref),
    );
  }
}

class _PrayerCard extends StatelessWidget {
  final PrayerTime prayer;
  final IconData icon;
  final Color color;
  final int index;

  const _PrayerCard({
    required this.prayer, required this.icon,
    required this.color, required this.index,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: prayer.isNext
        ? color.withValues(alpha: 0.12)
        : AppColors.bgCard,
      borderRadius: BorderRadius.circular(16),
      border: prayer.isNext
        ? Border.all(color: color.withValues(alpha: 0.4), width: 1.5)
        : null,
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(prayer.nameAr, style: GoogleFonts.amiri(
          fontSize: 18, color: prayer.passed ? AppColors.textMuted : Colors.white)),
        Text(prayer.name, style: GoogleFonts.inter(
          fontSize: 12, color: AppColors.textMuted)),
      ]),
      const Spacer(),
      if (prayer.isNext) Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20)),
        child: Text('Suivante', style: GoogleFonts.inter(
          fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ),
      Text(prayer.time, style: GoogleFonts.poppins(
        fontSize: 18, fontWeight: FontWeight.w700,
        color: prayer.passed ? AppColors.textMuted : Colors.white)),
    ]),
  ).animate().fadeIn(duration: 300.ms, delay: (index * 60).ms).slideX(begin: 0.05);
}

class _MethodBadge extends StatelessWidget {
  final String method;
  final String madhab;
  const _MethodBadge({required this.method, required this.madhab});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.bgCard, borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.calculate_rounded, size: 14, color: AppColors.textMuted),
      const SizedBox(width: 6),
      Text('Méthode : $method  •  Madhab : $madhab',
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
    ]),
  );
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
    child: Text('Erreur: $message', style: GoogleFonts.inter(color: Colors.red)),
  );
}

class _ConfigSheet extends StatelessWidget {
  final WidgetRef ref;
  const _ConfigSheet({required this.ref});

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Configuration calcul', style: GoogleFonts.poppins(
          fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 16),
        Text('Madhab', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: ['hanafi', 'shafi', 'maliki', 'hanbali'].map((m) =>
          ChoiceChip(
            label: Text(m, style: GoogleFonts.inter(fontSize: 12)),
            selected: prefs.madhab == m,
            selectedColor: AppColors.emerald.withValues(alpha: 0.3),
            onSelected: (_) => ref.read(prefsProvider.notifier)
              .update(prefs.copyWith(madhab: m)),
          )
        ).toList()),
        const SizedBox(height: 12),
        Text('Méthode de calcul', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: ['MWL', 'ISNA', 'Egypt', 'Makkah', 'Karachi'].map((m) =>
          ChoiceChip(
            label: Text(m, style: GoogleFonts.inter(fontSize: 12)),
            selected: prefs.calculationMethod == m,
            selectedColor: AppColors.emerald.withValues(alpha: 0.3),
            onSelected: (_) => ref.read(prefsProvider.notifier)
              .update(prefs.copyWith(calculationMethod: m)),
          )
        ).toList()),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
            onPressed: () {
              ref.invalidate(prayerTimesProvider);
              Navigator.pop(context);
            },
            child: Text('Appliquer', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}
