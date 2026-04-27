import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

class HomeControlScreen extends ConsumerWidget {
  const HomeControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(title: Text('Maison'), pinned: true),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _AdhanBoxCard(ref: ref).animate().fadeIn(duration: 300.ms),
                const SizedBox(height: 16),
                _ScenesSection().animate().fadeIn(duration: 300.ms, delay: 100.ms),
                const SizedBox(height: 16),
                _ComingSoonBanner().animate().fadeIn(duration: 300.ms, delay: 200.ms),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdhanBoxCard extends StatefulWidget {
  final WidgetRef ref;
  const _AdhanBoxCard({required this.ref});

  @override
  State<_AdhanBoxCard> createState() => _AdhanBoxCardState();
}

class _AdhanBoxCardState extends State<_AdhanBoxCard> {
  int _ledScenario = 8;
  int _brightness = 50;

  static const _scenarios = [
    (0,  'Off',      Icons.circle_outlined,          Colors.grey),
    (8,  'Hue',      Icons.blur_circular_rounded,    AppColors.emerald),
    (10, 'Prière',   Icons.mosque_rounded,           Color(0xFF10B981)),
    (11, 'Respir.',  Icons.air_rounded,              Color(0xFF0EA5E9)),
    (12, 'Fête',     Icons.celebration_rounded,      Color(0xFFF59E0B)),
  ];

  @override
  Widget build(BuildContext context) {
    final api = widget.ref.read(apiServiceProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.speaker_rounded, color: AppColors.emerald, size: 20),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AdhanBox', style: GoogleFonts.poppins(
              fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
            Text('ESP32 • MQTT', style: GoogleFonts.inter(
              fontSize: 11, color: AppColors.textMuted)),
          ]),
          const Spacer(),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald.withValues(alpha: 0.15),
              foregroundColor: AppColors.emerald,
              elevation: 0,
            ),
            icon: const Icon(Icons.volume_up_rounded, size: 16),
            label: Text('Adhan', style: GoogleFonts.inter(fontSize: 12)),
            onPressed: () => api.triggerAdhan(),
          ),
        ]),
        const Divider(color: AppColors.bgCardLight, height: 24),
        Text('Scénario LED', style: GoogleFonts.inter(
          fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 10),
        Row(children: _scenarios.map((s) => Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() => _ledScenario = s.$1);
              api.setLed(scenario: s.$1, brightness: _brightness);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _ledScenario == s.$1
                  ? s.$4.withValues(alpha: 0.2)
                  : AppColors.bgCardLight,
                borderRadius: BorderRadius.circular(10),
                border: _ledScenario == s.$1
                  ? Border.all(color: s.$4.withValues(alpha: 0.5))
                  : null,
              ),
              child: Column(children: [
                Icon(s.$3, color: _ledScenario == s.$1 ? s.$4 : AppColors.textMuted, size: 18),
                const SizedBox(height: 4),
                Text(s.$2, style: GoogleFonts.inter(
                  fontSize: 10,
                  color: _ledScenario == s.$1 ? s.$4 : AppColors.textMuted)),
              ]),
            ),
          ),
        )).toList()),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.brightness_6_rounded, color: AppColors.textMuted, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8)),
              child: Slider(
                value: _brightness.toDouble(),
                min: 0, max: 100,
                activeColor: AppColors.gold,
                inactiveColor: AppColors.bgCardLight,
                onChanged: (v) => setState(() => _brightness = v.round()),
                onChangeEnd: (v) => api.setLed(scenario: _ledScenario, brightness: v.round()),
              ),
            ),
          ),
          Text('$_brightness%', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
        ]),
      ]),
    );
  }
}

class _ScenesSection extends StatelessWidget {
  static const _scenes = [
    ('Mode Prière',   Icons.mosque_rounded,         Color(0xFF064E3B), '🤲'),
    ('Fajr',          Icons.wb_twilight_rounded,     Color(0xFF1E3A5F), '🌅'),
    ('Tahajjud',      Icons.nightlight_round,        Color(0xFF1A1035), '🌙'),
    ('Ramadan',       Icons.star_rounded,            Color(0xFF3D1A00), '🌙'),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Scènes islamiques', style: GoogleFonts.poppins(
        fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
      const SizedBox(height: 10),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.5,
        children: _scenes.map((s) => _SceneCard(
          name: s.$1, icon: s.$2, bgColor: s.$3, emoji: s.$4)).toList(),
      ),
    ],
  );
}

class _SceneCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color bgColor;
  final String emoji;
  const _SceneCard({required this.name, required this.icon, required this.bgColor, required this.emoji});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(width: 8),
      Text(name, style: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
    ]),
  );
}

class _ComingSoonBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.bgCard, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.bgCardLight)),
    child: Row(children: [
      const Icon(Icons.construction_rounded, color: AppColors.gold, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(
        'Zigbee, lumières, prises et capteurs — disponibles Phase 2 avec Home Assistant',
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted))),
    ]),
  );
}
