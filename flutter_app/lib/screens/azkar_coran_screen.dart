import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/adhanbox_provider.dart';

/// Automatisations Azkar & Coran (V2) : par automatisation -> on/off, heure,
/// volume, jours de la semaine. Auto-save (pas de bouton Enregistrer).
class AzkarCoranScreen extends ConsumerStatefulWidget {
  const AzkarCoranScreen({super.key});

  @override
  ConsumerState<AzkarCoranScreen> createState() => _AzkarCoranScreenState();
}

/// jours = bitmask, bit0=Dimanche … bit6=Samedi (convention RTClib du firmware)
class _Item {
  bool enabled;
  TimeOfDay time;
  int volume; // 0-30
  int days; // bitmask
  _Item(this.enabled, this.time, this.volume, this.days);
}

class _AzkarCoranScreenState extends ConsumerState<AzkarCoranScreen> {
  bool _loading = true;
  String? _error;
  String _saveState = ''; // '', 'saving', 'saved'
  Timer? _saveTimer;

  // valeurs par défaut (écrasées par le GET)
  final _sabah = _Item(false, const TimeOfDay(hour: 7, minute: 0), 20, 0x7F);
  final _masaa = _Item(false, const TimeOfDay(hour: 18, minute: 0), 20, 0x7F);
  final _kahf = _Item(false, const TimeOfDay(hour: 9, minute: 0), 20, 0x20); // vendredi
  final _mulk = _Item(false, const TimeOfDay(hour: 22, minute: 0), 20, 0x7F);

  // libellés des jours (index = bit) : 0=Dim … 6=Sam
  static const _dayLabels = ['D', 'L', 'M', 'M', 'J', 'V', 'S'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
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
          it.volume = (m['vol'] ?? it.volume) as int;
          it.days = (m['days'] ?? it.days) as int;
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

  /// Auto-save débouncé : tout changement programme un envoi 600 ms plus tard.
  void _scheduleSave() {
    setState(() => _saveState = 'saving');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    Map<String, dynamic> f(String p, _Item it) => {
          '${p}_en': it.enabled ? 1 : 0,
          '${p}_h': it.time.hour,
          '${p}_m': it.time.minute,
          '${p}_vol': it.volume,
          '${p}_days': it.days,
        };
    try {
      final api = ref.read(adhanboxApiProvider);
      if (api == null) throw Exception('Aucun appareil connecté');
      await api.setAzkarCoran({
        ...f('sabah', _sabah),
        ...f('masaa', _masaa),
        ...f('kahf', _kahf),
        ...f('mulk', _mulk),
      });
      if (mounted) setState(() => _saveState = 'saved');
    } catch (e) {
      if (mounted) {
        setState(() => _saveState = '');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur enregistrement : $e')));
      }
    }
  }

  Future<void> _pickTime(_Item it) async {
    final t = await showTimePicker(context: context, initialTime: it.time);
    if (t != null) {
      setState(() => it.time = t);
      _scheduleSave();
    }
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    required _Item item,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Switch(
                  value: item.enabled,
                  onChanged: (v) {
                    setState(() => item.enabled = v);
                    _scheduleSave();
                  },
                ),
              ],
            ),
            if (item.enabled) ...[
              const Divider(height: 20),
              // Heure
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 20),
                  const SizedBox(width: 8),
                  const Text('Heure'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _pickTime(item),
                    child: Text(item.time.format(context),
                        style: const TextStyle(fontSize: 18)),
                  ),
                ],
              ),
              // Volume
              Row(
                children: [
                  const Icon(Icons.volume_up_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: item.volume.toDouble(),
                      min: 0,
                      max: 30,
                      divisions: 30,
                      label: '${item.volume}',
                      onChanged: (v) =>
                          setState(() => item.volume = v.round()),
                      onChangeEnd: (_) => _scheduleSave(),
                    ),
                  ),
                  SizedBox(
                      width: 28,
                      child: Text('${item.volume}',
                          textAlign: TextAlign.end)),
                ],
              ),
              const SizedBox(height: 8),
              // Jours
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 18),
                  const SizedBox(width: 8),
                  const Text('Jours'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: List.generate(7, (i) {
                        final on = (item.days >> i) & 1 == 1;
                        return GestureDetector(
                          onTap: () {
                            setState(() => item.days ^= (1 << i));
                            _scheduleSave();
                          },
                          child: CircleAvatar(
                            radius: 15,
                            backgroundColor: on
                                ? theme.colorScheme.primary
                                : theme.disabledColor.withValues(alpha: 0.15),
                            child: Text(
                              _dayLabels[i],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: on
                                    ? theme.colorScheme.onPrimary
                                    : theme.textTheme.bodyMedium?.color,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Azkar & Coran'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                _saveState == 'saving'
                    ? 'Enregistrement…'
                    : _saveState == 'saved'
                        ? 'Enregistré ✓'
                        : '',
                style: const TextStyle(fontSize: 13, color: Colors.green),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: _load, child: const Text('Réessayer')),
                ]))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Azkar',
                        style: Theme.of(context).textTheme.headlineSmall),
                    _card(
                        icon: Icons.wb_sunny_rounded,
                        title: 'Azkar du matin (Sabah)',
                        subtitle: 'Invocations du matin',
                        item: _sabah),
                    _card(
                        icon: Icons.nights_stay_rounded,
                        title: 'Azkar du soir (Masaa)',
                        subtitle: 'Invocations du soir',
                        item: _masaa),
                    const SizedBox(height: 16),
                    Text('Coran',
                        style: Theme.of(context).textTheme.headlineSmall),
                    _card(
                        icon: Icons.menu_book_rounded,
                        title: 'Sourate Al-Kahf',
                        subtitle: 'Traditionnellement le vendredi',
                        item: _kahf),
                    _card(
                        icon: Icons.bedtime_rounded,
                        title: 'Sourate Al-Mulk',
                        subtitle: 'Traditionnellement avant de dormir',
                        item: _mulk),
                    const SizedBox(height: 24),
                    Text(
                      'Les modifications sont enregistrées automatiquement.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
    );
  }
}
