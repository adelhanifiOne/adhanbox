import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

class AzkarScreen extends ConsumerStatefulWidget {
  const AzkarScreen({super.key});

  @override
  ConsumerState<AzkarScreen> createState() => _AzkarScreenState();
}

class _AzkarScreenState extends ConsumerState<AzkarScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  static const _categories = [
    ('morning',     'Matin',           '🌅', Color(0xFF0EA5E9)),
    ('evening',     'Soir',            '🌙', Color(0xFF6366F1)),
    ('after_prayer','Après prière',    '🤲', Color(0xFF10B981)),
    ('sleep',       'Coucher',         '😴', Color(0xFF8B5CF6)),
    ('wake',        'Réveil',          '☀️', Color(0xFFF59E0B)),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            title: const Text('Azkar'),
            pinned: true,
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: _categories.map((c) => Tab(text: '${c.$3} ${c.$2}')).toList(),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: _categories.map((c) => _AzkarList(
            category: c.$1,
            color: c.$4,
          )).toList(),
        ),
      ),
    );
  }
}

class _AzkarList extends ConsumerWidget {
  final String category;
  final Color color;
  const _AzkarList({required this.category, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final azkar = ref.watch(azkarProvider(category));

    return azkar.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e',
        style: GoogleFonts.inter(color: Colors.red))),
      data: (list) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        itemBuilder: (_, i) => _ZikrCard(zikr: list[i], color: color, index: i),
      ),
    );
  }
}

class _ZikrCard extends StatefulWidget {
  final Zikr zikr;
  final Color color;
  final int index;
  const _ZikrCard({required this.zikr, required this.color, required this.index});

  @override
  State<_ZikrCard> createState() => _ZikrCardState();
}

class _ZikrCardState extends State<_ZikrCard> {
  int _current = 0;
  bool _done = false;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _done
        ? AppColors.emerald.withValues(alpha: 0.1)
        : AppColors.bgCard,
      borderRadius: BorderRadius.circular(16),
      border: _done
        ? Border.all(color: AppColors.emerald.withValues(alpha: 0.4))
        : Border.all(color: widget.color.withValues(alpha: 0.15)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.zikr.textAr,
        textAlign: TextAlign.right,
        style: GoogleFonts.amiri(fontSize: 20, color: Colors.white, height: 1.8)),
      const SizedBox(height: 8),
      Text(widget.zikr.textFr,
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
      const SizedBox(height: 10),
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8)),
          child: Text(widget.zikr.source,
            style: GoogleFonts.inter(fontSize: 10, color: widget.color)),
        ),
        const Spacer(),
        if (!_done) GestureDetector(
          onTap: _increment,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, color: widget.color, size: 16),
              const SizedBox(width: 4),
              Text('$_current / ${widget.zikr.count}',
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700,
                  color: widget.color)),
            ]),
          ),
        ) else const Row(children: [
          Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 18),
          SizedBox(width: 4),
          Text('Terminé', style: TextStyle(color: AppColors.emerald, fontSize: 12)),
        ]),
      ]),
    ]),
  ).animate().fadeIn(duration: 300.ms, delay: (widget.index * 50).ms.clamp(0.ms, 400.ms));

  void _increment() {
    setState(() {
      _current++;
      if (_current >= widget.zikr.count) _done = true;
    });
  }
}
