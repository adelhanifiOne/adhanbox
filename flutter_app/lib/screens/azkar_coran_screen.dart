import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/adhanbox_provider.dart';
import 'quran_player_screen.dart';
import '../utils/friendly_error.dart';
import '../utils/autorisation.dart';

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
  /// Chemin en cours de lancement, pour n'animer que le bouton clique.
  String? _launching;
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
      // L'IP de l'appareil est renseignee de facon ASYNCHRONE au lancement
      // (autoReconnect, ~1-3s). Plutot que d'echouer des le 1er affichage, on
      // attend que l'API soit prete (jusqu'a ~6s) -> la page s'affiche sans avoir
      // a cliquer "Reessayer".
      var api = ref.read(adhanboxApiProvider);
      for (int i = 0; api == null && i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        api = ref.read(adhanboxApiProvider);
      }
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
      _error = messageAmical(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Auto-save débouncé : tout changement programme un envoi 600 ms plus tard.
  /// Lance la recitation tout de suite, sans toucher a la programmation.
  ///
  /// /api/audio/play ne fait que demarrer un fichier : l'heure, les jours et
  /// l'activation restent tels qu'ils sont enregistres dans la box. On ne
  /// declenche donc AUCUNE sauvegarde ici.
  Future<void> _playNow(_Item item, String path, String title) async {
    final api = ref.read(adhanboxApiProvider);
    if (api == null) {
      _snack('Aucun appareil connecte');
      return;
    }
    setState(() => _launching = path);
    try {
      await api.playFile(path, volume: item.volume);
      if (mounted) _snack('Lecture de $title sur votre AdhanBox');
    } catch (e) {
      if (mounted) {
        afficherErreurBox(context, ref, e,
            repli: 'La lecture n\'a pas demarre.',
            reessayer: () => _playNow(item, path, title));
      }
    } finally {
      if (mounted) setState(() => _launching = null);
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

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
        afficherErreurBox(context, ref, e,
            repli: "Impossible d'enregistrer vos réglages.");
      }
    }
  }

  void _pickTime(_Item it) {
    final initial = Duration(hours: it.time.hour, minutes: it.time.minute);
    showModalBottomSheet(
      context: context,
      builder: (_) => SizedBox(
        height: 260,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Annuler')),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTimerPicker(
                mode: CupertinoTimerPickerMode.hm,
                initialTimerDuration: initial,
                onTimerDurationChanged: (d) {
                  setState(() => it.time =
                      TimeOfDay(hour: d.inHours, minute: d.inMinutes % 60));
                  _scheduleSave();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    required _Item item,
    required String path,
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
                // Lecture immediate. Volontairement hors du bloc
                // `if (item.enabled)` : on doit pouvoir ecouter une recitation
                // meme quand l'automatisme est desactive.
                IconButton(
                  tooltip: 'Ecouter maintenant',
                  onPressed:
                      _launching != null ? null : () => _playNow(item, path, title),
                  icon: _launching == path
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Icon(Icons.play_circle_fill_rounded, size: 30),
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
                    // Affiche un pourcentage, envoie 0-30 a la box.
                    child: Slider(
                      value: (item.volume * 100 / 30).clamp(0, 100).toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '${(item.volume * 100 / 30).round()} %',
                      onChanged: (pct) => setState(
                          () => item.volume = (pct * 30 / 100).round()),
                      onChangeEnd: (_) => _scheduleSave(),
                    ),
                  ),
                  SizedBox(
                      width: 42,
                      child: Text('${(item.volume * 100 / 30).round()} %',
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
    // [ETAT REEL] Recharge les rappels (heures + activés/désactivés) depuis la
    // box quand on change d'AdhanBox -> réglages exacts de l'appareil sélectionné.
    ref.listen<String?>(currentDeviceIpProvider, (prev, next) {
      if (prev != next && next != null) {
        // Annule toute sauvegarde en attente (débounce) de l'ANCIENNE box :
        // sinon un réglage modifié juste avant le switch s'écrirait sur la NOUVELLE.
        _saveTimer?.cancel();
        _load();
      }
    });
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
                    // Accès au lecteur Coran (récitateurs + 114 sourates)
                    Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        leading: const Icon(Icons.menu_book_rounded, size: 28),
                        title: const Text('Écouter le Coran',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Récitateurs et sourates au choix'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const QuranPlayerScreen())),
                      ),
                    ),
                    Text('Azkar',
                        style: Theme.of(context).textTheme.headlineSmall),
                    _card(
                        icon: Icons.wb_sunny_rounded,
                        title: 'Azkar du matin (Sabah)',
                        subtitle: 'Invocations du matin',
                        item: _sabah,
                        path: '/azkar/sabah.mp3'),
                    _card(
                        icon: Icons.nights_stay_rounded,
                        title: 'Azkar du soir (Masaa)',
                        subtitle: 'Invocations du soir',
                        item: _masaa,
                        path: '/azkar/masaa.mp3'),
                    const SizedBox(height: 16),
                    Text('Coran',
                        style: Theme.of(context).textTheme.headlineSmall),
                    _card(
                        icon: Icons.menu_book_rounded,
                        title: 'Sourate Al-Kahf',
                        subtitle: 'Traditionnellement le vendredi',
                        item: _kahf,
                        path: '/quran/al-kahf.mp3'),
                    _card(
                        icon: Icons.bedtime_rounded,
                        title: 'Sourate Al-Mulk',
                        subtitle: 'Traditionnellement avant de dormir',
                        item: _mulk,
                        path: '/quran/al-mulk.mp3'),
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
