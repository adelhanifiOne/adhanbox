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

class AdhanScreen extends ConsumerStatefulWidget {
  const AdhanScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AdhanScreen> createState() => _AdhanScreenState();
}

class _AdhanScreenState extends ConsumerState<AdhanScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _deviceIp;

  // null = rien en lecture, autrement = clé prière en cours de test
  String? _testingPrayer;
  Timer? _testTimer;

  double _volume = 20;
  bool _isLoadingVolume = false;

  final Map<String, int> _selectedTracks = {
    'fajr': 2, 'dhuhr': 4, 'asr': 4, 'maghrib': 4, 'isha': 4,
  };

  final Map<String, bool> _playDuaa = {
    'fajr': true, 'dhuhr': true, 'asr': true, 'maghrib': true, 'isha': true,
  };

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _testTimer?.cancel();
    super.dispose();
  }

  Future<String?> _resolveApiToken(String deviceIp) async {
    final cached = ref.read(adhanboxApiKeyProvider);
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final r = await http.get(Uri.parse('http://$deviceIp/api/device/info'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        final token = (jsonDecode(r.body) as Map<String, dynamic>?)?['token'] as String?;
        if (token != null && token.isNotEmpty) {
          ref.read(adhanboxApiKeyProvider.notifier).state = token;
          return token;
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, String> _headersWithToken(String? token) => {
    'Content-Type': 'application/json',
    if (token != null && token.isNotEmpty) 'X-API-Key': token,
  };

  Future<void> _load() async {
    final ip = ref.read(currentDeviceIpProvider);
    if (ip == null) {
      setState(() { _errorMessage = 'Aucun appareil configuré'; _isLoading = false; });
      return;
    }
    setState(() { _deviceIp = ip; _isLoading = true; _errorMessage = null; _isLoadingVolume = true; });

    await Future.wait([
      _loadAdhanConfig(ip),
      _loadVolume(ip),
    ]);

    if (mounted) setState(() { _isLoading = false; _isLoadingVolume = false; });
  }

  Future<void> _loadAdhanConfig(String ip) async {
    try {
      final r = await http.get(Uri.parse('http://$ip/api/adhan/config'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        if (mounted) setState(() {
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
        });
      }
    } catch (_) {}
  }

  Future<void> _loadVolume(String ip) async {
    try {
      final r = await http.get(Uri.parse('http://$ip/get_volume'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        if (mounted) setState(() => _volume = ((d['vol'] as num?) ?? 20).toDouble());
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() { _isSaving = true; _errorMessage = null; });
    try {
      if (_deviceIp == null) throw Exception('Aucun appareil connecté');
      final token = await _resolveApiToken(_deviceIp!);
      final payload = {
        for (final k in _selectedTracks.keys) '${k}_track': _selectedTracks[k],
        for (final k in _playDuaa.keys) '${k}_duaa': _playDuaa[k],
      };
      final r = await http.post(
        Uri.parse('http://$_deviceIp/api/adhan/config'),
        headers: _headersWithToken(token),
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw Exception('Échec HTTP ${r.statusCode}');
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

  Future<void> _testPlay(String prayerKey) async {
    if (_deviceIp == null) return;
    // Si on teste déjà ce même bouton, on stop
    if (_testingPrayer == prayerKey) {
      await _stop();
      return;
    }
    // Arrêter la lecture précédente si nécessaire
    if (_testingPrayer != null) await _stop(skipState: true);

    setState(() => _testingPrayer = prayerKey);
    _testTimer?.cancel();
    // Auto-reset après 3min (durée max d'un adhan)
    _testTimer = Timer(const Duration(minutes: 3), () {
      if (mounted) setState(() => _testingPrayer = null);
    });

    try {
      final track = _selectedTracks[prayerKey] ?? 4;
      await http.get(Uri.parse('http://$_deviceIp/play?track=$track'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      if (mounted) setState(() => _testingPrayer = null);
    }
  }

  Future<void> _stop({bool skipState = false}) async {
    _testTimer?.cancel();
    if (!skipState && mounted) setState(() => _testingPrayer = null);
    if (_deviceIp == null) return;
    try {
      await http.get(Uri.parse('http://$_deviceIp/stopplay'))
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Recharge automatiquement quand le device devient disponible après l'init
    ref.listen<String?>(currentDeviceIpProvider, (prev, next) {
      if (next != null && _deviceIp == null) _load();
    });

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.emeraldDeep,
            title: Text(
              'Adhan',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
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

                  // ── Volume ─────────────────────────────────────────
                  _SectionLabel('Volume'),
                  const SizedBox(height: 8),
                  _VolumeCard(
                    volume: _volume,
                    isLoading: _isLoadingVolume,
                    onChanged: (v) => setState(() => _volume = v),
                    onChangeEnd: (v) async {
                      if (_deviceIp == null) return;
                      try {
                        final token = await _resolveApiToken(_deviceIp!);
                        await http.post(
                          Uri.parse('http://$_deviceIp/set_volume'),
                          headers: _headersWithToken(token),
                          body: jsonEncode({'vol': v.toInt()}),
                        ).timeout(const Duration(seconds: 5));
                      } catch (_) {}
                    },
                  ).animate().fadeIn(duration: 300.ms),

                  const SizedBox(height: 24),

                  // ── Adhans ─────────────────────────────────────────
                  _SectionLabel('Appel à la prière'),
                  const SizedBox(height: 8),

                  ..._prayerMeta.entries.indexed.map((e) {
                    final (i, entry) = e;
                    final key = entry.key;
                    final meta = entry.value;
                    final isTesting = _testingPrayer == key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PrayerAdhanCard(
                        prayerKey: key,
                        meta: meta,
                        selectedTrack: _selectedTracks[key]!,
                        playDuaa: _playDuaa[key]!,
                        isTesting: isTesting,
                        onTrackChanged: (v) => setState(() => _selectedTracks[key] = v),
                        onDuaaChanged: (v) => setState(() => _playDuaa[key] = v),
                        onTest: () => _testPlay(key),
                      ).animate().fadeIn(delay: Duration(milliseconds: 60 * i)).slideY(begin: 0.06),
                    );
                  }),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
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

// ─── VOLUME CARD ──────────────────────────────────────────────────
class _VolumeCard extends StatelessWidget {
  final double volume;
  final bool isLoading;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  const _VolumeCard({
    required this.volume,
    required this.isLoading,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.asrColor.withOpacity(isDark ? 0.18 : 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.volume_up_rounded, color: AppTheme.asrColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Volume', style: Theme.of(context).textTheme.titleMedium),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald),
                  )
                else
                  Text(
                    '${volume.toInt()} / 30',
                    style: GoogleFonts.poppins(
                      color: AppTheme.emerald,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            Slider(
              value: volume,
              min: 0,
              max: 30,
              divisions: 30,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── PRAYER ADHAN CARD ────────────────────────────────────────────
class _PrayerAdhanCard extends StatelessWidget {
  final String prayerKey;
  final _PrayerMeta meta;
  final int selectedTrack;
  final bool playDuaa;
  final bool isTesting;
  final ValueChanged<int> onTrackChanged;
  final ValueChanged<bool> onDuaaChanged;
  final VoidCallback onTest;

  const _PrayerAdhanCard({
    required this.prayerKey,
    required this.meta,
    required this.selectedTrack,
    required this.playDuaa,
    required this.isTesting,
    required this.onTrackChanged,
    required this.onDuaaChanged,
    required this.onTest,
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
          // Header with test/stop button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(isDark ? 0.18 : 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(meta.icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(meta.name, style: Theme.of(context).textTheme.titleMedium),
                ),
                // Test / Stop toggle button
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isTesting
                      ? IconButton(
                          key: const ValueKey('stop'),
                          icon: const Icon(Icons.stop_circle_rounded, size: 30),
                          color: Colors.red[400],
                          tooltip: 'Arrêter',
                          onPressed: onTest,
                        )
                      : IconButton(
                          key: const ValueKey('play'),
                          icon: const Icon(Icons.play_circle_rounded, size: 30),
                          color: AppTheme.emerald,
                          tooltip: 'Tester',
                          onPressed: onTest,
                        ),
                ),
              ],
            ),
          ),

          Divider(height: 1, indent: 16, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),

          // Track dropdown
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
            padding: const EdgeInsets.fromLTRB(4, 0, 16, 8),
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
        ],
      ),
    );
  }
}

// ─── HELPERS ─────────────────────────────────────────────────────
class _PrayerMeta {
  final String name;
  final IconData icon;
  const _PrayerMeta(this.name, this.icon);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
      ),
    );
  }
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
