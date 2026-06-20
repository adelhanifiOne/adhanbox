import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:app_settings/app_settings.dart';
import '../providers/adhanbox_provider.dart';
import '../services/adhanbox_api.dart';
import '../services/esp32_discovery_service.dart';
import '../theme/app_theme.dart';
import 'calculation_setup_screen.dart';

class DeviceSetupScreen extends ConsumerStatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  ConsumerState<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends ConsumerState<DeviceSetupScreen>
    with SingleTickerProviderStateMixin {
  int _step = 1;
  String? _error;

  // Step 1
  List<Map<String, dynamic>> _adhanboxNetworks = [];
  bool _isScanningAdhanboxWifi = false;
  String? _selectedAdhanboxWifi;

  // Step 2
  bool _isConnectingToAdhanbox = false;

  // Step 3
  List<Map<String, dynamic>> _homeWifiNetworks = [];
  bool _isScanningHomeWifi = false;
  String? _selectedHomeWifi;
  bool _isSendingCredentials = false;
  bool _showPassword = false;
  final TextEditingController _passwordController = TextEditingController();

  // Step 4
  bool _isSearchingOnHomeNetwork = false;
  String? _deviceIp;
  String _networkScanProgress = '';
  bool _step4ReadyToSearch = false;
  final TextEditingController _manualIpController = TextEditingController();

  // Step 5
  final TextEditingController _nameController = TextEditingController(text: 'AdhanBox');

  late AnimationController _pulseController;

  static const _steps = [
    _StepMeta(icon: Icons.search_rounded, label: 'Détection'),
    _StepMeta(icon: Icons.link_rounded, label: 'Connexion'),
    _StepMeta(icon: Icons.wifi_rounded, label: 'WiFi'),
    _StepMeta(icon: Icons.devices_rounded, label: 'Réseau'),
    _StepMeta(icon: Icons.check_circle_rounded, label: 'Terminé'),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scanForAdhanBoxNetworks();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _passwordController.dispose();
    _manualIpController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // ─────────────────── BUSINESS LOGIC ───────────────────

  Future<void> _openWiFiSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.wifi);
    } catch (_) {
      try {
        await AppSettings.openAppSettings(type: AppSettingsType.settings);
      } catch (_) {}
    }
  }

  Future<void> _scanForAdhanBoxNetworks() async {
    setState(() { _isScanningAdhanboxWifi = true; _error = null; });
    try {
      if (kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 400));
        setState(() { _adhanboxNetworks = []; });
      } else {
        final locationEnabled = await Geolocator.isLocationServiceEnabled();
        if (!locationEnabled) {
          setState(() => _error = 'Activez la localisation (GPS) pour détecter les réseaux WiFi.');
          return;
        }
        final perm = await Permission.locationWhenInUse.request();
        if (!perm.isGranted) {
          setState(() => _error = 'Permission localisation requise pour le scan WiFi.');
          return;
        }
        final canScan = await WiFiScan.instance.canStartScan();
        if (canScan != CanStartScan.yes) {
          setState(() => _error = 'Scan WiFi indisponible. Vérifiez WiFi, GPS et permissions.');
          return;
        }
        await WiFiScan.instance.startScan();
        await Future.delayed(const Duration(seconds: 2));
        final canGet = await WiFiScan.instance.canGetScannedResults();
        if (canGet != CanGetScannedResults.yes) {
          setState(() => _error = 'Impossible de lire les résultats du scan.');
          return;
        }
        final results = await WiFiScan.instance.getScannedResults();
        final networks = results
            .where((n) {
              final ssid = n.ssid.toLowerCase();
              return ssid.contains('adhanbox') || ssid.contains('adhan-box') || ssid.contains('adhan');
            })
            .map((n) => {
              'ssid': n.ssid,
              'rssi': n.level,
              'security': n.capabilities.toLowerCase().contains('wpa')
                  ? 'WPA2'
                  : (n.capabilities.toLowerCase().contains('wep') ? 'WEP' : 'Open'),
            })
            .toList();
        setState(() {
          _adhanboxNetworks = networks;
          if (networks.isEmpty) _error = 'Aucun AdhanBox détecté à proximité.';
        });
      }
    } catch (e) {
      setState(() => _error = 'Erreur lors du scan WiFi: $e');
    } finally {
      if (mounted) setState(() => _isScanningAdhanboxWifi = false);
    }
  }

  Future<void> _connectToAdhanBoxWifi() async {
    if (_selectedAdhanboxWifi == null) return;
    setState(() { _isConnectingToAdhanbox = true; _error = null; });
    try {
      const maxAttempts = 5;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          setState(() => _error = 'Vérification de la connexion ($attempt/$maxAttempts)...');
          final api = AdhanBoxAPI(baseUrl: 'http://192.168.4.1', timeout: const Duration(seconds: 8));
          final status = await api.getStatus();
          if (status.containsKey('wifi') && status.containsKey('rtc_ok')) {
            setState(() { _step = 3; _isConnectingToAdhanbox = false; _error = null; });
            await _getHomeWifiNetworksFromESP32();
            return;
          }
        } catch (_) {
          if (attempt < maxAttempts) await Future.delayed(const Duration(seconds: 3));
        }
      }
      setState(() {
        _error = 'Impossible de contacter l\'ESP32. Vérifiez que vous êtes connecté au réseau "$_selectedAdhanboxWifi".';
        _isConnectingToAdhanbox = false;
      });
    } catch (e) {
      setState(() { _error = 'Erreur: $e'; _isConnectingToAdhanbox = false; });
    }
  }

  Future<void> _getHomeWifiNetworksFromESP32() async {
    setState(() { _isScanningHomeWifi = true; _error = null; });
    try {
      final api = AdhanBoxAPI(baseUrl: 'http://192.168.4.1', timeout: const Duration(seconds: 10));
      final networks = await api.scanWiFiNetworks();
      setState(() {
        _homeWifiNetworks = networks
            .map((n) => {
                  'ssid': n['ssid'],
                  'rssi': n['rssi'],
                  'security': n['security'] ?? n['secure'],
                })
            .toList();
        _isScanningHomeWifi = false;
        if (_homeWifiNetworks.isEmpty) _error = 'Aucun réseau WiFi détecté par l\'AdhanBox.';
      });
    } catch (_) {
      try {
        await WiFiScan.instance.startScan();
        await Future.delayed(const Duration(seconds: 2));
        final results = await WiFiScan.instance.getScannedResults();
        final networks = results
            .where((n) => n.ssid.isNotEmpty)
            .map((n) => {
              'ssid': n.ssid,
              'rssi': n.level,
              'security': n.capabilities.toLowerCase().contains('wpa')
                  ? 'WPA2'
                  : (n.capabilities.toLowerCase().contains('wep') ? 'WEP' : 'Open'),
            })
            .toList();
        setState(() { _homeWifiNetworks = networks; _isScanningHomeWifi = false; });
        if (_homeWifiNetworks.isEmpty) setState(() => _error = 'Aucun réseau WiFi détecté.');
      } catch (e) {
        setState(() { _error = 'Erreur scan WiFi: $e'; _isScanningHomeWifi = false; });
      }
    }
  }

  Future<void> _sendWifiCredentials() async {
    if (_selectedHomeWifi == null) return;
    setState(() { _isSendingCredentials = true; _error = null; });
    try {
      final api = AdhanBoxAPI(baseUrl: 'http://192.168.4.1', timeout: const Duration(seconds: 10));
      await api.connectWiFi(_selectedHomeWifi!, _passwordController.text);
      await Future.delayed(const Duration(seconds: 10));
      setState(() { _step = 4; _step4ReadyToSearch = false; _isSendingCredentials = false; });
    } catch (e) {
      setState(() { _error = 'Erreur: vérifiez le mot de passe WiFi.'; _isSendingCredentials = false; });
    }
  }

  Future<String?> _getLocalIp() async {
    if (kIsWeb) return null;
    try {
      for (var iface in await NetworkInterface.list()) {
        for (var addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final ip = addr.address;
            if (ip.startsWith('192.168.') || ip.startsWith('10.')) return ip;
            if (ip.startsWith('172.')) {
              final second = int.tryParse(ip.split('.')[1]) ?? 0;
              if (second >= 16 && second <= 31) return ip;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _findESP32OnHomeNetwork() async {
    setState(() {
      _isSearchingOnHomeNetwork = true;
      _error = null;
      _networkScanProgress = 'Recherche en cours...';
    });
    try {
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          setState(() => _networkScanProgress = 'Tentative $attempt/3...');
          final discovery = ESP32DiscoveryService();
          final devices = await discovery.discoverDevices(timeout: const Duration(seconds: 5));
          
          final prefs = await SharedPreferences.getInstance();
          final savedList = prefs.getString('savedDevices');
          List<String> knownIps = [];
          if (savedList != null) {
              try {
                final List decoded = jsonDecode(savedList);
                knownIps = decoded.map((e) => e['ip'] as String).toList();
              } catch(_) {}
          }
          
          bool deviceFound = false;
          for (final device in devices) {
            if (knownIps.contains(device.host)) continue;

            final api = AdhanBoxAPI(baseUrl: 'http://${device.host}', timeout: const Duration(seconds: 4));
            try {
              final status = await api.getStatus();
              if (status.containsKey('wifi') && status.containsKey('rtc_ok')) {
                await saveDeviceIp(ref, device.host, name: 'Nouvel Appareil');
                try {
                  final pos = await Geolocator.getCurrentPosition(
                      desiredAccuracy: LocationAccuracy.high,
                      timeLimit: const Duration(seconds: 10));
                  await api.setLocation(pos.latitude, pos.longitude, pos.accuracy);
                } catch (_) {}
                try { await api.setRtcTime(DateTime.now()); } catch (_) {}
                setState(() {
                  _deviceIp = device.host;
                  _step = 5;
                  _isSearchingOnHomeNetwork = false;
                  _networkScanProgress = '';
                });
                deviceFound = true;
                break;
              }
            } catch(_) {}
          }
          if (deviceFound) return;
        } catch (e) {
          if (attempt < 3) await Future.delayed(const Duration(seconds: 2));
        }
      }
      setState(() {
        _error = 'AdhanBox introuvable sur le réseau. Vérifiez la connexion WiFi ou entrez l\'IP manuellement.';
        _isSearchingOnHomeNetwork = false;
        _networkScanProgress = '';
      });
    } catch (e) {
      setState(() {
        _error = 'Erreur: $e';
        _isSearchingOnHomeNetwork = false;
        _networkScanProgress = '';
      });
    }
  }

  Future<void> _testManualIp(String ip) async {
    setState(() { _isSearchingOnHomeNetwork = true; _error = null; });
    try {
      final api = AdhanBoxAPI(baseUrl: 'http://$ip', timeout: const Duration(seconds: 5));
      final status = await api.getStatus();
      if (status.containsKey('wifi') && status.containsKey('rtc_ok')) {
        await saveDeviceIp(ref, ip, name: 'Nouvel Appareil');
        try {
          final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 10));
          await api.setLocation(pos.latitude, pos.longitude, pos.accuracy);
        } catch (_) {}
        try { await api.setRtcTime(DateTime.now()); } catch (_) {}
        setState(() { _deviceIp = ip; _step = 5; _isSearchingOnHomeNetwork = false; });
      } else {
        setState(() { _error = 'Cette adresse ne correspond pas à un AdhanBox.'; _isSearchingOnHomeNetwork = false; });
      }
    } catch (e) {
      setState(() { _error = 'Impossible de contacter $ip.'; _isSearchingOnHomeNetwork = false; });
    }
  }

  void _goBack() {
    setState(() {
      _error = null;
      if (_step == 2) _step = 1;
      else if (_step == 3) _step = 2;
      else if (_step == 4) _step = 3;
      else Navigator.pop(context);
    });
  }

  // ─────────────────── BUILD ───────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Gradient AppBar ──
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: AppTheme.emeraldDeep,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: _step > 1 ? _goBack : () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _SetupHeader(step: _step),
            ),
            title: Text(
              'Configuration',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
            ),
          ),

          // ── Step Indicator ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            sliver: SliverToBoxAdapter(
              child: _ModernStepIndicator(current: _step, steps: _steps),
            ),
          ),

          // ── Error Banner ──
          if (_error != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null))
                    .animate().fadeIn().slideY(begin: -0.1),
              ),
            ),

          // ── Step Content ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: _buildCurrentStep(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 1: return _buildStep1(key: const ValueKey(1));
      case 2: return _buildStep2(key: const ValueKey(2));
      case 3: return _buildStep3(key: const ValueKey(3));
      case 4: return _buildStep4(key: const ValueKey(4));
      case 5: return _buildStep5(key: const ValueKey(5));
      default: return const SizedBox.shrink();
    }
  }

  // ─────────────────── STEP 1: SCAN ───────────────────

  Widget _buildStep1({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          icon: Icons.search_rounded,
          title: 'Détection d\'AdhanBox',
          subtitle: 'Recherche des appareils à proximité',
        ),
        const SizedBox(height: 20),

        if (_isScanningAdhanboxWifi) ...[
          _LoadingCard(
            icon: Icons.radar_rounded,
            title: 'Scan en cours...',
            subtitle: 'Recherche des réseaux AdhanBox',
            pulseController: _pulseController,
          ),
        ] else if (_adhanboxNetworks.isEmpty) ...[
          _EmptyStateCard(
            icon: Icons.wifi_find_rounded,
            title: 'Aucun appareil détecté',
            subtitle: kIsWeb
                ? 'Connectez votre appareil au WiFi AdhanBox puis continuez.'
                : 'Vérifiez que votre AdhanBox est allumé et proche.',
            actions: [
              if (kIsWeb)
                _ActionBtn(
                  label: 'Je suis connecté',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {
                    setState(() { _selectedAdhanboxWifi = 'AdhanBox (manuel)'; _step = 2; });
                    _connectToAdhanBoxWifi();
                  },
                )
              else
                _ActionBtn(
                  label: 'Relancer le scan',
                  icon: Icons.refresh_rounded,
                  isPrimary: false,
                  onPressed: _scanForAdhanBoxNetworks,
                ),
            ],
          ),
        ] else ...[
          ..._adhanboxNetworks.asMap().entries.map((e) {
            final i = e.key;
            final network = e.value;
            final ssid = network['ssid']?.toString() ?? 'Inconnu';
            final rssi = network['rssi'] as int? ?? 0;
            final isSelected = _selectedAdhanboxWifi == ssid;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _WifiNetworkTile(
                ssid: ssid,
                rssi: rssi,
                isSelected: isSelected,
                isAdhanbox: true,
                onTap: () => setState(() => _selectedAdhanboxWifi = ssid),
              ).animate().fadeIn(delay: Duration(milliseconds: 60 * i)).slideY(begin: 0.08),
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanForAdhanBoxNetworks,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Rescanner'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _selectedAdhanboxWifi == null
                      ? null
                      : () { setState(() { _step = 2; _error = null; }); _connectToAdhanBoxWifi(); },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Continuer'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ─────────────────── STEP 2: CONNECT ───────────────────

  Widget _buildStep2({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          icon: Icons.link_rounded,
          title: 'Connexion à l\'AdhanBox',
          subtitle: 'Réseau: $_selectedAdhanboxWifi',
        ),
        const SizedBox(height: 20),

        if (_isConnectingToAdhanbox) ...[
          _LoadingCard(
            icon: Icons.link_rounded,
            title: 'Connexion en cours...',
            subtitle: 'Vérification de la communication',
            pulseController: _pulseController,
          ),
        ] else ...[
          _InstructionCard(
            icon: Icons.smartphone_rounded,
            iconColor: AppTheme.fajrColor,
            title: 'Connectez-vous au réseau AdhanBox',
            steps: [
              'Ouvrez les paramètres WiFi de votre téléphone',
              'Sélectionnez le réseau "$_selectedAdhanboxWifi"',
              'Aucun mot de passe nécessaire',
              'Revenez dans l\'application',
            ],
            action: OutlinedButton.icon(
              onPressed: _openWiFiSettings,
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Ouvrir paramètres WiFi'),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _connectToAdhanBoxWifi,
              icon: const Icon(Icons.check_circle_rounded, size: 20),
              label: const Text('Je suis connecté'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────── STEP 3: WIFI CONFIG ───────────────────

  Widget _buildStep3({Key? key}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          icon: Icons.wifi_rounded,
          title: 'Réseau WiFi domestique',
          subtitle: 'Connectez l\'AdhanBox à votre WiFi',
        ),
        const SizedBox(height: 20),

        if (_isScanningHomeWifi) ...[
          _LoadingCard(
            icon: Icons.wifi_find_rounded,
            title: 'Détection des réseaux...',
            subtitle: 'Récupération de la liste WiFi',
            pulseController: _pulseController,
          ),
        ] else if (_homeWifiNetworks.isEmpty) ...[
          _EmptyStateCard(
            icon: Icons.wifi_off_rounded,
            title: 'Aucun réseau détecté',
            subtitle: 'Vérifiez que le WiFi est activé.',
            actions: [
              _ActionBtn(
                label: 'Réessayer',
                icon: Icons.refresh_rounded,
                isPrimary: false,
                onPressed: _getHomeWifiNetworksFromESP32,
              ),
            ],
          ),
        ] else ...[
          // Network list
          _ThemedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_rounded, color: AppTheme.emerald, size: 18),
                      const SizedBox(width: 8),
                      Text('Réseaux disponibles', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      GestureDetector(
                        onTap: _getHomeWifiNetworksFromESP32,
                        child: Icon(Icons.refresh_rounded, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, size: 20),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _homeWifiNetworks.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1, indent: 56,
                      color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                    ),
                    itemBuilder: (_, i) {
                      final n = _homeWifiNetworks[i];
                      final ssid = n['ssid']?.toString() ?? '';
                      final rssi = n['rssi'] as int? ?? 0;
                      final isSelected = _selectedHomeWifi == ssid;
                      final strength = _signalPercent(rssi);
                      return ListTile(
                        dense: true,
                        leading: _SignalIcon(strength: strength),
                        title: Text(ssid, style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                        subtitle: Text('Signal $strength%', style: Theme.of(context).textTheme.bodySmall),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 22)
                            : Icon(Icons.circle_outlined, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder, size: 22),
                        onTap: () => setState(() => _selectedHomeWifi = ssid),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Password input
          if (_selectedHomeWifi != null) ...[
            const SizedBox(height: 16),
            _ThemedCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_rounded, color: AppTheme.gold, size: 18),
                        const SizedBox(width: 8),
                        Text('Mot de passe WiFi', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Réseau: $_selectedHomeWifi', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        hintText: 'Entrez le mot de passe',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn().slideY(begin: 0.06),
          ],

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_selectedHomeWifi == null || _isSendingCredentials) ? null : _sendWifiCredentials,
              icon: _isSendingCredentials
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_isSendingCredentials ? 'Configuration...' : 'Configurer l\'AdhanBox'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────── STEP 4: FIND DEVICE ───────────────────

  Widget _buildStep4({Key? key}) {
    if (!_step4ReadyToSearch) {
      return Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepTitle(
            icon: Icons.swap_horiz_rounded,
            title: 'Reconnexion WiFi',
            subtitle: 'Retournez sur votre réseau domestique',
          ),
          const SizedBox(height: 20),
          _InstructionCard(
            icon: Icons.wifi_rounded,
            iconColor: AppTheme.gold,
            title: 'Reconnectez votre téléphone',
            steps: [
              'L\'AdhanBox se connecte à votre WiFi domestique',
              'Reconnectez votre téléphone au même réseau',
              'Appuyez sur "Rechercher" quand vous êtes prêt',
            ],
            action: OutlinedButton.icon(
              onPressed: _openWiFiSettings,
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Ouvrir paramètres WiFi'),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() => _step4ReadyToSearch = true);
                _findESP32OnHomeNetwork();
              },
              icon: const Icon(Icons.search_rounded, size: 20),
              label: const Text('Rechercher l\'AdhanBox'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
        ],
      );
    }

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          icon: Icons.devices_rounded,
          title: 'Recherche sur le réseau',
          subtitle: 'Localisation de l\'AdhanBox...',
        ),
        const SizedBox(height: 20),

        if (_isSearchingOnHomeNetwork) ...[
          _LoadingCard(
            icon: Icons.devices_rounded,
            title: 'Recherche en cours...',
            subtitle: _networkScanProgress.isNotEmpty ? _networkScanProgress : 'Scan du réseau local',
            pulseController: _pulseController,
          ),
        ] else ...[
          // Manual IP entry
          _ThemedCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.edit_rounded, color: AppTheme.fajrColor, size: 18),
                      const SizedBox(width: 8),
                      Text('Saisie manuelle', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Si la détection automatique échoue, entrez l\'adresse IP affichée sur le moniteur série.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _manualIpController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: '192.168.1.100',
                      prefixIcon: Icon(Icons.router_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final ip = _manualIpController.text.trim();
                        if (ip.isNotEmpty) _testManualIp(ip);
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Tester cette adresse'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _findESP32OnHomeNetwork,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Relancer la recherche'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────── STEP 5: COMPLETE ───────────────────

  Widget _buildStep5({Key? key}) {
    return Column(
      key: key,
      children: [
        const SizedBox(height: 20),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppTheme.emerald.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 54),
        ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
        const SizedBox(height: 24),
        Text(
          'Configuration réussie !',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 8),
        Text(
          'Connectée sur $_deviceIp',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 300.ms),
        const SizedBox(height: 24),
        
        // Device name field
        _ThemedCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.edit_rounded, color: AppTheme.emerald, size: 20),
                    const SizedBox(width: 10),
                    Text('Nom de l\'appareil', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'ex: AdhanBox Salon',
                    prefixIcon: Icon(Icons.label_rounded),
                  ),
                ),
              ],
            ),
          ),
        ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.08),
        const SizedBox(height: 24),

        // Next steps card
        _ThemedCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, color: AppTheme.gold, size: 20),
                    const SizedBox(width: 10),
                    Text('Prochaines étapes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 16),
                _NextStepItem(icon: Icons.mosque_rounded, color: AppTheme.emerald, label: 'Configurer votre mosquée Mawaqit'),
                const SizedBox(height: 10),
                _NextStepItem(icon: Icons.calculate_rounded, color: AppTheme.fajrColor, label: 'Choisir la méthode de calcul'),
                const SizedBox(height: 10),
                _NextStepItem(icon: Icons.volume_up_rounded, color: AppTheme.asrColor, label: 'Ajuster le volume de l\'adhan'),
                const SizedBox(height: 10),
                _NextStepItem(icon: Icons.light_rounded, color: AppTheme.gold, label: 'Personnaliser l\'éclairage LED'),
              ],
            ),
          ),
        ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.08),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              if (_deviceIp != null) {
                final name = _nameController.text.trim().isEmpty ? 'AdhanBox' : _nameController.text.trim();
                await saveDeviceIp(ref, _deviceIp!, name: name);
              }
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const CalculationSetupScreen()),
              );
            },
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Configurer les horaires'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ).animate().fadeIn(delay: 500.ms),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () async {
              if (_deviceIp != null) {
                final name = _nameController.text.trim().isEmpty ? 'AdhanBox' : _nameController.text.trim();
                await saveDeviceIp(ref, _deviceIp!, name: name);
              }
              Navigator.of(context).pop();
            },
            child: const Text('Revenir à l\'accueil'),
          ),
        ).animate().fadeIn(delay: 550.ms),
      ],
    );
  }

  int _signalPercent(int rssi) {
    if (rssi >= -50) return 100;
    if (rssi <= -100) return 0;
    return ((rssi + 100) * 2).clamp(0, 100);
  }
}

