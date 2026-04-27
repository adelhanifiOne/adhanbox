import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

class QuranScreen extends ConsumerStatefulWidget {
  const QuranScreen({super.key});

  @override
  ConsumerState<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends ConsumerState<QuranScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final surahs = ref.watch(surahsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Coran'),
            pinned: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: GoogleFonts.inter(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Rechercher une sourate...',
                    hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.bgCardLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: surahs.when(
              loading: () => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator())),
              error: (e, _) => SliverToBoxAdapter(
                child: _ErrorBanner(message: e.toString())),
              data: (list) {
                final filtered = _search.isEmpty ? list : list.where((s) =>
                  s.nameAr.contains(_search) ||
                  s.nameFr.toLowerCase().contains(_search.toLowerCase()) ||
                  s.number.toString() == _search).toList();
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _SurahTile(surah: filtered[i], index: i),
                    childCount: filtered.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SurahTile extends ConsumerWidget {
  final Surah surah;
  final int index;
  const _SurahTile({required this.surah, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF064E3B), Color(0xFF065F46)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text('${surah.number}',
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700,
              color: AppColors.gold))),
        ),
        title: Text(surah.nameAr, style: GoogleFonts.amiri(
          fontSize: 18, color: Colors.white)),
        subtitle: Text('${surah.nameFr} • ${surah.versesCount} versets • ${surah.revelationType}',
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
        trailing: IconButton(
          icon: const Icon(Icons.play_circle_rounded, color: AppColors.emerald, size: 28),
          onPressed: () => _playSurah(context, ref, surah, prefs.favoriteReciterId),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms, delay: (index * 20).ms.clamp(0.ms, 300.ms));
  }

  void _playSurah(BuildContext context, WidgetRef ref, Surah surah, int reciterId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PlayerSheet(surah: surah, reciterId: reciterId, ref: ref),
    );
  }
}

class _PlayerSheet extends StatelessWidget {
  final Surah surah;
  final int reciterId;
  final WidgetRef ref;
  const _PlayerSheet({required this.surah, required this.reciterId, required this.ref});

  @override
  Widget build(BuildContext context) {
    final reciters = ref.watch(recitersProvider);
    final currentReciter = reciters.valueOrNull
        ?.firstWhere((r) => r.id == reciterId, orElse: () => const ReciterInfo(id: 7, name: 'Mishary', style: 'Murattal'));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Text(surah.nameAr, style: GoogleFonts.amiri(
          fontSize: 32, color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(surah.nameFr, style: GoogleFonts.inter(color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Text(currentReciter?.name ?? '', style: GoogleFonts.inter(
          fontSize: 12, color: AppColors.gold)),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _PlayerBtn(icon: Icons.skip_previous_rounded, onTap: () {}),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () {},
            child: Container(
              width: 64, height: 64,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.emerald, AppColors.emeraldDark]),
                shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(width: 16),
          _PlayerBtn(icon: Icons.skip_next_rounded, onTap: () {}),
        ]),
        const SizedBox(height: 20),
      ]),
    );
  }
}

class _PlayerBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _PlayerBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCardLight, borderRadius: BorderRadius.circular(14)),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
    child: Text('Erreur chargement: $message',
      style: GoogleFonts.inter(color: Colors.red, fontSize: 12)),
  );
}
