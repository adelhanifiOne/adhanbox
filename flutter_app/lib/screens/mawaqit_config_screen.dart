import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/adhanbox_provider.dart';
import '../theme/app_theme.dart';
import 'device_setup_screen.dart';

class MosqueData {
  final String uuid;
  final String slug;
  final String name;
  final double lat;
  final double lon;
  final String? city;
  final String? address;

  MosqueData({
    required this.uuid,
    required this.slug,
    required this.name,
    required this.lat,
    required this.lon,
    this.city,
    this.address,
  });

  factory MosqueData.fromJson(Map<String, dynamic> json) {
    return MosqueData(
      uuid: json['uuid'] ?? json['slug'] ?? '',
      slug: json['slug'] ?? '',
      name: json['name'] ?? 'Mosquée',
      lat: (json['latitude'] ?? json['lat'] ?? 0.0).toDouble(),
      lon: (json['longitude'] ?? json['lon'] ?? 0.0).toDouble(),
      city: json['city'] ?? json['localisation'],
      address: json['address'] ?? json['adresse'] ?? json['localisation'],
    );
  }

  double distanceTo(double lat2, double lon2) {
    const double r = 6371;
    final dLat = _rad(lat2 - lat);
    final dLon = _rad(lon2 - lon);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double d) => d * pi / 180;
}

class MawaqitConfigScreen extends ConsumerStatefulWidget {
  const MawaqitConfigScreen({super.key});

  @override
  ConsumerState<MawaqitConfigScreen> createState() => _MawaqitConfigScreenState();
}

class _MawaqitConfigScreenState extends ConsumerState<MawaqitConfigScreen> {
  bool _isConfiguring = false;
  bool _isSearching = false;
  String? _error;
  String? _configuredMosque;
  List<MosqueData> _nearbyMosques = [];
  double? _userLat;
  double? _userLon;
  bool _hasSearched = false;
  late TextEditingController _searchController;
  String _selectedCalcMethod = 'mwl';

