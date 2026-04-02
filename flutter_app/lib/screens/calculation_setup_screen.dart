import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../models/prayer_time.dart';
import '../providers/adhanbox_provider.dart';
import '../theme/app_theme.dart';

class CalculationSetupScreen extends ConsumerStatefulWidget {
  const CalculationSetupScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CalculationSetupScreen> createState() => _CalculationSetupScreenState();
}

class _CalculationSetupScreenState extends ConsumerState<CalculationSetupScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _deviceIp;

  String _method = 'mwl';
  int _school = 0;

  final Map<String, int> _offsets = {
    'fajr': 0, 'sunrise': 0, 'dhuhr': 0,
    'asr': 0, 'maghrib': 0, 'isha': 0,
  };

  Map<String, String> _basePreviewTimes = {};
  Map<String, String> _previewTimes = {};

  static const _methods = {
    'mwl':     'Ligue islamique mondiale (MWL)',
    'karachi': 'Sciences islamiques — Karachi',
    'uoif':    'UOIF — France',
    'egypt':   'Autorité égyptienne de sondage',
    'isna':    'ISNA — Amérique du Nord',
  };

  static const _schools = {
    0: 'École Shafi (standard)',
    1: 'École Hanafi',
  };

  static const _prayerNames = {
    'fajr': 'Fajr', 'sunrise': 'Chourouk', 'dhuhr': 'Dhuhr',
    'asr': 'Asr', 'maghrib': 'Maghrib', 'isha': 'Isha',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIpAndConfig());
  }

  Future<void> _loadIpAndConfig() async {
    try {
      final ip = ref.read(currentDeviceIpProvider);
      if (ip == null) {
        setState(() { _errorMessage = 'Aucun appareil configuré'; _isLoading = false; });
        return;
      }
      setState(() => _deviceIp = ip);
      await _loadConfiguration();
    } catch (e) {
      setState(() { _errorMessage = 'Erreur: $e'; _isLoading = false; });
    }
  }

  Future<void> _loadConfiguration() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      // Méthode de calcul
      try {
        final r = await http.get(Uri.parse('http://$_deviceIp/api/calculation/config'))
            .timeout(const Duration(seconds: 5));
        if (r.statusCode == 200) {
          final d = jsonDecode(r.body);
          final m = (d['method'] ?? 'mwl').toString().toLowerCase();
          setState(() {
            _method = _methods.containsKey(m) ? m : 'mwl';
            _school = d['school'] ?? 0;
          });
        }
      } catch (_) {}

      // Offsets
      try {
        final r = await http.get(Uri.parse('http://$_deviceIp/api/mawaqit/offsets'))
            .timeout(const Duration(seconds: 5));
        if (r.statusCode == 200) {
          final d = jsonDecode(r.body);
          setState(() {
            for (final k in _offsets.keys) _offsets[k] = d[k] ?? 0;
          });
        }
      } catch (_) {}

      try { await _loadPreview(); } catch (_) {}
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() { _errorMessage = 'Erreur de connexion'; _isLoading = false; });
    }
  }

  Future<void> _loadPreview() async {
    if (_deviceIp == null) return;
    final r = await http.get(Uri.parse('http://$_deviceIp/prayer_times'))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode == 200) {
      final d = jsonDecode(r.body);
      final base = {
        for (final k in _offsets.keys) k: _addMins((d[k] ?? '--:--').toString(), -(_offsets[k] ?? 0)),
      };
      setState(() {
        _basePreviewTimes = base;
        _previewTimes = _applyOffsets(base);
      });
    }
  }

  Future<void> _refreshPreview() async {
    if (_deviceIp == null) return;
    try {
      await http.post(
        Uri.parse('http://$_deviceIp/api/calculation/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'method': _method, 'school': _school}),
      ).timeout(const Duration(seconds: 6));
      await _loadPreview();
    } catch (_) {}
  }

  Map<String, String> _applyOffsets(Map<String, String> base) {
    return {for (final k in _prayerNames.keys) k: _addMins(base[k] ?? '--:--', _offsets[k] ?? 0)};
  }

  String _addMins(String time, int delta) {
    final p = time.split(':');
    if (p.length != 2) return time;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    if (h == null || m == null) return time;
    var t = h * 60 + m + delta;
    t = ((t % 1440) + 1440) % 1440;
    return '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
  }

  Map<String, String> _fromPrayerTimes(PrayerTimes? pt) {
    if (pt == null) return {};
    final r = <String, String>{};
    for (final p in pt.times) {
      final k = p.name.toLowerCase();
      if (k.contains('fajr')) r['fajr'] = p.calculatedTime;
      if (k.contains('sunrise') || k.contains('chour') || k.contains('shuru')) r['sunrise'] = p.calculatedTime;
      if (k.contains('dhuhr') || k.contains('dohr')) r['dhuhr'] = p.calculatedTime;
      if (k.contains('asr')) r['asr'] = p.calculatedTime;
      if (k.contains('maghrib')) r['maghrib'] = p.calculatedTime;
      if (k.contains('isha')) r['isha'] = p.calculatedTime;
    }
    return r;
  }

  Future<void> _save() async {
    setState(() { _isSaving = true; _errorMessage = null; });
    try {
      if (_deviceIp == null) throw Exception('Aucun appareil connecté');
      final r = await http.post(
        Uri.parse('http://$_deviceIp/api/calculation/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'method': _method, 'school': _school}),
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw Exception('HTTP ${r.statusCode}');
      }
      try {
        await http.post(
          Uri.parse('http://$_deviceIp/api/mawaqit/offsets'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(_offsets),
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}

      // Prepare fresh preview times from updated base
      await _loadPreview();

      // Refresh providers
      ref.invalidate(prayerTimesProvider);
      ref.invalidate(prayerOffsetsProvider);
      // Wait for fresh adjusted times so all watchers (HomeScreen, etc.) have new data
      try { await ref.read(adjustedPrayerTimesProvider.future); } catch (_) {}
      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration enregistrée'), backgroundColor: AppTheme.emerald),
        );
      }
    } catch (e) {
      setState(() { _errorMessage = e.toString(); _isSaving = false; });
    }
  }

  // ─────────────────────────── BUILD ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final providerPreview = _fromPrayerTimes(ref.watch(prayerTimesProvider).valueOrNull);
    if (_basePreviewTimes.isEmpty && providerPreview.isNotEmpty && _previewTimes.isEmpty) {
      _basePreviewTimes = Map.from(providerPreview);
      _previewTimes = _applyOffsets(_basePreviewTimes);
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── AppBar ──
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: AppTheme.emeraldDeep,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _PreviewHeader(
                previewTimes: _previewTimes.isNotEmpty ? _previewTimes : providerPreview,
                deviceIp: _deviceIp,
              ),
            ),
            title: Text(
              'Horaires de Prière',
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
                  // Erreur
                  if (_errorMessage != null) ...[
                    _ErrorBanner(message: _errorMessage!),
                    const SizedBox(height: 16),
                  ],

                  // ── Méthode ──
                  _SectionLabel(label: 'Méthode de calcul', icon: Icons.calculate_rounded),
                  const SizedBox(height: 10),
                  _SelectCard(
                    items: _methods.entries.map((e) => _SelectItem(key: e.key, label: e.value)).toList(),
                    selected: _method,
                    onSelect: (k) { setState(() => _method = k); _refreshPreview(); },
                  ).animate().fadeIn(delay: 50.ms).slideY(begin: 0.06),

                  const SizedBox(height: 24),

                  // ── École ──
                  _SectionLabel(label: 'École juridique', icon: Icons.school_rounded),
                  const SizedBox(height: 10),
                  _SelectCard(
                    items: _schools.entries.map((e) => _SelectItem(key: e.key.toString(), label: e.value)).toList(),
                    selected: _school.toString(),
                    onSelect: (k) { setState(() => _school = int.parse(k)); _refreshPreview(); },
                  ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.06),

                  const SizedBox(height: 24),

                  // ── Ajustements ──
                  _SectionLabel(label: 'Ajustements fins', icon: Icons.tune_rounded),
                  const SizedBox(height: 4),
                  Text(
                    'Décalez chaque horaire de ±30 minutes si nécessaire.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),

                  ..._prayerNames.keys.indexed.map((entry) {
                    final (i, prayer) = entry;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OffsetCard(
                        prayer: prayer,
                        name: _prayerNames[prayer]!,
                        offset: _offsets[prayer]!,
                        baseTime: _basePreviewTimes[prayer] ?? providerPreview[prayer] ?? '--:--',
                        adjustedTime: _previewTimes[prayer] ?? '--:--',
                        onChanged: (v) {
                          setState(() {
                            _offsets[prayer] = v;
                            final src = _basePreviewTimes.isNotEmpty ? _basePreviewTimes : providerPreview;
                            _previewTimes = _applyOffsets(src);
                          });
                        },
                      ).animate().fadeIn(delay: Duration(milliseconds: 120 + 40 * i)).slideY(begin: 0.06),
                    );
                  }),

                  const SizedBox(height: 24),

                  // ── Bouton ──
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
                          : const Text('Enregistrer la configuration'),
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

// ─────────────────────────── PREVIEW HEADER ───────────────────────────
class _PreviewHeader extends StatelessWidget {
  final Map<String, String> previewTimes;
  final String? deviceIp;
  const _PreviewHeader({required this.previewTimes, this.deviceIp});

  static const _icons = {
    'fajr': Icons.wb_twilight_rounded,
    'sunrise': Icons.wb_sunny_outlined,
    'dhuhr': Icons.wb_sunny_rounded,
    'asr': Icons.light_mode_rounded,
    'maghrib': Icons.nightlight_round,
    'isha': Icons.dark_mode_rounded,
  };

  static const _names = {
    'fajr': 'Fajr', 'sunrise': 'Chourouk', 'dhuhr': 'Dhuhr',
    'asr': 'Asr', 'maghrib': 'Maghrib', 'isha': 'Isha',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF064E3B), Color(0xFF065F46), Color(0xFF059669)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: ['fajr', 'sunrise', 'dhuhr'].map((p) => Expanded(child: _PreviewCell(prayer: p, time: previewTimes[p] ?? '--:--', icon: _icons[p]!, name: _names[p]!))).toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: ['asr', 'maghrib', 'isha'].map((p) => Expanded(child: _PreviewCell(prayer: p, time: previewTimes[p] ?? '--:--', icon: _icons[p]!, name: _names[p]!))).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCell extends StatelessWidget {
  final String prayer, time, name;
  final IconData icon;
  const _PreviewCell({required this.prayer, required this.time, required this.icon, required this.name});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(name, style: GoogleFonts.inter(color: Colors.white60, fontSize: 10)),
        const SizedBox(height: 2),
        Text(time, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}

// ─────────────────────────── SELECT CARD ───────────────────────────
class _SelectItem {
  final String key, label;
  const _SelectItem({required this.key, required this.label});
}

class _SelectCard extends StatelessWidget {
  final List<_SelectItem> items;
  final String selected;
  final ValueChanged<String> onSelect;
  const _SelectCard({required this.items, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final isLast = e.key == items.length - 1;
          final item = e.value;
          final isSelected = selected == item.key;
          return InkWell(
            onTap: () => onSelect(item.key),
            borderRadius: isLast
                ? const BorderRadius.vertical(bottom: Radius.circular(16))
                : BorderRadius.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: 200.ms,
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? AppTheme.emerald : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                            width: isSelected ? 2 : 1.5,
                          ),
                        ),
                        child: isSelected
                            ? Center(
                                child: Container(
                                  width: 10, height: 10,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.emerald,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          item.label,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isSelected
                                ? (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)
                                : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    indent: 52,
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────── OFFSET CARD ───────────────────────────
class _OffsetCard extends StatelessWidget {
  final String prayer, name, baseTime, adjustedTime;
  final int offset;
  final ValueChanged<int> onChanged;
  const _OffsetCard({
    required this.prayer, required this.name, required this.offset,
    required this.baseTime, required this.adjustedTime, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = AppTheme.prayerColor(name);
    final icon = AppTheme.prayerIcon(name);
    final hasOffset = offset != 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasOffset
              ? AppTheme.emerald.withOpacity(0.4)
              : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(isDark ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      hasOffset ? '$baseTime → $adjustedTime' : baseTime,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: hasOffset ? AppTheme.emerald : null,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: 200.ms,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hasOffset
                      ? AppTheme.emerald.withOpacity(0.12)
                      : (isDark ? AppTheme.darkSurface : AppTheme.lightBg),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasOffset ? AppTheme.emerald.withOpacity(0.3) : Colors.transparent,
                  ),
                ),
                child: Text(
                  offset == 0 ? '0' : '${offset > 0 ? '+' : ''}${offset}\'',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: hasOffset ? AppTheme.emerald : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: offset.toDouble(),
            min: -30, max: 30, divisions: 60,
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── HELPERS ───────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.emerald, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppTheme.emerald),
        ),
      ],
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
