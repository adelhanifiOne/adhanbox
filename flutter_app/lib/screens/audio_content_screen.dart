import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/adhanbox_provider.dart';

/// Écran V2 : contenu audio de la carte SD.
/// - bouton "Synchroniser" -> télécharge les nouveaux fichiers depuis le repo
/// - liste les fichiers présents sur la SD
class AudioContentScreen extends ConsumerStatefulWidget {
  const AudioContentScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AudioContentScreen> createState() => _AudioContentScreenState();
}

class _AudioContentScreenState extends ConsumerState<AudioContentScreen> {
  List<String> _files = [];
  bool _loading = true;
  bool _syncing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(adhanboxApiProvider);
      if (api == null) throw Exception('Aucun appareil connecté');
      final files = await api.listAudio();
      files.sort();
      _files = files;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final api = ref.read(adhanboxApiProvider);
      if (api == null) throw Exception('Aucun appareil connecté');
      await api.syncContent(); // lance la synchro en tâche de fond sur le device
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Synchronisation lancée… les fichiers apparaissent au fur et à mesure')));
      }
      // On interroge l'état + on rafraîchit la liste jusqu'à la fin (~3 min max).
      for (int i = 0; i < 45; i++) {
        await Future.delayed(const Duration(seconds: 4));
        if (!mounted) return;
        await _refresh();
        try {
          final st = await api.getContentStatus();
          if (st['running'] == false) {
            final added = (st['added'] ?? 0) as int;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(added > 0
                      ? '$added fichier(s) téléchargé(s) ✓'
                      : 'Déjà à jour ✓')));
            }
            break;
          }
        } catch (_) {/* device occupé, on réessaie */}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
    if (mounted) setState(() => _syncing = false);
  }

  IconData _iconFor(String path) {
    final p = path.toLowerCase();
    if (p.contains('/adhan')) return Icons.campaign_rounded;
    if (p.contains('/azkar')) return Icons.spa_rounded;
    if (p.contains('/quran') || p.contains('kahf') || p.contains('mulk')) {
      return Icons.menu_book_rounded;
    }
    if (p.contains('/dua')) return Icons.volunteer_activism_rounded;
    return Icons.audiotrack_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contenu audio')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_download_rounded),
                label: Text(_syncing
                    ? 'Synchronisation…'
                    : 'Synchroniser le contenu'),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 12),
                            ElevatedButton(
                                onPressed: _refresh,
                                child: const Text('Réessayer')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: _files.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 80),
                                  Center(child: Text('Aucun fichier audio')),
                                ],
                              )
                            : ListView.separated(
                                itemCount: _files.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) => ListTile(
                                  leading: Icon(_iconFor(_files[i])),
                                  title: Text(_files[i]),
                                  dense: true,
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
