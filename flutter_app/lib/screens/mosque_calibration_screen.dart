import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../providers/adhanbox_provider.dart';
import '../services/mosque_fitting_service.dart';
import '../services/prayer_calculator.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────

class MosqueCalibrationScreen extends ConsumerStatefulWidget {
  const MosqueCalibrationScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<MosqueCalibrationScreen> createState() =>
      _MosqueCalibrationScreenState();
}

class _MosqueCalibrationScreenState
    extends ConsumerState<MosqueCalibrationScreen> {
  // ── État général ─────────────────────────────────────────────────────
  bool _loadingDevice = true;
  bool _fitting       = false;
  bool _applying      = false;
  String? _error;
  String? _deviceIp;

  // ── Paramètres appareil ──────────────────────────────────────────────
  double _lat = 48.8566;
  double _lon =  2.3522;
  int    _tz  = 60; // minutes UTC (ex: +1h = 60)

  // ── Saisie horaires mosquée ──────────────────────────────────────────
  // Clé → TimeOfDay (null si non saisi)
  final Map<String, TimeOfDay?> _entered = {
    'fajr': null, 'sunrise': null, 'dhuhr': null,
    'asr':  null, 'maghrib': null, 'isha':  null,
  };

  // ── Résultat fitting ─────────────────────────────────────────────────
  CalibrationResult? _result;

  // ── Config UI ────────────────────────────────────────────────────────
  static const _labels = {
    'fajr':    'Fajr',
    'sunrise': 'Chourouk',
    'dhuhr':   'Dhuhr',
    'asr':     'Asr',
    'maghrib': 'Maghrib',
    'isha':    'Isha',
  };

  static const _icons = {
    'fajr':    Icons.wb_twilight_rounded,
    'sunrise': Icons.wb_sunny_outlined,
    'dhuhr':   Icons.wb_sunny_rounded,
    'asr':     Icons.light_mode_rounded,
    'maghrib': Icons.nightlight_round,
    'isha':    Icons.dark_mode_rounded,
  };

  // ── Init ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDevice());
  }

  Future<void> _loadDevice() async {
    final ip = ref.read(currentDeviceIpProvider);
    if (ip == null) {
      setState(() { _error = 'Aucun appareil connecté.'; _loadingDevice = false; });
      return;
    }
    setState(() => _deviceIp = ip);

    try {
      // Récupérer la localisation stockée dans l'ESP32
      final locR = await http
          .get(Uri.parse('http://$ip/api/config/location'))
          .timeout(const Duration(seconds: 6));
      if (locR.statusCode == 200) {
        final d = jsonDecode(locR.body);
        _lat = (d['lat'] ?? _lat).toDouble();
        _lon = (d['lon'] ?? _lon).toDouble();
      }
    } catch (_) {}

    try {
      // Récupérer le fuseau horaire
      final tzR = await http
          .get(Uri.parse('http://$ip/api/config/timezone'))
          .timeout(const Duration(seconds: 5));
      if (tzR.statusCode == 200) {
        final d = jsonDecode(tzR.body);
        _tz = (d['tz_min'] ?? _tz).toInt();
      }
    } catch (_) {}

    setState(() => _loadingDevice = false);
  }

  // ── Saisie horaire ───────────────────────────────────────────────────
  Future<void> _pickTime(String prayer) async {
    final initial = _entered[prayer] ?? TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Horaire mosquée — ${_labels[prayer]}',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _entered[prayer] = picked);
  }

  void _clearTime(String prayer) => setState(() => _entered[prayer] = null);

  // ── Analyse / Fitting ─────────────────────────────────────────────────
  bool get _canFit =>
      _entered.values.where((t) => t != null).length >= 2 &&
      _entered['fajr'] != null &&
      _entered['isha'] != null;

  Future<void> _runFitting() async {
    setState(() { _fitting = true; _result = null; _error = null; });

    try {
      final now = DateTime.now();
      final mosqueTimes = <String, int?>{};
      for (final k in _entered.keys) {
        final t = _entered[k];
        mosqueTimes[k] = t != null ? t.hour * 60 + t.minute : null;
      }

      final result = await MosqueFittingService.fit(
        mosqueTimes: mosqueTimes,
        lat: _lat,
        lon: _lon,
        year: now.year, month: now.month, day: now.day,
        tzOffsetMinutes: _tz,
      );

      setState(() { _result = result; _fitting = false; });
    } catch (e) {
      setState(() { _error = 'Erreur : $e'; _fitting = false; });
    }
  }

  // ── Appliquer à l'ESP32 ───────────────────────────────────────────────
  Future<void> _apply() async {
    if (_result == null || _deviceIp == null) return;
    setState(() { _applying = true; _error = null; });

    try {
      final r = _result!;

      // 1. Méthode + angles
      await http.post(
        Uri.parse('http://$_deviceIp/api/calculation/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'method':      r.methodCode == 'custom' ? 'mwl' : r.methodCode,
          'school':      r.school,
          'fajr_angle':  r.fajrAngle,
          'isha_angle':  r.ishaAngle,
        }),
      ).timeout(const Duration(seconds: 10));

      // 2. Offsets résiduels
      await http.post(
        Uri.parse('http://$_deviceIp/api/mawaqit/offsets'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(r.residualOffsets),
      ).timeout(const Duration(seconds: 8));

      // 3. Rafraîchir les providers
      ref.invalidate(prayerTimesProvider);
      ref.invalidate(prayerOffsetsProvider);

      setState(() => _applying = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Configuration mosquée appliquée — ${r.methodName}'),
            backgroundColor: AppTheme.emerald,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() { _error = 'Erreur lors de l\'application : $e'; _applying = false; });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── AppBar ──────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: const Color(0xFF1E3A5F),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _CalibrationHeader(lat: _lat, lon: _lon, tz: _tz),
            ),
            title: Text(
              'Calibration Mosquée',
              style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          if (_loadingDevice)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppTheme.emerald)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  // ── Erreur ─────────────────────────────────────────
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],

                  // ── Explication ────────────────────────────────────
                  _InfoCard(
                    icon: Icons.info_outline_rounded,
                    text:
                      'Saisissez les horaires affichés par votre mosquée '
                      'pour aujourd\'hui. Le système va détecter '
                      'automatiquement la méthode de calcul utilisée — '
                      'plus besoin de fine-tuning à l\'avenir.',
                  ).animate().fadeIn(delay: 50.ms),

                  const SizedBox(height: 24),

                  // ── Saisie des horaires ────────────────────────────
                  _SectionLabel(
                    label: 'Horaires de la mosquée — aujourd\'hui',
                    icon: Icons.mosque_rounded,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fajr et Isha sont obligatoires. Les autres affinent l\'analyse.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),

                  ..._entered.keys.indexed.map((entry) {
                    final (i, prayer) = entry;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TimeEntryRow(
                        prayer: prayer,
                        label: _labels[prayer]!,
                        icon: _icons[prayer]!,
                        time: _entered[prayer],
                        required: prayer == 'fajr' || prayer == 'isha',
                        onTap: () => _pickTime(prayer),
                        onClear: _entered[prayer] != null ? () => _clearTime(prayer) : null,
                      ).animate().fadeIn(delay: Duration(milliseconds: 80 + 30 * i))
                       .slideY(begin: 0.05),
                    );
                  }),

                  const SizedBox(height: 20),

                  // ── Bouton Analyser ────────────────────────────────
                  if (!_canFit)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Saisissez au minimum Fajr et Isha pour lancer l\'analyse.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.gold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_canFit && !_fitting) ? _runFitting : null,
                      icon: _fitting
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search_rounded),
                      label: Text(_fitting ? 'Analyse en cours…' : 'Analyser'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF1E3A5F).withOpacity(0.4),
                      ),
                    ),
                  ).animate().fadeIn(delay: 300.ms),

                  // ── Résultats ──────────────────────────────────────
                  if (_result != null) ...[
                    const SizedBox(height: 32),
                    _ResultSection(
                      result: _result!,
                      mosqueTimes: _entered,
                      lat: _lat, lon: _lon, tz: _tz,
                      applying: _applying,
                      onApply: _apply,
                    ).animate().fadeIn(delay: 50.ms).slideY(begin: 0.06),
                  ],
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _CalibrationHeader extends StatelessWidget {
  final double lat, lon;
  final int tz;
  const _CalibrationHeader({required this.lat, required this.lon, required this.tz});

  @override
  Widget build(BuildContext context) {
    final tzH = tz >= 0 ? '+${tz ~/ 60}h' : '${tz ~/ 60}h';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0F2744), Color(0xFF1E3A5F), Color(0xFF1A5276)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 72, 20, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_fix_high_rounded, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text(
              'Détection automatique de la méthode',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.location_on_rounded, color: Colors.white38, size: 14),
            const SizedBox(width: 4),
            Text(
              '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°  •  UTC$tzH',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SAISIE D'UN HORAIRE
// ─────────────────────────────────────────────────────────────────────────────

class _TimeEntryRow extends StatelessWidget {
  final String prayer, label;
  final IconData icon;
  final TimeOfDay? time;
  final bool required;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _TimeEntryRow({
    required this.prayer, required this.label, required this.icon,
    required this.time, required this.required,
    required this.onTap, this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color  = AppTheme.prayerColor(label);
    final filled = time != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: 200.ms,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: filled
                ? color.withOpacity(isDark ? 0.12 : 0.07)
                : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: filled
                  ? color.withOpacity(0.35)
                  : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              width: filled ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Icône prière
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 14),
              // Nom
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (required) ...[
                          const SizedBox(width: 4),
                          Text(
                            '*', style: TextStyle(color: AppTheme.gold, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      filled ? 'Tapez pour modifier' : 'Tapez pour saisir',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              // Heure saisie ou placeholder
              if (filled) ...[
                Text(
                  '${time!.hour.toString().padLeft(2, '0')}:'
                  '${time!.minute.toString().padLeft(2, '0')}',
                  style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onClear,
                  child: Icon(Icons.close_rounded, color: color.withOpacity(0.6), size: 18),
                ),
              ] else
                Text(
                  '--:--',
                  style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w500,
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION RÉSULTATS
// ─────────────────────────────────────────────────────────────────────────────

class _ResultSection extends StatelessWidget {
  final CalibrationResult result;
  final Map<String, TimeOfDay?> mosqueTimes;
  final double lat, lon;
  final int tz;
  final bool applying;
  final VoidCallback onApply;

  const _ResultSection({
    required this.result, required this.mosqueTimes,
    required this.lat, required this.lon, required this.tz,
    required this.applying, required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();

    // Recalcul avec les paramètres fittés pour l'affichage
    final fittedTimes = PrayerCalculator.calculate(
      lat: lat, lon: lon,
      year: now.year, month: now.month, day: now.day,
      tzOffsetMinutes: tz,
      fajrAngle: result.fajrAngle, ishaAngle: result.ishaAngle,
      school: result.school,
    );

    final allZeroOffsets = result.residualOffsets.values.every((v) => v == 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Résultat de l\'analyse', icon: Icons.analytics_rounded),
        const SizedBox(height: 12),

        // ── Carte méthode détectée ──────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: result.isKnownMethod
                  ? [AppTheme.emeraldDeep, AppTheme.emerald]
                  : [const Color(0xFF1E3A5F), const Color(0xFF1A5276)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(
                  result.isKnownMethod
                      ? Icons.check_circle_rounded
                      : Icons.tune_rounded,
                  color: Colors.white, size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.isKnownMethod ? 'Méthode identifiée' : 'Angles personnalisés',
                    style: GoogleFonts.poppins(
                      color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                result.methodName,
                style: GoogleFonts.poppins(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: [
                  _Chip(label: result.angleDescription),
                  _Chip(label: result.schoolName),
                  _Chip(
                    label: 'Erreur ≤ ${result.rmsError.toStringAsFixed(1)} min',
                    ok: result.rmsError <= 2,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Tableau comparatif ──────────────────────────────────────
        _SectionLabel(label: 'Comparaison horaires', icon: Icons.compare_arrows_rounded),
        const SizedBox(height: 10),

        Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
          child: Column(
            children: _labels.keys.indexed.map((entry) {
              final (i, prayer) = entry;
              final mosqueT = mosqueTimes[prayer];
              final fittedMin = fittedTimes[prayer];
              final mosqueMin = mosqueT != null ? mosqueT.hour * 60 + mosqueT.minute : null;
              final diff = (mosqueMin != null && fittedMin != null)
                  ? mosqueMin - fittedMin : null;

              return _ComparisonRow(
                prayer: prayer,
                label: _labels[prayer]!,
                mosqueTime: mosqueT != null
                    ? '${mosqueT.hour.toString().padLeft(2, '0')}:${mosqueT.minute.toString().padLeft(2, '0')}'
                    : null,
                calculatedTime: PrayerCalculator.minutesToHHMM(fittedMin),
                delta: diff,
                isLast: i == _labels.length - 1,
              );
            }).toList(),
          ),
        ),

        // ── Offsets résiduels si nécessaires ───────────────────────
        if (!allZeroOffsets) ...[
          const SizedBox(height: 16),
          _InfoCard(
            icon: Icons.info_outline_rounded,
            text: 'Des ajustements résiduels mineurs seront appliqués '
                  'pour correspondre exactement aux horaires de votre mosquée.',
            color: AppTheme.gold.withOpacity(0.1),
            borderColor: AppTheme.gold.withOpacity(0.3),
            textColor: AppTheme.gold,
          ),
          const SizedBox(height: 8),
          _ResidualOffsetsList(offsets: result.residualOffsets),
        ],

        const SizedBox(height: 24),

        // ── Bouton Appliquer ────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: applying ? null : onApply,
            icon: applying
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(applying ? 'Application…' : 'Appliquer à l\'appareil'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  static const _labels = {
    'fajr': 'Fajr', 'sunrise': 'Chourouk', 'dhuhr': 'Dhuhr',
    'asr': 'Asr', 'maghrib': 'Maghrib', 'isha': 'Isha',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS HELPER
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: AppTheme.emerald, size: 18),
      const SizedBox(width: 8),
      Text(label, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: AppTheme.emerald,
      )),
    ],
  );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  final Color? borderColor;
  final Color? textColor;

  const _InfoCard({
    required this.icon, required this.text,
    this.color, this.borderColor, this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? (isDark ? AppTheme.darkCard : AppTheme.lightCard),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor ?? (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor ?? AppTheme.emerald, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: textColor,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
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
        Expanded(
          child: Text(message, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool ok;
  const _Chip({required this.label, this.ok = true});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: GoogleFonts.inter(
        color: ok ? Colors.white : Colors.orangeAccent, fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ComparisonRow extends StatelessWidget {
  final String prayer, label;
  final String? mosqueTime;
  final String calculatedTime;
  final int? delta;
  final bool isLast;

  const _ComparisonRow({
    required this.prayer, required this.label,
    required this.mosqueTime, required this.calculatedTime,
    required this.delta, required this.isLast,
  });

  Color _deltaColor() {
    if (delta == null) return Colors.grey;
    final abs = delta!.abs();
    if (abs <= 1) return AppTheme.emerald;
    if (abs <= 3) return AppTheme.gold;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Nom
              SizedBox(
                width: 70,
                child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
              ),
              // Mosquée
              Expanded(
                child: mosqueTime != null
                    ? Text(
                        mosqueTime!,
                        style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.bold,
                          color: AppTheme.prayerColor(label),
                        ),
                        textAlign: TextAlign.center,
                      )
                    : Text(
                        '—',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        ),
                      ),
              ),
              // Calculé
              Expanded(
                child: Text(
                  calculatedTime,
                  style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w500,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // Delta
              SizedBox(
                width: 48,
                child: delta != null
                    ? Text(
                        delta == 0
                            ? '✓'
                            : '${delta! > 0 ? '+' : ''}${delta!}\'',
                        style: TextStyle(
                          color: _deltaColor(),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.right,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1, indent: 16,
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
      ],
    );
  }
}

class _ResidualOffsetsList extends StatelessWidget {
  final Map<String, int> offsets;
  const _ResidualOffsetsList({required this.offsets});

  static const _names = {
    'fajr': 'Fajr', 'sunrise': 'Chourouk', 'dhuhr': 'Dhuhr',
    'asr': 'Asr', 'maghrib': 'Maghrib', 'isha': 'Isha',
  };

  @override
  Widget build(BuildContext context) {
    final nonZero = offsets.entries.where((e) => e.value != 0).toList();
    if (nonZero.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8, runSpacing: 8,
      children: nonZero.map((e) {
        final sign = e.value > 0 ? '+' : '';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.gold.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.gold.withOpacity(0.3)),
          ),
          child: Text(
            '${_names[e.key] ?? e.key} $sign${e.value}\'',
            style: GoogleFonts.inter(
              color: AppTheme.gold, fontSize: 12, fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }
}
