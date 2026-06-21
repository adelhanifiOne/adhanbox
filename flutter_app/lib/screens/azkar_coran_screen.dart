import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/adhanbox_provider.dart';

/// Réglages V2 : Azkar (heures fixes) + Coran (Al-Kahf vendredi / Al-Mulk soir).
class AzkarCoranScreen extends ConsumerStatefulWidget {
  const AzkarCoranScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AzkarCoranScreen> createState() => _AzkarCoranScreenState();
}

class _Item {
  bool enabled;
  TimeOfDay time;
  _Item(this.enabled, this.time);
}

class _AzkarCoranScreenState extends ConsumerState<AzkarCoranScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _sabah = _Item(false, const TimeOfDay(hour: 7, minute: 0));
  final _masaa = _Item(false, const TimeOfDay(hour: 18, minute: 0));
  final _kahf = _Item(false, const TimeOfDay(hour: 9, minute: 0));
  final _mulk = _Item(false, const TimeOfDay(hour: 22, minute: 0));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(adhanboxApiProvider);
      if (api == null) throw Exception('Aucun appareil connecté');
      final d = await api.getAzkarCoran();
      void fill(_Item it, String k) {
        final m = d[k];
        if (m is Map) {
          it.enabled = (m['en'] ?? 0) == 1 || m['en'] == true;
          it.time = TimeOfDay(
              hour: (m['h'] ?? it.time.hour) as int,
              minute: (m['m'] ?? it.time.minute) as int);
        }
      }

      fill(_sabah, 'sabah');
      fill(_masaa, 'masaa');
      fill(_kahf, 'kahf');
      fill(_mulk, 'mulk');
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(adhanboxApiProvider);
      if (api == null) throw Exception('Aucun appareil connecté');
      await api.setAzkarCoran({
        'sabah_en': _sabah.enabled ? 1 : 0,
        'sabah_h': _sabah.time.hour,
        'sabah_m': _sabah.time.minute,
        'masaa_en': _masaa.enabled ? 1 : 0,
        'masaa_h': _masaa.time.hour,
        'masaa_m': _masaa.time.minute,
        'kahf_en': _kahf.enabled ? 1 : 0,
        'kahf_h': _kahf.time.hour,
        'kahf_m': _kahf.time.minute,
        'mulk_en': _mulk.enabled ? 1 : 0,
        'mulk_h': _mulk.time.hour,
        'mulk_m': _mulk.time.minute,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Réglages enregistrés ✓')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _pickTime(_Item it) async {
    final t = await showTimePicker(context: context, initialTime: it.time);
    if (t != null) setState(() => it.time = t);
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required _Item item,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            TextButton(
              onPressed: item.enabled ? () => _pickTime(item) : null,
              child: Text(item.time.format(context),
                  style: const TextStyle(fontSize: 18)),
            ),
            Switch(
              value: item.enabled,
              onChanged: (v) => setState(() => item.enabled = v),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Azkar & Coran')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: _load, child: const Text('Réessayer')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Azkar',
                        style: Theme.of(context).textTheme.headlineSmall),
                    _tile(
                        icon: Icons.wb_sunny_rounded,
                        title: 'Azkar du matin (Sabah)',
                        subtitle: 'Tous les jours à l’heure choisie',
                        item: _sabah),
                    _tile(
                        icon: Icons.nights_stay_rounded,
                        title: 'Azkar du soir (Masaa)',
                        subtitle: 'Tous les jours à l’heure choisie',
                        item: _masaa),
                    const SizedBox(height: 16),
                    Text('Coran',
                        style: Theme.of(context).textTheme.headlineSmall),
                    _tile(
                        icon: Icons.menu_book_rounded,
                        title: 'Sourate Al-Kahf',
                        subtitle: 'Chaque vendredi à l’heure choisie',
                        item: _kahf),
                    _tile(
                        icon: Icons.bedtime_rounded,
                        title: 'Sourate Al-Mulk',
                        subtitle: 'Chaque soir à l’heure choisie',
                        item: _mulk),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_rounded),
                        label: const Text('Enregistrer'),
                      ),
                    ),
                  ],
                ),
    );
  }
}
