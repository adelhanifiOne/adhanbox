import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/quran_data.dart';
import '../providers/adhanbox_provider.dart';
import '../theme/app_theme.dart';

/// Lecteur Coran : choisir un récitateur puis une sourate (jouée sur l'AdhanBox).
/// Les fichiers sont pré-chargés sur la SD : /quran/<slug>/NNN.mp3
class QuranPlayerScreen extends ConsumerStatefulWidget {
  const QuranPlayerScreen({super.key});

  @override
  ConsumerState<QuranPlayerScreen> createState() => _QuranPlayerScreenState();
}

class _QuranPlayerScreenState extends ConsumerState<QuranPlayerScreen> {
  int _reciter = 0;
  int? _playing; // numéro de sourate en cours
  bool _busy = false;
  String _query = '';

  Future<void> _play(Surah s) async {
    final api = ref.read(adhanboxApiProvider);
    if (api == null) {
      _snack('Aucun appareil connecté');
      return;
    }
    setState(() {
      _busy = true;
      _playing = s.number;
    });
    try {
      await api.playFile(surahPath(kReciters[_reciter].slug, s.number));
    } catch (e) {
      _playing = null;
      _snack('Lecture impossible (fichier absent sur la carte ?)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final api = ref.read(adhanboxApiProvider);
    await api?.stopAudio();
    if (mounted) setState(() => _playing = null);
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surahs = _query.isEmpty
        ? kSurahs
        : kSurahs.where((s) =>
            s.name.toLowerCase().contains(_query.toLowerCase()) ||
            s.arabic.contains(_query) ||
            s.number.toString() == _query).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coran'),
        actions: [
          if (_playing != null)
            IconButton(
              icon: const Icon(Icons.stop_circle_rounded, color: AppTheme.emerald),
              tooltip: 'Arrêter',
              onPressed: _stop,
            ),
        ],
      ),
      body: Column(
        children: [
          // Sélecteur de récitateur
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: kReciters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final sel = i == _reciter;
                return ChoiceChip(
                  label: Text(kReciters[i].name),
                  selected: sel,
                  onSelected: (_) => setState(() => _reciter = i),
                  selectedColor: AppTheme.emerald,
                  labelStyle: TextStyle(
                    color: sel ? Colors.white : null,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
          // Recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher une sourate…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // Liste des sourates
          Expanded(
            child: ListView.builder(
              itemCount: surahs.length,
              itemBuilder: (context, i) {
                final s = surahs[i];
                final playing = _playing == s.number;
                return ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: playing
                        ? AppTheme.emerald
                        : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
                    child: playing
                        ? const Icon(Icons.volume_up_rounded, size: 18, color: Colors.white)
                        : Text('${s.number}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  title: Text(s.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: playing ? AppTheme.emerald : null)),
                  subtitle: Text(s.arabic, style: const TextStyle(fontSize: 15)),
                  trailing: Icon(
                    playing ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                    color: playing ? AppTheme.emerald : AppTheme.darkTextMuted,
                  ),
                  onTap: _busy ? null : () => _play(s),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
