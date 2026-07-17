// [PLAYER] Barre « en cours de lecture » — s'affiche au-dessus de la barre de
// navigation quand l'AdhanBox joue un audio (sourate, azkar, adhan…).
// Tap -> panneau complet : progression, pause/reprise, suivant, lecture auto,
// aléatoire, volume. Comme une app de streaming, mais c'est la box qui joue.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/playback_provider.dart';
import '../theme/app_theme.dart';

class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pb = ref.watch(playbackProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!pb.hasAudio) return const SizedBox.shrink();

    return Material(
      color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: InkWell(
        onTap: () => _openSheet(context),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 1,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // fine barre de progression en tête
              SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: pb.size > 0 ? pb.progress : null,
                  backgroundColor: Colors.transparent,
                  color: AppTheme.emerald,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        pb.paused
                            ? Icons.pause_rounded
                            : Icons.graphic_eq_rounded,
                        color: AppTheme.emerald,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            pb.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (pb.subtitle.isNotEmpty)
                            Text(
                              pb.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? AppTheme.darkTextMuted
                                    : AppTheme.lightTextMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        pb.paused
                            ? Icons.play_circle_fill_rounded
                            : Icons.pause_circle_filled_rounded,
                        color: AppTheme.emerald,
                        size: 34,
                      ),
                      onPressed: () =>
                          ref.read(playbackProvider.notifier).togglePause(),
                    ),
                    if (pb.hasQueue)
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, size: 30),
                        onPressed: () =>
                            ref.read(playbackProvider.notifier).next(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NowPlayingSheet(),
    );
  }
}

class _NowPlayingSheet extends ConsumerWidget {
  const _NowPlayingSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pb = ref.watch(playbackProvider);
    final ctrl = ref.read(playbackProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppTheme.emerald.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              pb.paused ? Icons.pause_rounded : Icons.graphic_eq_rounded,
              color: AppTheme.emerald,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            pb.title.isEmpty ? 'Aucune lecture' : pb.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          if (pb.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                pb.subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color:
                      isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
            ),
          const SizedBox(height: 18),
          // progression
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pb.size > 0 ? pb.progress : null,
              minHeight: 5,
              backgroundColor:
                  (isDark ? Colors.white : Colors.black).withOpacity(0.08),
              color: AppTheme.emerald,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                pb.size > 0 ? '${(pb.progress * 100).round()} %' : '…',
                style: TextStyle(
                  fontSize: 11,
                  color:
                      isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
              Text(
                pb.paused ? 'En pause' : (pb.playing ? 'Lecture' : 'Arrêté'),
                style: TextStyle(
                  fontSize: 11,
                  color:
                      isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // contrôles principaux
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ModeButton(
                icon: Icons.shuffle_rounded,
                active: pb.shuffle,
                tooltip: 'Lecture aléatoire',
                onTap: ctrl.toggleShuffle,
              ),
              IconButton(
                iconSize: 40,
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: () {
                  ctrl.stop();
                  Navigator.of(context).pop();
                },
              ),
              IconButton(
                iconSize: 64,
                icon: Icon(
                  pb.paused
                      ? Icons.play_circle_fill_rounded
                      : Icons.pause_circle_filled_rounded,
                  color: AppTheme.emerald,
                ),
                onPressed: ctrl.togglePause,
              ),
              IconButton(
                iconSize: 40,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: pb.hasQueue ? ctrl.next : null,
              ),
              _ModeButton(
                icon: Icons.repeat_rounded,
                active: pb.autoplay,
                tooltip: 'Enchaîner automatiquement',
                onTap: ctrl.toggleAutoplay,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // volume de la box
          Row(
            children: [
              const Icon(Icons.volume_down_rounded, size: 20),
              Expanded(
                child: Slider(
                  value: pb.volume.toDouble().clamp(0, 30),
                  min: 0,
                  max: 30,
                  divisions: 30,
                  activeColor: AppTheme.emerald,
                  onChanged: (v) => ctrl.setVolume(v.round()),
                ),
              ),
              const Icon(Icons.volume_up_rounded, size: 20),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  const _ModeButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: active
                ? AppTheme.emerald.withOpacity(0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 24,
            color: active ? AppTheme.emerald : null,
          ),
        ),
      ),
    );
  }
}
