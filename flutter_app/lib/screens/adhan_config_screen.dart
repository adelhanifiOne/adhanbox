import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../providers/adhanbox_provider.dart';
import '../theme/app_theme.dart';

const _trackNames = {
  2:  'Adhan 1',
  3:  'Adhan 2',
  4:  'Adhan 1',
  5:  'Adhan 2',
  6:  'Adhan 3',
  7:  'Adhan 4',
  8:  'Adhan 5',
  9:  'Adhan 6',
  10: 'Adhan 7',
  11: 'Adhan 8',
  12: 'Adhan 9',
  13: 'Adhan 10',
  14: 'Adhan 11',
  15: 'Adhan 12',
  16: 'Adhan 13',
  17: 'Adhan 14',
  18: 'Adhan 15',
  19: 'Adhan 16',
  20: 'Adhan 17',
  21: 'Adhan 18',
};

class AdhanConfigScreen extends ConsumerStatefulWidget {
  const AdhanConfigScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AdhanConfigScreen> createState() => _AdhanConfigScreenState();
}

class _AdhanConfigScreenState extends ConsumerState<AdhanConfigScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _deviceIp;

  final Map<String, int> _selectedTracks = {
    'fajr': 2, 'dhuhr': 4, 'asr': 4, 'maghrib': 4, 'isha': 4,
  };

  final Map<String, bool> _playDuaa = {
    'fajr': true, 'dhuhr': true, 'asr': true, 'maghrib': true, 'isha': true,
  };

  final Map<String, bool> _enabledPrayers = {
    'fajr': true, 'dhuhr': true, 'asr': true, 'maghrib': true, 'isha': true,
  };

  final Map<String, int> _selectedVolumes = {
    'fajr': 20, 'dhuhr': 20, 'asr': 20, 'maghrib': 20, 'isha': 20,
  };

  String? _playingKey;
  int _globalVolume = 20;
  Timer? _volumeDebounce;

  static const _prayerMeta = {
    'fajr':    _PrayerMeta('Fajr',    Icons.wb_twilight_rounded),
    'dhuhr':   _PrayerMeta('Dhuhr',   Icons.wb_sunny_rounded),
    'asr':     _PrayerMeta('Asr',     Icons.light_mode_rounded),
    'maghrib': _PrayerMeta('Maghrib', Icons.nightlight_round),
    'isha':    _PrayerMeta('Isha',    Icons.dark_mode_rounded),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConfiguration());
  }

  @override
  void dispose() {
    _volumeDebounce?.cancel();
    super.dispose();
  }

  void _onGlobalVolumeChanged(int vol) {
    setState(() => _globalVolume = vol);
    _volumeDebounce?.cancel();
    _volumeDebounce = Timer(const Duration(milliseconds: 300), () => _sendGlobalVolume(vol));
  }

  Future<void> _sendGlobalVolume(int vol) async {
    if (_deviceIp == null) return;
    final apiKey = ref.read(adhanboxApiKeyProvider);
    try {
      await http.post(
        Uri.parse('http://$_deviceIp/set_volume'),
        headers: {
          'Content-Type': 'application/json',
          if (apiKey != null) 'Authorization': 'Bearer $apiKey',
          if (apiKey != null) 'X-API-Key': apiKey,
        },
        body: jsonEncode({'vol': vol}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> _loadConfiguration() async {
    final ip = ref.read(currentDeviceIpProvider);
    if (ip == null) {
      setState(() { _errorMessage = 'Aucun appareil configuré'; _isLoading = false; });
      return;
    }
    setState(() {
      _deviceIp = ip;
      _errorMessage = null; // Clear old error banner on new load
      _isLoading = true;
    });
    try {
      final results = await Future.wait([
        http.get(Uri.parse('http://$ip/api/adhan/config')).timeout(const Duration(seconds: 10)),
        http.get(Uri.parse('http://$ip/get_volume')).timeout(const Duration(seconds: 5)),
      ]);
      final r = results[0];
      final rVol = results[1];
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        int globalVol = _globalVolume;
        if (rVol.statusCode == 200) {
          final dv = jsonDecode(rVol.body);
          globalVol = (dv['vol'] as num?)?.toInt() ?? 20;
        }
        setState(() {
          _globalVolume = globalVol;
          for (final k in _selectedTracks.keys) {
            int raw = d['${k}_track'] as int? ?? (k == 'fajr' ? 2 : 4);
            if (k == 'fajr') {
              if (raw != 2 && raw != 3) raw = 2;
            } else {
              if (raw < 4 || raw > 21) raw = 4;
            }
            _selectedTracks[k] = raw;
          }
          for (final k in _playDuaa.keys) {
            _playDuaa[k] = d['${k}_duaa'] as bool? ?? true;
          }
          for (final k in _enabledPrayers.keys) {
            _enabledPrayers[k] = d['${k}_enabled'] as bool? ?? true;
          }
          for (final k in _selectedVolumes.keys) {
            _selectedVolumes[k] = (d['${k}_volume'] as num?)?.toInt() ?? 20;
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur de chargement (HTTP ${r.statusCode})'),
              backgroundColor: Colors.orange[800],
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (_) {
      // Appareil injoignable au chargement : on garde silencieusement les
      // valeurs par défaut (plus de bandeau orange).
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    setState(() { _isSaving = true; _errorMessage = null; });
    try {
      if (_deviceIp == null) throw Exception('Aucun appareil connecté');
      final payload = {
        for (final k in _selectedTracks.keys) '${k}_track': _selectedTracks[k],
        for (final k in _playDuaa.keys) '${k}_duaa': _playDuaa[k],
        for (final k in _enabledPrayers.keys) '${k}_enabled': _enabledPrayers[k],
        for (final k in _selectedVolumes.keys) '${k}_volume': _selectedVolumes[k],
      };
      final apiKey = ref.read(adhanboxApiKeyProvider);
      final r = await http.post(
        Uri.parse('http://$_deviceIp/api/adhan/config'),
        headers: {
          'Content-Type': 'application/json',
          if (apiKey != null) 'Authorization': 'Bearer $apiKey',
          if (apiKey != null) 'X-API-Key': apiKey,
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw Exception('Échec (HTTP ${r.statusCode})');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration enregistrée'),
            backgroundColor: AppTheme.emerald,
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Impossible de sauvegarder: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _playPreview(String key, int track, int volume) async {
    if (_deviceIp == null) return;
    setState(() => _playingKey = key);
    try {
      await http.get(Uri.parse('http://$_deviceIp/play?track=$track&volume=$volume'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> _stopPreview() async {
    setState(() => _playingKey = null);
    if (_deviceIp == null) return;
    try {
      await http.get(Uri.parse('http://$_deviceIp/stopplay'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Watch currentDeviceIpProvider so we reactively listen to IP updates
    ref.listen<String?>(currentDeviceIpProvider, (prev, next) {
      if (next != null && next != _deviceIp) {
        _loadConfiguration();
      } else if (next == null) {
        setState(() {
          _deviceIp = null;
          _errorMessage = 'Aucun appareil configuré';
        });
      }
    });

    // Handle case where IP resolved after first stack initialization but before listener registered
    final currentIp = ref.watch(currentDeviceIpProvider);
    if (currentIp != null && _deviceIp == null && !_isLoading && _errorMessage == 'Aucun appareil configuré') {
      Future.microtask(() => _loadConfiguration());
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.emeraldDeep,
            title: Text(
              'Appel à la prière',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppTheme.emerald)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_errorMessage != null) ...[
                    _ErrorBanner(message: _errorMessage!),
                    const SizedBox(height: 16),
                  ],

                  Text(
                    'Choisissez l\'appel à la prière joué pour chaque prière.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),

                  // ── Volume général live ──
                  _GlobalVolumeCard(
                    volume: _globalVolume,
                    onChanged: _deviceIp != null ? _onGlobalVolumeChanged : null,
                  ),
                  const SizedBox(height: 16),

                  ..._prayerMeta.entries.indexed.map((e) {
                    final (i, entry) = e;
                    final key = entry.key;
                    final meta = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PrayerAdhanCard(
                        prayerKey: key,
                        meta: meta,
                        selectedTrack: _selectedTracks[key]!,
                        playDuaa: _playDuaa[key]!,
                        enabled: _enabledPrayers[key]!,
                        volume: _selectedVolumes[key]!,
                        onTrackChanged: (v) => setState(() => _selectedTracks[key] = v),
                        onDuaaChanged: (v) => setState(() => _playDuaa[key] = v),
                        onEnabledChanged: (v) => setState(() => _enabledPrayers[key] = v),
                        onVolumeChanged: (v) => setState(() => _selectedVolumes[key] = v),
                        isPlaying: _playingKey == key,
                        onPreview: () => _playPreview(key, _selectedTracks[key]!, _selectedVolumes[key]!),
                        onStop: _stopPreview,
                      ).animate().fadeIn(delay: Duration(milliseconds: 60 * i)).slideY(begin: 0.06),
                    );
                  }),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Enregistrer'),
                    ),
                  ).animate().fadeIn(delay: 350.ms),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────── PRAYER ADHAN CARD ───────────────────────────
class _PrayerAdhanCard extends StatelessWidget {
  final String prayerKey;
  final _PrayerMeta meta;
  final int selectedTrack;
  final bool playDuaa;
  final bool enabled;
  final int volume;
  final ValueChanged<int> onTrackChanged;
  final ValueChanged<bool> onDuaaChanged;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onVolumeChanged;
  final bool isPlaying;
  final VoidCallback onPreview;
  final VoidCallback onStop;

  const _PrayerAdhanCard({
    required this.prayerKey,
    required this.meta,
    required this.selectedTrack,
    required this.playDuaa,
    required this.enabled,
    required this.volume,
    required this.onTrackChanged,
    required this.onDuaaChanged,
    required this.onEnabledChanged,
    required this.onVolumeChanged,
    required this.isPlaying,
    required this.onPreview,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = AppTheme.prayerColor(meta.name);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => onEnabledChanged(!enabled),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: enabled
                              ? color.withOpacity(isDark ? 0.18 : 0.1)
                              : Colors.grey.withOpacity(isDark ? 0.15 : 0.08),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          meta.icon,
                          color: enabled ? color : (isDark ? Colors.grey[500] : Colors.grey[400]),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        meta.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: enabled ? null : (isDark ? Colors.grey[500] : Colors.grey[400]),
                          decoration: enabled ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Actions: Preview + Enable switch
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (enabled)
                      IconButton(
                        icon: Icon(
                          isPlaying ? Icons.stop_circle_rounded : Icons.play_circle_rounded,
                          size: 28,
                        ),
                        color: isPlaying ? Colors.redAccent : AppTheme.emerald,
                        tooltip: isPlaying ? 'Arrêter' : 'Écouter',
                        onPressed: isPlaying ? onStop : onPreview,
                      ),
                    Switch.adaptive(
                      value: enabled,
                      activeColor: AppTheme.emerald,
                      onChanged: onEnabledChanged,
                    ),
                  ],
                ),
              ],
            ),
          ),

          Divider(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),

          // Card contents (grayed out and disabled when not enabled)
          Opacity(
            opacity: enabled ? 1.0 : 0.45,
            child: IgnorePointer(
              ignoring: !enabled,
              child: Column(
                children: [
                  // Track selector
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Adhan', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<int>(
                          value: selectedTrack,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                            ),
                            filled: true,
                            fillColor: isDark ? AppTheme.darkSurface : AppTheme.lightBg,
                          ),
                          items: _trackNames.entries
                              .where((e) {
                                if (prayerKey == 'fajr') {
                                  return e.key == 2 || e.key == 3;
                                } else {
                                  return e.key >= 4 && e.key <= 21;
                                }
                              })
                              .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                              .toList(),
                          onChanged: (v) { if (v != null) onTrackChanged(v); },
                        ),
                      ],
                    ),
                  ),

                  // Duaa toggle
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
                    child: Row(
                      children: [
                        Checkbox(
                          value: playDuaa,
                          activeColor: AppTheme.emerald,
                          onChanged: (v) { if (v != null) onDuaaChanged(v); },
                        ),
                        Expanded(
                          child: Text(
                            'Jouer la Doua après l\'adhan',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Volume slider
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Volume de l\'Adhan', style: Theme.of(context).textTheme.bodySmall),
                            Text('$volume / 30', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.volume_mute_rounded, size: 18, color: isDark ? Colors.grey[600] : Colors.grey[400]),
                            Expanded(
                              child: Slider(
                                value: volume.toDouble(),
                                min: 0,
                                max: 30,
                                divisions: 30,
                                activeColor: color,
                                inactiveColor: color.withOpacity(0.15),
                                onChanged: (v) => onVolumeChanged(v.toInt()),
                              ),
                            ),
                            Icon(Icons.volume_up_rounded, size: 18, color: color),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── HELPERS ───────────────────────────
class _PrayerMeta {
  final String name;
  final IconData icon;
  const _PrayerMeta(this.name, this.icon);
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.red, fontSize: 13))),
        ],
      ),
    );
  }
}

// ─────────────────────────── GLOBAL VOLUME CARD ───────────────────────────
class _GlobalVolumeCard extends StatelessWidget {
  final int volume;
  final ValueChanged<int>? onChanged;

  const _GlobalVolumeCard({required this.volume, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.volume_up_rounded, color: AppTheme.emerald, size: 20),
              const SizedBox(width: 10),
              Text('Volume général', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$volume / 30', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.volume_mute_rounded, size: 18, color: isDark ? Colors.grey[600] : Colors.grey[400]),
              Expanded(
                child: Slider(
                  value: volume.toDouble(),
                  min: 0,
                  max: 30,
                  divisions: 30,
                  activeColor: AppTheme.emerald,
                  onChanged: onChanged != null ? (v) => onChanged!(v.round()) : null,
                ),
              ),
              Icon(Icons.volume_up_rounded, size: 18, color: AppTheme.emerald),
            ],
          ),
          if (onChanged == null)
            Text('Connectez-vous à un appareil pour régler le volume', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
        ],
      ),
    );
  }
}
