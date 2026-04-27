import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayers = ref.watch(prayerTimesProvider);
    final hubConnected = ref.watch(hubConnectedProvider);
    final prefs = ref.watch(prefsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, hubConnected),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _NextPrayerCard(prayers: prayers).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
                const SizedBox(height: 16),
                _PrayerTimesRow(prayers: prayers).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                const SizedBox(height: 16),
                _QuickActionsRow().animate().fadeIn(duration: 400.ms, delay: 200.ms),
                const SizedBox(height: 16),
                _AzkarCard(madhab: prefs.madhab).animate().fadeIn(duration: 400.ms, delay: 300.ms),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, AsyncValue<bool> connected) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF064E3B), Color(0xFF0F172A)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(children: [
                    Text('بِسْمِ اللهِ الرَّحْمٰنِ الرَّحِيمِ',
                      style: GoogleFonts.amiri(fontSize: 16, color: AppColors.gold)),
                    const Spacer(),
                    connected.when(
                      data: (ok) => _HubBadge(connected: ok),
                      loading: () => const _HubBadge(connected: false),
                      error: (_, __) => const _HubBadge(connected: false),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('Islamic Hub', style: GoogleFonts.poppins(
                    fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HubBadge extends StatelessWidget {
  final bool connected;
  const _HubBadge({required this.connected});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: (connected ? AppColors.emerald : Colors.red).withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: connected ? AppColors.emerald : Colors.red, width: 1),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(
        color: connected ? AppColors.emerald : Colors.red, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(connected ? 'Hub connecté' : 'Hub hors ligne',
        style: GoogleFonts.inter(fontSize: 11, color: connected ? AppColors.emerald : Colors.red)),
    ]),
  );
}

class _NextPrayerCard extends StatelessWidget {
  final AsyncValue<PrayerTimesResponse> prayers;
  const _NextPrayerCard({required this.prayers});

  @override
  Widget build(BuildContext context) {
    return prayers.when(
      loading: () => _loadingCard(),
      error: (e, _) => _offlineCard(),
      data: (data) {
        final next = data.prayers.where((p) => p.isNext).firstOrNull
            ?? data.prayers.first;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF064E3B), Color(0xFF065F46)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Prochaine prière', style: GoogleFonts.inter(
              color: AppColors.emerald, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(children: [
              Text(next.nameAr, style: GoogleFonts.amiri(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Text(next.name, style: GoogleFonts.poppins(
                color: Colors.white70, fontSize: 14)),
              const Spacer(),
              Text(next.time, style: GoogleFonts.poppins(
                color: AppColors.gold, fontSize: 32, fontWeight: FontWeight.w700)),
            ]),
          ]),
        );
      },
    );
  }

  Widget _loadingCard() => Container(
    height: 100,
    decoration: BoxDecoration(
      color: AppColors.bgCard, borderRadius: BorderRadius.circular(20)),
    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );

  Widget _offlineCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.bgCard, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
    child: Row(children: [
      const Icon(Icons.wifi_off, color: Colors.red),
      const SizedBox(width: 10),
      Text('Hub non connecté — prières en attente',
        style: GoogleFonts.inter(color: Colors.red, fontSize: 13)),
    ]),
  );
}

class _PrayerTimesRow extends StatelessWidget {
  final AsyncValue<PrayerTimesResponse> prayers;
  const _PrayerTimesRow({required this.prayers});

  @override
  Widget build(BuildContext context) {
    return prayers.when(
      loading: () => const SizedBox(height: 60),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) => Row(
        children: data.prayers.map((p) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: p.isNext
                ? AppColors.emerald.withValues(alpha: 0.15)
                : AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: p.isNext
                ? Border.all(color: AppColors.emerald.withValues(alpha: 0.5))
                : null,
            ),
            child: Column(children: [
              Text(p.nameAr, style: GoogleFonts.amiri(
                fontSize: 13,
                color: p.isNext ? AppColors.emerald : AppColors.textMuted)),
              const SizedBox(height: 4),
              Text(p.time, style: GoogleFonts.inter(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: p.isNext ? Colors.white : AppColors.textMuted)),
            ]),
          ),
        )).toList(),
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.volume_up_rounded, 'Adhan', AppColors.emerald),
      (Icons.menu_book_rounded, 'Coran', AppColors.gold),
      (Icons.favorite_rounded, 'Azkar', const Color(0xFF8B5CF6)),
      (Icons.lightbulb_rounded, 'Maison', const Color(0xFF0EA5E9)),
    ];
    return Row(
      children: actions.map((a) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _QuickActionBtn(icon: a.$1, label: a.$2, color: a.$3),
        ),
      )).toList(),
    );
  }
}

class _QuickActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _QuickActionBtn({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 5),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}

class _AzkarCard extends StatelessWidget {
  final String madhab;
  const _AzkarCard({required this.madhab});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF4C1D95).withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.favorite_rounded, color: Color(0xFF8B5CF6), size: 20),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Azkar du matin', style: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
        Text('Rappel : après Fajr', style: GoogleFonts.inter(
          fontSize: 11, color: AppColors.textMuted)),
      ])),
      const Icon(Icons.chevron_right, color: AppColors.textMuted),
    ]),
  );
}