// ═══════════════════════════════════════════════════════════════
//  REUSABLE THEMED WIDGETS
// ═══════════════════════════════════════════════════════════════

class _StepMeta {
  final IconData icon;
  final String label;
  const _StepMeta({required this.icon, required this.label});
}

// ─────────────────── HEADER ───────────────────

class _SetupHeader extends StatelessWidget {
  final int step;
  const _SetupHeader({required this.step});

  static const _titles = [
    'Détection', 'Connexion', 'Configuration WiFi', 'Recherche', 'Terminé'
  ];
  static const _subtitles = [
    'Recherche des appareils',
    'Liaison avec l\'AdhanBox',
    'Réseau domestique',
    'Localisation sur le réseau',
    'Tout est prêt !',
  ];

  @override
  Widget build(BuildContext context) {
    final idx = (step - 1).clamp(0, 4);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF064E3B), Color(0xFF065F46), Color(0xFF059669)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GeomPainter())),
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Étape $step sur 5',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  _titles[idx],
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitles[idx],
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────── STEP INDICATOR ───────────────────

class _ModernStepIndicator extends StatelessWidget {
  final int current;
  final List<_StepMeta> steps;
  const _ModernStepIndicator({required this.current, required this.steps});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepBefore = (i ~/ 2) + 1;
          final done = current > stepBefore;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: done ? AppTheme.emerald : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }
        final stepIdx = i ~/ 2;
        final stepNum = stepIdx + 1;
        final isActive = current >= stepNum;
        final isCurrent = current == stepNum;
        final meta = steps[stepIdx];

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isCurrent ? 40 : 32,
              height: isCurrent ? 40 : 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? (isCurrent ? AppTheme.emerald : AppTheme.emerald.withOpacity(0.15))
                    : (isDark ? AppTheme.darkSurface : AppTheme.lightBg),
                border: Border.all(
                  color: isActive ? AppTheme.emerald : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                  width: isCurrent ? 2 : 1,
                ),
              ),
              child: Icon(
                isActive && !isCurrent ? Icons.check_rounded : meta.icon,
                color: isActive ? (isCurrent ? Colors.white : AppTheme.emerald) : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                size: isCurrent ? 20 : 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              meta.label,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? (isCurrent ? AppTheme.emerald : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))
                    : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ─────────────────── STEP TITLE ───────────────────