  static const _calcMethods = {
    'mwl': 'Ligue islamique mondiale',
    'isna': 'ISNA (Amérique du Nord)',
    'uoif': 'UOIF / France',
    'egypt': 'Égyptienne',
    'karachi': 'Karachi',
  };

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _loadConfiguredMosque();
    _autoDetectAndSearch();
  }

  Future<void> _loadConfiguredMosque() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(kMawaqitMosqueNameKey);
    if (name != null && name.isNotEmpty && mounted) {
      setState(() => _configuredMosque = name);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── GPS ────────────────────────────────────────────────────────

  Future<Position> _getPosition() async {
    final hasPermission = await _checkLocationPermission();
    if (!hasPermission) throw Exception('Permission de localisation refusée.');

    for (final (accuracy, secs) in [
      (LocationAccuracy.best, 30),
      (LocationAccuracy.medium, 20),
      (LocationAccuracy.low, 10),
    ]) {
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: accuracy,
          timeLimit: Duration(seconds: secs),
        );
      } on TimeoutException {
        continue;
      }
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null &&
        !(lastKnown.latitude == 48.8566 && lastKnown.longitude == 2.3522)) {
      return lastKnown;
    }

    return await _getPositionByIP();
  }

  Future<Position> _getPositionByIP() async {
    for (final url in ['https://ipapi.co/json/', 'https://ip-api.com/json/']) {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (r.statusCode != 200) continue;
        final d = jsonDecode(r.body);
        if (d is! Map) continue;
        final lat = (d['latitude'] ?? d['lat'])?.toDouble();
        final lon = (d['longitude'] ?? d['lon'])?.toDouble();
        if (lat != null && lon != null && (lat != 0.0 || lon != 0.0)) {
          return Position(
            latitude: lat, longitude: lon, timestamp: DateTime.now(),
            accuracy: 5000, altitude: 0, heading: 0, speed: 0,
            speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
          );
        }
      } catch (_) {}
    }
    throw Exception(
      'Position introuvable.\nActivez le GPS ou vérifiez votre connexion Internet.',
    );
  }

  Future<bool> _checkLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Service de localisation désactivé.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception('Permission de localisation refusée définitivement.\nActivez-la dans les réglages.');
    }
    return perm != LocationPermission.denied;
  }

  // ─── MAWAQIT SEARCH ─────────────────────────────────────────────

  static const _mawaqitHeaders = {
    'Accept': 'application/json',
    'User-Agent': 'AdhanBox/1.0',
  };

  Future<List<MosqueData>> _searchViaMawaqit(double lat, double lon) async {
    try {
      final uri = Uri.https('mawaqit.net', '/api/2.0/mosque/search', {
        'lat': lat.toStringAsFixed(6),
        'lon': lon.toStringAsFixed(6),
        'distance': '20',
      });
      debugPrint('Mawaqit coords: $uri');
      final r = await http.get(uri, headers: _mawaqitHeaders)
          .timeout(const Duration(seconds: 15));
      debugPrint('Mawaqit coords status: ${r.statusCode}');
      if (r.statusCode == 200) {
        final decoded = jsonDecode(r.body);
        if (decoded is List) {
          return decoded
              .whereType<Map<String, dynamic>>()
              .map((e) => MosqueData.fromJson(e))
              .where((m) => m.uuid.isNotEmpty && m.name.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Mawaqit coords failed: $e');
    }
    return [];
  }

  Future<List<MosqueData>> _searchViaMawaqitByWord(String word) async {
    try {
      final uri = Uri.https('mawaqit.net', '/api/2.0/mosque/search', {
        'word': word,
      });
      debugPrint('Mawaqit word: $uri');
      final r = await http.get(uri, headers: _mawaqitHeaders)
          .timeout(const Duration(seconds: 15));
      debugPrint('Mawaqit word status: ${r.statusCode}');
      if (r.statusCode == 200) {
        final decoded = jsonDecode(r.body);
        if (decoded is List) {
          return decoded
              .whereType<Map<String, dynamic>>()
              .map((e) => MosqueData.fromJson(e))
              .where((m) => m.uuid.isNotEmpty && m.name.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Mawaqit word failed: $e');
    }
    return [];
  }

  void _sortByDistance(List<MosqueData> mosques) {
    if (_userLat == null || _userLon == null) return;
    mosques.sort((a, b) =>
        a.distanceTo(_userLat!, _userLon!).compareTo(b.distanceTo(_userLat!, _userLon!)));
  }

  // ─── HELPERS ────────────────────────────────────────────────────

  /// Retourne le token API — utilise le cache du provider, ou le fetche depuis
  /// /api/device/info si absent (endpoint public, pas d'auth requise).
  Future<String?> _resolveApiToken(String deviceIp) async {
    final cached = ref.read(adhanboxApiKeyProvider);
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final r = await http
          .get(Uri.parse('http://$deviceIp/api/device/info'))
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

  // ─── ACTIONS ────────────────────────────────────────────────────

  Future<void> _autoDetectAndSearch() async {
    setState(() { _isSearching = true; _error = null; });

    try {
      final pos = await _getPosition();
      _userLat = pos.latitude;
      _userLon = pos.longitude;

      final mosques = await _searchViaMawaqit(_userLat!, _userLon!);
      _sortByDistance(mosques);

      setState(() {
        _nearbyMosques = mosques.take(15).toList();
        _hasSearched = true;
        if (mosques.isEmpty) {
          _error = 'Aucune mosquée trouvée à proximité.\nEssayez de rechercher par nom.';
        }
      });
    } on TimeoutException {
      setState(() {
        _error = 'Délai dépassé. Vérifiez que le GPS est activé puis réessayez.';
        _hasSearched = true;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _hasSearched = true;
      });
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _searchByName() async {
    final input = _searchController.text.trim();
    if (input.isEmpty) return;

    setState(() { _isSearching = true; _error = null; });

    try {
      // Direct Mawaqit word search (mosque names)
      var mosques = await _searchViaMawaqitByWord(input);

      // Fallback: geocode city → Mawaqit coordinate search
      if (mosques.isEmpty) {
        final gr = await http
            .get(
              Uri.https('nominatim.openstreetmap.org', '/search',
                  {'q': input, 'format': 'json', 'limit': '1'}),
              headers: {'User-Agent': 'AdhanBox/1.0'},
            )
            .timeout(const Duration(seconds: 10));

        if (gr.statusCode == 200) {
          final data = jsonDecode(gr.body);
          if (data is List && data.isNotEmpty) {
            final first = data.first;
            if (first is Map) {
              final lat = double.tryParse(first['lat']?.toString() ?? '');
              final lon = double.tryParse(first['lon']?.toString() ?? '');
              if (lat != null && lon != null) {
                _userLat = lat;
                _userLon = lon;
                mosques = await _searchViaMawaqit(lat, lon);
              }
            }
          }
        }
      }

      _sortByDistance(mosques);

      setState(() {
        _nearbyMosques = mosques.take(20).toList();
        _hasSearched = true;
        if (mosques.isEmpty) {
          _error = 'Aucune mosquée trouvée pour "$input".\nEssayez un nom différent ou utilisez le GPS.';
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _hasSearched = true;
      });
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _configureMosque(MosqueData mosque) async {
    final deviceIp = ref.read(currentDeviceIpProvider);

    if (deviceIp == null || deviceIp.isEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Aucun appareil AdhanBox'),
          content: const Text(
            'Vous devez d\'abord configurer votre AdhanBox avant de sélectionner une mosquée.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
                );
              },
              child: const Text('Configurer'),
            ),
          ],
        ),
      );
      return;
    }

    if (deviceIp == '192.168.4.1') {
      setState(() { _error = 'Connectez d\'abord l\'AdhanBox à votre WiFi maison.'; });
      return;
    }

    setState(() { _isConfiguring = true; _error = null; });

    try {
      final token = await _resolveApiToken(deviceIp);
      final headers = _headersWithToken(token);

      final r = await http
          .post(
            Uri.parse('http://$deviceIp/api/mawaqit/config'),
            headers: headers,
            body: jsonEncode({
              'mosque_uuid': mosque.uuid,
              'slug': mosque.slug,
              'name': mosque.name,
              'city': mosque.city ?? mosque.address ?? '',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (r.statusCode != 200) {
        String msg = 'HTTP ${r.statusCode}';
        try {
          final d = jsonDecode(r.body);
          if (d is Map && d['error'] != null) msg = d['error'].toString();
        } catch (_) {}
        throw Exception(msg);
      }

      // Trigger Mawaqit sync on the device
      final syncRes = await http
          .post(Uri.parse('http://$deviceIp/api/mawaqit/sync'), headers: headers)
          .timeout(const Duration(seconds: 90));
      if (syncRes.statusCode != 200) {
        String msg = 'Échec de synchronisation (HTTP ${syncRes.statusCode})';
        try {
          final d = jsonDecode(syncRes.body);
          if (d is Map && d['error'] != null) msg = d['error'].toString();
        } catch (_) {}
        throw Exception(msg);
      }

      ref.invalidate(prayerTimesProvider);
      ref.invalidate(mawaqitComparisonProvider);
      ref.invalidate(mawaqitTimesProvider);
      ref.invalidate(deviceStatusProvider);

      setState(() { _configuredMosque = mosque.name; });
      // Persiste le nom pour l'afficher sur la page Prière
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kMawaqitMosqueNameKey, mosque.name);
      ref.invalidate(configuredMosqueProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${mosque.name} configurée avec succès'),
          backgroundColor: AppTheme.emerald,
        ));
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.of(context).pop();
      }
    } on TimeoutException {
      setState(() {
        _error =
            'Délai dépassé. Vérifiez que l\'AdhanBox et votre téléphone sont sur le même réseau WiFi.';
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); });
    } finally {
      setState(() => _isConfiguring = false);
    }
  }

  Future<void> _activateCalculatedFallback() async {
    final deviceIp = ref.read(currentDeviceIpProvider);
    if (deviceIp == null) {
      setState(() { _error = 'Aucun appareil configuré.'; });
      return;
    }

    setState(() { _isConfiguring = true; _error = null; });
    try {
      final token = await _resolveApiToken(deviceIp);
      await http
          .post(
            Uri.parse('http://$deviceIp/api/calculation/config'),
            headers: _headersWithToken(token),
            body: jsonEncode({'method': _selectedCalcMethod}),
          )
          .timeout(const Duration(seconds: 10));

      ref.invalidate(prayerTimesProvider);
      ref.invalidate(deviceStatusProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Horaires calculés activés'),
          backgroundColor: AppTheme.emerald,
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() { _error = 'Erreur: $e'; });
    } finally {
      setState(() => _isConfiguring = false);
    }
  }

  // ─── BUILD ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: AppTheme.emeraldDeep,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _MawaqitHeader(),
            ),
            title: Text(
              'Mosquée de référence',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                tooltip: 'Détecter ma position',
                onPressed: _isSearching ? null : _autoDetectAndSearch,
                icon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.my_location_rounded, color: Colors.white),
              ),
              const SizedBox(width: 4),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Search bar
                _SearchCard(
                  controller: _searchController,
                  isSearching: _isSearching,
                  onSearch: _searchByName,
                  onGPS: _autoDetectAndSearch,
                  isDark: isDark,
                ).animate().fadeIn(duration: 300.ms),

                // Error / warning banner
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _WarningBanner(message: _error!).animate().fadeIn(),
                ],

                // Results section
                if (_nearbyMosques.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _SectionHeader(
                    icon: Icons.mosque_rounded,
                    label:
                        '${_nearbyMosques.length} mosquée${_nearbyMosques.length > 1 ? 's' : ''} trouvée${_nearbyMosques.length > 1 ? 's' : ''}',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  ..._nearbyMosques.asMap().entries.map((e) {
                    final mosque = e.value;
                    final dist = (_userLat != null && _userLon != null)
                        ? mosque.distanceTo(_userLat!, _userLon!)
                        : null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MosqueCard(
                        mosque: mosque,
                        distance: dist,
                        isConfigured: _configuredMosque == mosque.name,
                        isLoading: _isConfiguring,
                        isDark: isDark,
                        onTap: _isConfiguring ? null : () => _configureMosque(mosque),
                      )
                          .animate()
                          .fadeIn(delay: Duration(milliseconds: 40 * e.key))
                          .slideY(begin: 0.05, curve: Curves.easeOut),
                    );
                  }),
                ],

                // Empty state after search attempt
                if (_hasSearched && _nearbyMosques.isEmpty && !_isSearching) ...[
                  const SizedBox(height: 16),
                  _EmptyState(isDark: isDark).animate().fadeIn(),
                ],

                // Calculated fallback option
                if (_hasSearched && !_isSearching) ...[
                  const SizedBox(height: 20),
                  _FallbackCard(
                    isDark: isDark,
                    selectedMethod: _selectedCalcMethod,
                    isLoading: _isConfiguring,
                    onMethodChanged: (v) => setState(() => _selectedCalcMethod = v),
                    onActivate: _activateCalculatedFallback,
                    methods: _calcMethods,
                  ).animate().fadeIn(delay: 150.ms),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── HEADER ─────────────────────────────────────────────────────
class _MawaqitHeader extends StatelessWidget {
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
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.mosque_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Synchronisation Mawaqit',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Horaires officiels de votre mosquée',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── SEARCH CARD ────────────────────────────────────────────────
class _SearchCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isSearching;
  final VoidCallback onSearch;
  final VoidCallback onGPS;
  final bool isDark;

  const _SearchCard({
    required this.controller,
    required this.isSearching,
    required this.onSearch,
    required this.onGPS,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trouver votre mosquée',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            enabled: !isSearching,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              hintText: 'Nom de mosquée, ville...',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isSearching ? null : onSearch,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Rechercher'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: isSearching ? null : onGPS,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  side: BorderSide(color: AppTheme.emerald.withOpacity(0.5)),
                ),
                child: const Icon(
                  Icons.my_location_rounded,
                  color: AppTheme.emerald,
                  size: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── SECTION HEADER ─────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  const _SectionHeader(
      {required this.icon, required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.emerald, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(color: AppTheme.emerald),
        ),
      ],
    );
  }
}

// ─── MOSQUE CARD ────────────────────────────────────────────────
class _MosqueCard extends StatelessWidget {
  final MosqueData mosque;
  final double? distance;
  final bool isConfigured;
  final bool isLoading;
  final VoidCallback? onTap;
  final bool isDark;

  const _MosqueCard({
    required this.mosque,
    required this.isConfigured,
    required this.isLoading,
    required this.isDark,
    this.distance,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final location = mosque.city ?? mosque.address;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isConfigured
              ? AppTheme.emerald.withOpacity(isDark ? 0.12 : 0.07)
              : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isConfigured
                ? AppTheme.emerald.withOpacity(0.5)
                : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            width: isConfigured ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (isConfigured ? AppTheme.emerald : AppTheme.gold)
                    .withOpacity(isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isConfigured ? Icons.check_circle_rounded : Icons.mosque_rounded,
                color: isConfigured ? AppTheme.emerald : AppTheme.gold,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mosque.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isConfigured ? AppTheme.emerald : null,
                          fontWeight:
                              isConfigured ? FontWeight.w700 : FontWeight.w500,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (location != null && location.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      location,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (distance != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withOpacity(isDark ? 0.18 : 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${distance!.toStringAsFixed(1)} km',
                      style: GoogleFonts.inter(
                        color: AppTheme.goldLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (!isConfigured) ...[
                  const SizedBox(height: 6),
                  isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.emerald),
                        )
                      : const Icon(Icons.chevron_right_rounded,
                          color: AppTheme.emerald, size: 20),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── EMPTY STATE ────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_off_rounded, color: Colors.orange, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            'Aucune mosquée trouvée',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Essayez de rechercher par nom de mosquée,\nou activez les horaires calculés ci-dessous.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── FALLBACK CARD ──────────────────────────────────────────────
class _FallbackCard extends StatelessWidget {
  final bool isDark;
  final String selectedMethod;
  final bool isLoading;
  final ValueChanged<String> onMethodChanged;
  final VoidCallback onActivate;
  final Map<String, String> methods;

  const _FallbackCard({
    required this.isDark,
    required this.selectedMethod,
    required this.isLoading,
    required this.onMethodChanged,
    required this.onActivate,
    required this.methods,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.gold.withOpacity(isDark ? 0.06 : 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gold.withOpacity(isDark ? 0.25 : 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calculate_rounded,
                    color: AppTheme.gold, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Horaires calculés',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: AppTheme.gold),
                    ),
                    Text(
                      'Alternative si aucune mosquée disponible',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: selectedMethod,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Méthode de calcul',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            items: methods.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged:
                isLoading ? null : (v) { if (v != null) onMethodChanged(v); },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isLoading ? null : onActivate,
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: const Text('Utiliser les horaires calculés'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: AppTheme.gold.withOpacity(0.5)),
                foregroundColor: AppTheme.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── WARNING BANNER ─────────────────────────────────────────────
class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.orange[700],
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