class _StepTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _StepTitle({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppTheme.emerald, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

// ─────────────────── THEMED CARD ───────────────────

class _ThemedCard extends StatelessWidget {
  final Widget child;
  const _ThemedCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
    );
  }
}

// ─────────────────── LOADING CARD ───────────────────

class _LoadingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final AnimationController pulseController;
  const _LoadingCard({required this.icon, required this.title, required this.subtitle, required this.pulseController});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _ThemedCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: pulseController,
              builder: (_, child) => Opacity(
                opacity: 0.5 + 0.5 * pulseController.value,
                child: child,
              ),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.emerald.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppTheme.emerald, size: 36),
              ),
            ),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                backgroundColor: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                color: AppTheme.emerald,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────── EMPTY STATE CARD ───────────────────

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> actions;
  const _EmptyStateCard({required this.icon, required this.title, required this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return _ThemedCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.gold.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.gold, size: 36),
            ),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              ...actions,
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────── INSTRUCTION CARD ───────────────────

class _InstructionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> steps;
  final Widget? action;
  const _InstructionCard({required this.icon, required this.iconColor, required this.title, required this.steps, this.action});

  @override
  Widget build(BuildContext context) {
    return _ThemedCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...steps.asMap().entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${e.key + 1}',
                          style: GoogleFonts.inter(color: AppTheme.emerald, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(e.value, style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (action != null) ...[
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: action),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────── WIFI TILE ───────────────────

class _WifiNetworkTile extends StatelessWidget {
  final String ssid;
  final int rssi;
  final bool isSelected;
  final bool isAdhanbox;
  final VoidCallback onTap;
  const _WifiNetworkTile({required this.ssid, required this.rssi, required this.isSelected, this.isAdhanbox = false, required this.onTap});

  int get _signalPercent {
    if (rssi >= -50) return 100;
    if (rssi <= -100) return 0;
    return ((rssi + 100) * 2).clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.emerald.withOpacity(isDark ? 0.12 : 0.06)
              : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.emerald.withOpacity(0.5) : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (isAdhanbox ? AppTheme.emerald : AppTheme.fajrColor).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isAdhanbox
                  ? const Icon(Icons.mosque_rounded, color: AppTheme.emerald, size: 22)
                  : _SignalIcon(strength: _signalPercent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ssid, style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? AppTheme.emerald : null,
                  )),
                  Text('$rssi dBm · $_signalPercent%', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            isSelected
                ? const Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 24)
                : Icon(Icons.circle_outlined, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder, size: 24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────── SIGNAL ICON ───────────────────

class _SignalIcon extends StatelessWidget {
  final int strength;
  final double size;
  const _SignalIcon({required this.strength, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final color = strength >= 75 ? AppTheme.emerald : (strength >= 40 ? AppTheme.gold : Colors.red);
    final icon = strength >= 75
        ? Icons.signal_wifi_4_bar_rounded
        : (strength >= 40 ? Icons.network_wifi_3_bar_rounded : Icons.signal_wifi_0_bar_rounded);
    return Icon(icon, color: color, size: size);
  }
}

// ─────────────────── ERROR BANNER ───────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  const _ErrorBanner({required this.message, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.red, fontSize: 13))),
          if (onDismiss != null)
            GestureDetector(
              onTap: onDismiss,
              child: const Icon(Icons.close_rounded, color: Colors.red, size: 16),
            ),
        ],
      ),
    );
  }
}

// ─────────────────── ACTION BUTTON ───────────────────

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isPrimary;
  const _ActionBtn({required this.label, required this.icon, required this.onPressed, this.isPrimary = true});

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return ElevatedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label));
    }
    return OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label));
  }
}

// ─────────────────── NEXT STEP ITEM ───────────────────

class _NextStepItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _NextStepItem({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}

// ─────────────────── GEOMETRIC PATTERN ───────────────────

class _GeomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const step = 50.0;
    for (double x = 0; x < size.width + step; x += step) {
      for (double y = 0; y < size.height + step; y += step) {
        canvas.drawCircle(Offset(x, y), 18, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
