import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:app_settings/app_settings.dart';
import '../providers/adhanbox_provider.dart';
import '../services/adhanbox_api.dart';
import '../services/esp32_discovery_service.dart';
import '../theme/app_theme.dart';
import 'calculation_setup_screen.dart';

enum _Phase { detecting, bleScan, bleWifi, connectAP, homeWifi, searching, done }

class DeviceSetupScreen extends ConsumerStatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  ConsumerState<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends ConsumerState<DeviceSetupScreen>
    with SingleTickerProviderStateMixin {

  _Phase _phase = _Phase.detecting;
  String? _error;
  String? _deviceIp;
  String? _selectedHomeWifi;
  List<Map<String, dynamic>> _homeWifiNetworks = [];
  bool _isBusy = false;
  bool _showPassword = false;
  bool _showManualEntry = false;
  String _progressText = '';

  final _passwordController = TextEditingController();
  final _manualIpController = TextEditingController();
  final _nameController = TextEditingController(text: 'AdhanBox');
  late AnimationController _pulseController;

  // ── BLE ──
  static const _bleSvcUuid      = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const _bleSsidUuid     = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const _blePassUuid     = 'beb5483e-36e1-4688-b7f5-ea07361b26a9';
  static const _bleStatusUuid   = 'beb5483e-36e1-4688-b7f5-ea07361b26aa';
  static const _bleWifiScanUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26ab'; // WiFi scan

  final Map<String, ScanResult> _bleDeviceMap = {};
  List<ScanResult> _bleDevices = [];
  BluetoothDevice? _selectedBleDevice;
  BluetoothCharacteristic? _bleSsidChar;
  BluetoothCharacteristic? _blePassChar;
  BluetoothCharacteristic? _bleWifiScanChar;     // WiFi scan via BLE
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _bleStatusSub;
  StreamSubscription<List<int>>? _bleWifiScanSub; // WiFi scan results from ESP32
  final List<Map<String, dynamic>> _tempBleWifiNetworks = [];
  bool _isBleScanDone = false;
  bool _isScanning = false;
  String? _currentWifiSsid;

  static const _stepMetas = [
    _StepMeta(icon: Icons.bluetooth_rounded,     label: 'Bluetooth'),
    _StepMeta(icon: Icons.wifi_rounded,          label: 'WiFi'),
    _StepMeta(icon: Icons.search_rounded,        label: 'Recherche'),
    _StepMeta(icon: Icons.check_circle_rounded,  label: 'Terminé'),
  ];

  int get _stepIndex {
    switch (_phase) {
      case _Phase.detecting:  return 0;
      case _Phase.bleScan:    return 1;
      case _Phase.connectAP:  return 1;
      case _Phase.bleWifi:    return 2;
      case _Phase.homeWifi:   return 2;
      case _Phase.searching:  return 3;
      case _Phase.done:       return 4;
    }
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _autoDetect();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _passwordController.dispose();
    _manualIpController.dispose();
    _nameController.dispose();
    _scanSub?.cancel();
    _bleStatusSub?.cancel();
    _bleWifiScanSub?.cancel();
    if (!kIsWeb) FlutterBluePlus.stopScan();
    try { _selectedBleDevice?.disconnect(); } catch (_) {}
    super.dispose();
  }

  // ── Auto-detect: find new device on current network ──
  Future<void> _autoDetect() async {
    setState(() { _phase = _Phase.detecting; _error = null; });

    Set<String> knownIps = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('savedDevices');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        knownIps = list.map((e) => e['ip'] as String).toSet();
      }
    } catch (_) {}

    try {
      final discovery = ESP32DiscoveryService();
      final devices = await discovery.discoverDevices(timeout: const Duration(seconds: 5));
      for (final d in devices) {
        if (knownIps.contains(d.host)) continue;
        if (!mounted) return;
        try {
          final api = AdhanBoxAPI(baseUrl: 'http://${d.host}', timeout: const Duration(seconds: 4));
          final status = await api.getStatus();
          if (status.containsKey('wifi') || status.containsKey('rtc_ok')) {
            await _finalizeDevice(d.host);
            return;
          }
        } catch (_) {}
      }
    } catch (_) {}

    if (mounted) _startBleScan();
  }

  Future<void> _startBleScan() async {
    setState(() {
      _phase = _Phase.bleScan;
      _bleDeviceMap.clear();
      _bleDevices = [];
      _isBleScanDone = false;
      _error = null;
      _isBusy = false;  // pas busy pendant le scan — on veut pouvoir tapper
      _isScanning = true;
    });

    // Pre-fill with current WiFi SSID
    try {
      final info = NetworkInfo();
      final ssid = await info.getWifiName();
      if (ssid != null && mounted) {
        setState(() => _currentWifiSsid = ssid.replaceAll('"', ''));
      }
    } catch (_) {}

    // Request BLE permissions
    if (!kIsWeb) {
      if (Platform.isAndroid) {
        await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
      } else if (Platform.isIOS) {
        // Sur iOS, CoreBluetooth gère la permission via le popup système
        // (déclenché au premier scan). On vérifie juste l'état de l'adaptateur.
        // flutter_blue_plus s'occupe de demander la permission automatiquement.
        await Permission.locationWhenInUse.request();
      }
    }

    try {
      // Attendre que l'adaptateur BLE soit prêt (important sur iOS)
      BluetoothAdapterState adapterState = await FlutterBluePlus.adapterState
          .timeout(const Duration(seconds: 5), onTimeout: (sink) {
            sink.add(BluetoothAdapterState.unknown);
          })
          .firstWhere((s) => s != BluetoothAdapterState.unknown,
              orElse: () => BluetoothAdapterState.unknown);

      // Sur iOS, si l'état est "unauthorized" ou "unknown", afficher un message clair
      if (adapterState == BluetoothAdapterState.unauthorized) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _isBleScanDone = true;
            _error = 'Permission Bluetooth refusée. Allez dans Réglages → Adhanbox et activez le Bluetooth.';
          });
        }
        return;
      }

      if (adapterState != BluetoothAdapterState.on) {
        if (mounted) setState(() { _isScanning = false; _isBleScanDone = true; _error = 'Bluetooth désactivé. Activez le Bluetooth pour continuer.'; });
        return;
      }

      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        if (!mounted) return;
        for (final r in results) {
          _bleDeviceMap[r.device.remoteId.str] = r;
        }
        setState(() => _bleDevices = _bleDeviceMap.values.toList());
      });

      // Sur iOS, filtrer par UUID de service peut empêcher la détection si l'ESP32
      // n'inclut pas l'UUID dans le advertising packet. On fait un scan sans filtre
      // et on filtre côté app par nom ("AdhanBox").
      await FlutterBluePlus.startScan(
        withServices: kIsWeb ? [] : (Platform.isIOS
            ? []  // iOS : scan ouvert, filtrage par nom fait ci-dessous
            : [Guid(_bleSvcUuid)]),  // Android : filtre par service UUID
        withKeywords: Platform.isIOS ? ['AdhanBox'] : [],
        timeout: const Duration(seconds: 12),
      );

      // Attendre la fin du scan sans bloquer le tap
      await FlutterBluePlus.isScanning.where((v) => !v).first;
    } on TimeoutException {
      if (mounted) setState(() => _error = 'Délai dépassé. Vérifiez que le Bluetooth est activé.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Bluetooth indisponible. Vérifiez que le Bluetooth est activé.');
    }

    if (mounted && _phase == _Phase.bleScan) {
      setState(() { _isScanning = false; _isBleScanDone = true; });
    }
  }

  // ── Connect to selected BLE device ──
  Future<void> _connectBleDevice(ScanResult result) async {
    final device = result.device;
    setState(() { _isBusy = true; _error = null; _selectedBleDevice = device; });

    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();

    try {
      await device.connect(timeout: const Duration(seconds: 10));

      // Request larger MTU on Android for reliable data transfer
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await device.requestMtu(512);
        } catch (e) {
          debugPrint('Failed to request MTU: $e');
        }
      }

      final services = await device.discoverServices();

      for (final svc in services) {
        if (svc.serviceUuid == Guid(_bleSvcUuid)) {
          for (final char in svc.characteristics) {
            final uuid = char.characteristicUuid;
            if (uuid == Guid(_bleSsidUuid))   _bleSsidChar = char;
            if (uuid == Guid(_blePassUuid))   _blePassChar = char;
            if (uuid == Guid(_bleStatusUuid)) {
              await char.setNotifyValue(true);
              _bleStatusSub?.cancel();
              _bleStatusSub = char.onValueReceived.listen(_handleBleStatus);
            }
            if (uuid == Guid(_bleWifiScanUuid)) {
              _bleWifiScanChar = char;
              await char.setNotifyValue(true);
              _bleWifiScanSub?.cancel();
              _bleWifiScanSub = char.onValueReceived.listen(_handleBleWifiScanResults);
            }
          }
          break;
        }
      }

      if (_bleSsidChar == null || _blePassChar == null) {
        throw Exception('Caractéristiques BLE introuvables');
      }

      setState(() { _phase = _Phase.bleWifi; _isBusy = false; });
      await _getPhoneWifiNetworks();
    } catch (_) {
      try { await device.disconnect(); } catch (_) {}
      if (mounted) {
        setState(() {
          _isBusy = false;
          _selectedBleDevice = null;
          _error = 'Connexion BLE échouée. Réessayez.';
        });
      }
    }
  }

  // ── Get WiFi networks from phone scan (BLE flow) ──
  Future<void> _getPhoneWifiNetworks() async {
    if (_isScanning) return; // déjà en cours
    setState(() { _isScanning = true; _error = null; });

    // Récupérer le SSID actuel du téléphone
    try {
      final info = NetworkInfo();
      final ssid = await info.getWifiName();
      if (ssid != null && mounted) {
        final cleaned = ssid.replaceAll('"', '');
        setState(() {
          _currentWifiSsid = cleaned;
          if (_selectedHomeWifi == null && cleaned.isNotEmpty) {
            _selectedHomeWifi = cleaned;
          }
        });
      }
    } catch (_) {}

    // Si on est connecté via BLE à l'AdhanBox, on demande à l'AdhanBox de scanner les réseaux WiFi
    if (_selectedBleDevice != null && _bleWifiScanChar != null) {
      try {
        await _bleWifiScanChar!.write(utf8.encode('scan'), withoutResponse: false);
        // Timeout de sécurité au cas où l'ESP32 ne renverrait rien
        Future.delayed(const Duration(seconds: 15)).then((_) {
          if (mounted && _isScanning && _homeWifiNetworks.isEmpty) {
            setState(() {
              _isScanning = false;
              _error = 'Délai d\'attente du scan WiFi dépassé.';
            });
          }
        });
        return; // Attend les notifications dans _handleBleWifiScanResults
      } catch (e) {
        debugPrint('Erreur lors du déclenchement du scan BLE: $e');
      }
    }

    // Fallback : sur iOS, wifi_scan n'est pas supporté (et le BLE scan a échoué / indisponible)
    if (!kIsWeb && Platform.isIOS) {
      if (_currentWifiSsid != null && _currentWifiSsid!.isNotEmpty) {
        setState(() {
          _homeWifiNetworks = [
            {'ssid': _currentWifiSsid!, 'rssi': -60, 'security': 'WPA2'},
          ];
          _selectedHomeWifi = _currentWifiSsid;
        });
      }
      if (mounted) setState(() => _isScanning = false);
      return;
    }

    try {
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        await Future.delayed(const Duration(seconds: 2));
        final results = await WiFiScan.instance.getScannedResults();
        if (!mounted) return;
        final networks = results
            .where((n) => n.ssid.isNotEmpty)
            .map((n) => <String, dynamic>{
                  'ssid': n.ssid,
                  'rssi': n.level,
                  'security': n.capabilities.toLowerCase().contains('wpa') ? 'WPA2' : 'Open',
                })
            .toList()
          ..sort((a, b) => (b['rssi'] as int).compareTo(a['rssi'] as int));
        setState(() {
          _homeWifiNetworks = networks;
          // Sélectionner automatiquement le réseau actuel s'il est dans la liste
          if (_selectedHomeWifi == null && _currentWifiSsid != null) {
            final match = networks.any((n) => n['ssid'] == _currentWifiSsid);
            if (match) _selectedHomeWifi = _currentWifiSsid;
          }
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isScanning = false);
  }

  // ── Send WiFi credentials via BLE ──
  Future<void> _sendBleWifiCreds() async {
    if (_selectedHomeWifi == null) return;
    setState(() { _isBusy = true; _error = null; _phase = _Phase.searching; _progressText = 'Envoi des identifiants…'; });
    try {
      await _bleSsidChar!.write(utf8.encode(_selectedHomeWifi!), withoutResponse: false);
      await Future.delayed(const Duration(milliseconds: 300));
      await _blePassChar!.write(utf8.encode(_passwordController.text), withoutResponse: false);
      if (mounted) setState(() => _progressText = 'Connexion WiFi en cours…');
      // Timeout fallback
      Future.delayed(const Duration(seconds: 90)).then((_) {
        if (mounted && _phase == _Phase.searching && _isBusy) {
          setState(() {
            _isBusy = false;
            _showManualEntry = true;
            _progressText = '';
            _error = 'AdhanBox introuvable. Entrez l\'IP manuellement.';
          });
        }
      });
    } catch (_) {
      if (mounted) setState(() { _isBusy = false; _error = 'Envoi BLE échoué. Réessayez.'; _phase = _Phase.bleWifi; });
    }
  }

  // ── Handle BLE status notification from firmware ──
  void _handleBleStatus(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final ok = json['ok'] as bool? ?? false;
      if (ok) {
        final ip = json['ip'] as String?;
        if (ip != null && mounted) {
          _bleStatusSub?.cancel();
          try { _selectedBleDevice?.disconnect(); } catch (_) {}
          _finalizeDevice(ip);
        }
      } else {
        final err = json['error'] as String? ?? 'wifi_failed';
        if (mounted) {
          setState(() {
            _isBusy = false;
            _error = err == 'wifi_failed'
                ? 'Connexion WiFi échouée. Vérifiez le mot de passe.'
                : 'Erreur: $err. Réessayez.';
            _phase = _Phase.bleWifi;
          });
        }
      }
    } catch (_) {}
  }

  // ── Handle WiFi networks scan results streamed from ESP32 ──
  void _handleBleWifiScanResults(List<int> bytes) {
    if (bytes.isEmpty) return;
    try {
      final jsonStr = utf8.decode(bytes);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'start') {
        _tempBleWifiNetworks.clear();
      } else if (type == 'item') {
        final ssid = data['ssid'] as String? ?? '';
        if (ssid.isNotEmpty) {
          _tempBleWifiNetworks.add({
            'ssid': ssid,
            'rssi': data['rssi'] as int? ?? -100,
            'security': (data['secure'] == 1) ? 'WPA2' : 'Open',
          });
        }
      } else if (type == 'end') {
        if (mounted) {
          setState(() {
            // Tri des réseaux par signal décroissant
            _tempBleWifiNetworks.sort((a, b) => (b['rssi'] as int).compareTo(a['rssi'] as int));
            // Éviter les doublons
            final seenSSIDs = <String>{};
            _homeWifiNetworks = _tempBleWifiNetworks.where((net) {
              final ssid = net['ssid'] as String;
              if (seenSSIDs.contains(ssid)) return false;
              seenSSIDs.add(ssid);
              return true;
            }).toList();
            _isScanning = false;

            // Sélectionner automatiquement le réseau actuel s'il est trouvé
            if (_selectedHomeWifi == null && _currentWifiSsid != null) {
              final match = _homeWifiNetworks.any((n) => n['ssid'] == _currentWifiSsid);
              if (match) _selectedHomeWifi = _currentWifiSsid;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error parsing BLE WiFi scan chunk: $e');
    }
  }

  // ── Step 1 AP fallback: Poll 192.168.4.1 ──
  Future<void> _waitForAP() async {
    setState(() { _isBusy = true; _error = null; });
    for (int i = 0; i < 12; i++) {
      if (!mounted) return;
      try {
        final api = AdhanBoxAPI(baseUrl: 'http://192.168.4.1', timeout: const Duration(seconds: 5));
        final status = await api.getStatus();
        if (status.containsKey('wifi') || status.containsKey('rtc_ok')) {
          if (!mounted) return;
          setState(() { _isBusy = false; _phase = _Phase.homeWifi; });
          await _getHomeWifiNetworks();
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
    if (mounted) {
      setState(() {
        _isBusy = false;
        _error = 'Impossible de contacter l\'AdhanBox. Vérifiez que vous êtes connecté au réseau AdhanBox-XXXX.';
      });
    }
  }

  // ── Step 2 AP: fetch WiFi list from ESP32 ──
  Future<void> _getHomeWifiNetworks() async {
    if (_isScanning) return;
    setState(() { _isScanning = true; _error = null; });
    try {
      final api = AdhanBoxAPI(baseUrl: 'http://192.168.4.1', timeout: const Duration(seconds: 10));
      final networks = await api.scanWiFiNetworks();
      if (!mounted) return;
      final list = networks.map((n) => <String, dynamic>{
        'ssid': n['ssid'], 'rssi': n['rssi'],
        'security': n['secure'] == 1 ? 'WPA2' : 'Open',
      }).toList()
        ..sort((a, b) => (b['rssi'] as int? ?? 0).compareTo(a['rssi'] as int? ?? 0));
      setState(() {
        _homeWifiNetworks = list;
        _isScanning = false;
      });
    } catch (_) {
      // Fallback : scan depuis le téléphone
      try {
        final canScan = await WiFiScan.instance.canStartScan();
        if (canScan == CanStartScan.yes) {
          await WiFiScan.instance.startScan();
          await Future.delayed(const Duration(seconds: 2));
          final results = await WiFiScan.instance.getScannedResults();
          if (!mounted) return;
          final list2 = results
              .where((n) => n.ssid.isNotEmpty)
              .map((n) => <String, dynamic>{
                    'ssid': n.ssid,
                    'rssi': n.level,
                    'security': n.capabilities.toLowerCase().contains('wpa') ? 'WPA2' : 'Open',
                  })
              .toList()
            ..sort((a, b) => (b['rssi'] as int? ?? 0).compareTo(a['rssi'] as int? ?? 0));
          if (mounted) setState(() { _homeWifiNetworks = list2; });
          return;
        }
      } catch (_) {}
      if (mounted) setState(() => _error = 'Impossible de récupérer la liste WiFi.');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  // ── Step 2 → 3 AP: send credentials ──
  Future<void> _sendWifiCredentials() async {
    if (_selectedHomeWifi == null) return;
    setState(() { _isBusy = true; _error = null; });
    try {
      final api = AdhanBoxAPI(baseUrl: 'http://192.168.4.1', timeout: const Duration(seconds: 10));
      await api.connectWiFi(_selectedHomeWifi!, _passwordController.text);
      if (!mounted) return;
      setState(() { _isBusy = false; _phase = _Phase.searching; _showManualEntry = false; });
      _startHomePolling();
    } catch (_) {
      if (mounted) setState(() { _isBusy = false; _error = 'Envoi échoué. Vérifiez le mot de passe.'; });
    }
  }

  // ── Step 3: Auto-poll home network ──
  Future<void> _startHomePolling() async {
    setState(() { _isBusy = true; _showManualEntry = false; });
    for (int i = 0; i < 30; i++) {
      if (!mounted) return;
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      setState(() => _progressText = 'Tentative ${i + 1}…');
      try {
        final discovery = ESP32DiscoveryService();
        final devices = await discovery.discoverDevices(timeout: const Duration(seconds: 4));
        for (final d in devices) {
          try {
            final api = AdhanBoxAPI(baseUrl: 'http://${d.host}', timeout: const Duration(seconds: 3));
            final status = await api.getStatus();
            if (status.containsKey('wifi') || status.containsKey('rtc_ok')) {
              await _finalizeDevice(d.host);
              return;
            }
          } catch (_) {}
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isBusy = false;
        _showManualEntry = true;
        _progressText = '';
        _error = 'AdhanBox introuvable. Reconnectez votre téléphone à votre WiFi, puis entrez l\'IP manuellement.';
      });
    }
  }

  // ── Manual IP test ──
  Future<void> _testManualIp() async {
    final ip = _manualIpController.text.trim();
    if (ip.isEmpty) return;
    setState(() { _isBusy = true; _error = null; });
    try {
      final api = AdhanBoxAPI(baseUrl: 'http://$ip', timeout: const Duration(seconds: 5));
      final status = await api.getStatus();
      if (status.containsKey('wifi') || status.containsKey('rtc_ok')) {
        await _finalizeDevice(ip);
      } else {
        if (mounted) setState(() { _isBusy = false; _error = 'Cette adresse ne correspond pas à un AdhanBox.'; });
      }
    } catch (_) {
      if (mounted) setState(() { _isBusy = false; _error = 'Impossible de contacter $ip.'; });
    }
  }

  // ── Finalize: save device, set location + RTC ──
  Future<void> _finalizeDevice(String ip) async {
    await saveDeviceIp(ref, ip, name: 'Nouvel Appareil');
    
    // Fetch device info to pair and retrieve API token
    String? token;
    try {
      final devApi = AdhanBoxAPI(baseUrl: 'http://$ip', timeout: const Duration(seconds: 3));
      final info = await devApi.getDeviceInfo();
      token = info['token'] as String?;
      if (token != null && token.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('api_token_$ip', token);
        ref.read(adhanboxApiKeyProvider.notifier).state = token;
      }
    } catch (_) {}

    final api = AdhanBoxAPI(
      baseUrl: 'http://$ip',
      timeout: const Duration(seconds: 5),
      apiKey: token,
    );

    // 1. Send Geolocation
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      await api.setLocation(pos.latitude, pos.longitude, pos.accuracy);
    } catch (_) {}

    // 2. Send timezone offset (minutes)
    try {
      final tzOffsetMin = DateTime.now().timeZoneOffset.inMinutes;
      await api.setTimezone(tzOffsetMin);
    } catch (_) {}

    // 3. Sync RTC time with smartphone local time
    try {
      await api.setRtcTime(DateTime.now());
    } catch (_) {}

    if (mounted) setState(() { _deviceIp = ip; _phase = _Phase.done; _isBusy = false; });
  }

  Future<void> _openWiFiSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.wifi);
    } catch (_) {
      try { await AppSettings.openAppSettings(type: AppSettingsType.settings); } catch (_) {}
    }
  }

  // ═══════════════════════ BUILD ═══════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: AppTheme.emeraldDeep,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _SetupHeader(phase: _phase),
            ),
            title: Text(
              'Configuration',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
            ),
          ),

          if (_phase != _Phase.detecting)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _ModernStepIndicator(current: _stepIndex, steps: _stepMetas),
              ),
            ),

          if (_error != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _ErrorBanner(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null),
                ).animate().fadeIn().slideY(begin: -0.1),
              ),
            ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOut,
                child: _buildPhase(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhase() {
    switch (_phase) {
      case _Phase.detecting:  return _buildDetecting(key: const ValueKey('d'));
      case _Phase.bleScan:    return _buildBleScan(key: const ValueKey('bs'));
      case _Phase.bleWifi:    return _buildWifiSelector(key: const ValueKey('bw'), isBle: true);
      case _Phase.connectAP:  return _buildConnectAP(key: const ValueKey('ap'));
      case _Phase.homeWifi:   return _buildWifiSelector(key: const ValueKey('hw'), isBle: false);
      case _Phase.searching:  return _buildSearching(key: const ValueKey('s'));
      case _Phase.done:       return _buildDone(key: const ValueKey('ok'));
    }
  }

  // ── DETECTING ──
  Widget _buildDetecting({Key? key}) => _LoadingCard(
    key: key,
    icon: Icons.radar_rounded,
    title: 'Recherche de l\'AdhanBox…',
    subtitle: 'Vérification sur le réseau local',
    pulseController: _pulseController,
  ).animate().fadeIn();

  // ── BLE SCAN ──
  Widget _buildBleScan({Key? key}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          icon: Icons.bluetooth_searching_rounded,
          title: 'Connexion Bluetooth',
          subtitle: 'Sélectionnez votre AdhanBox à proximité',
        ),
        const SizedBox(height: 16),

        // ── Bannière tutoriel BLE ──────────────────────────────────────────
        _BleTutorialBanner(),
        const SizedBox(height: 16),

        if ((_isScanning || _isBusy) && _bleDevices.isEmpty)
          _LoadingCard(
            icon: Icons.bluetooth_searching_rounded,
            title: 'Recherche Bluetooth…',
            subtitle: 'Scan en cours (10 secondes)',
            pulseController: _pulseController,
          )
        else if (_bleDevices.isEmpty && _isBleScanDone)
          _EmptyStateCard(
            icon: Icons.bluetooth_disabled_rounded,
            title: 'Aucun appareil trouvé',
            subtitle: 'Assurez-vous que l\'AdhanBox est sous tension et à proximité (< 5m).',
            actions: [
              _ActionBtn(label: 'Réessayer', icon: Icons.refresh_rounded, isPrimary: true, onPressed: _startBleScan),
              const SizedBox(height: 10),
              _ActionBtn(
                label: 'Configurer via WiFi AP',
                icon: Icons.wifi_rounded,
                isPrimary: false,
                onPressed: () => setState(() { _phase = _Phase.connectAP; _error = null; }),
              ),
            ],
          )
        else if (_bleDevices.isNotEmpty) ...[
          _ThemedCard(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.bluetooth_rounded, color: Color(0xFF3B82F6), size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Appareils détectés',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                      if (_isBusy)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald)),
                    ],
                  ),
                ),
                Divider(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: _bleDevices.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1, indent: 56,
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  ),
                  itemBuilder: (_, i) {
                    final r = _bleDevices[i];
                    final name = r.advertisementData.advName.isNotEmpty
                        ? r.advertisementData.advName
                        : r.device.platformName.isNotEmpty
                            ? r.device.platformName
                            : 'AdhanBox';
                    final isConnecting = _isBusy && _selectedBleDevice == r.device;
                    return ListTile(
                      leading: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.router_rounded, color: Color(0xFF3B82F6), size: 20),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${r.rssi} dBm',
                          style: Theme.of(context).textTheme.bodySmall),
                      trailing: isConnecting
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald))
                          : const Icon(Icons.chevron_right_rounded, color: AppTheme.emerald),
                      onTap: _isBusy ? null : () => _connectBleDevice(r),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _isBusy ? null : _startBleScan,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Rafraîchir'),
            ),
          ),
        ],

        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: _isBusy ? null : () => setState(() { _phase = _Phase.connectAP; _error = null; }),
            child: Text(
              'Configurer sans Bluetooth (mode AP)',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
          ),
        ),
      ],
    ).animate().fadeIn();
  }

  // ── WIFI PASSWORD PROMPT DIALOG ──
  void _promptWifiPassword(String ssid, bool isBle) {
    _passwordController.clear();
    setState(() {
      _selectedHomeWifi = ssid;
    });
    bool showPasswordLocal = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final cardBg = isDark ? AppTheme.darkCard : AppTheme.lightCard;
            final borderCol = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
            
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderCol),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.emerald.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.wifi_lock_rounded, color: AppTheme.emerald, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Connexion au WiFi',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Entrez le mot de passe pour le réseau :',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ssid,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppTheme.emerald,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: !showPasswordLocal,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        Navigator.pop(context);
                        if (isBle) {
                          _sendBleWifiCreds();
                        } else {
                          _sendWifiCredentials();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.key_rounded, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(
                            showPasswordLocal
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 18,
                          ),
                          onPressed: () => setDialogState(() => showPasswordLocal = !showPasswordLocal),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '(Laissez vide si réseau ouvert)',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _selectedHomeWifi = null;
                            });
                          },
                          child: Text(
                            'Annuler',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            if (isBle) {
                              _sendBleWifiCreds();
                            } else {
                              _sendWifiCredentials();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.emerald,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Connecter'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── WIFI SELECTOR (shared between BLE and AP flows) ──
  Widget _buildWifiSelector({Key? key, required bool isBle}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIos = !kIsWeb && Platform.isIOS;
    final onRefresh = isBle ? _getPhoneWifiNetworks : _getHomeWifiNetworks;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          icon: Icons.wifi_rounded,
          title: 'Votre réseau WiFi',
          subtitle: 'Connectez l\'AdhanBox à votre réseau domestique',
        ),
        const SizedBox(height: 16),

        // ── Carte scan WiFi ──────────────────────────────────────────────────
        _ThemedCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête avec statut + bouton refresh
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: Row(
                  children: [
                    _isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.emerald,
                            ),
                          )
                        : const Icon(Icons.wifi_find_rounded,
                            color: AppTheme.emerald, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isScanning
                            ? 'Recherche des réseaux…'
                            : _homeWifiNetworks.isEmpty
                                ? (isIos ? 'Entrez votre réseau WiFi' : 'Aucun réseau détecté')
                                : '${_homeWifiNetworks.length} réseau${_homeWifiNetworks.length > 1 ? 'x' : ''} disponible${_homeWifiNetworks.length > 1 ? 's' : ''}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _isScanning
                              ? AppTheme.emerald
                              : null,
                        ),
                      ),
                    ),
                    // Bouton Rafraîchir
                    AnimatedOpacity(
                      opacity: _isScanning ? 0.4 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: IconButton(
                        onPressed: _isScanning ? null : onRefresh,
                        icon: const Icon(Icons.refresh_rounded),
                        iconSize: 20,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        tooltip: 'Relancer le scan',
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),

              // Barre de progression pendant le scan
              if (_isScanning)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      backgroundColor:
                          isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                      color: AppTheme.emerald,
                      minHeight: 3,
                    ),
                  ),
                ),

              Divider(
                  height: 1,
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),

              // Liste des réseaux trouvés
              if (_homeWifiNetworks.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _homeWifiNetworks.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 56,
                      color:
                          isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                    ),
                    itemBuilder: (_, i) {
                      final n = _homeWifiNetworks[i];
                      final ssid = n['ssid']?.toString() ?? '';
                      final rssi = n['rssi'] as int? ?? 0;
                      final isSelected = _selectedHomeWifi == ssid;
                      return _WifiNetworkTile(
                        ssid: ssid,
                        rssi: rssi,
                        isSelected: isSelected,
                        isCurrent: ssid == _currentWifiSsid,
                        onTap: () => _promptWifiPassword(ssid, isBle),
                      );
                    },
                  ),
                )
              else if (!_isScanning)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isIos
                            ? Icons.phone_iphone_rounded
                            : Icons.wifi_off_rounded,
                        color: isDark
                            ? AppTheme.darkTextMuted
                            : AppTheme.lightTextMuted,
                        size: 17,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isIos
                              ? 'Sur iPhone, seul le réseau actuellement connecté peut être détecté automatiquement. Entrez le nom de votre réseau WiFi ci-dessous.'
                              : 'Aucun réseau détecté. Vérifiez que le WiFi est activé et relancez le scan.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Champ saisie SSID manuelle ─────────────────────────────────
              // Toujours visible : utile sur iOS, réseaux cachés, ou si liste vide
              Divider(
                  height: 1,
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              _ManualSsidRow(
                currentSsid: _currentWifiSsid,
                selectedSsid: _selectedHomeWifi,
                // Auto-ouvrir sur iOS quand la liste est vide
                autoExpand: isIos && _homeWifiNetworks.isEmpty && !_isScanning,
                onSelect: (ssid) => _promptWifiPassword(ssid, isBle),
              ),
            ],
          ),
        ),

        // ── Saisie mot de passe / Statut de connexion ────────────────────────
        if (_isBusy && _selectedHomeWifi != null) ...[
          const SizedBox(height: 14),
          _ThemedCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppTheme.emerald,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connexion de l\'AdhanBox…',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Envoi des identifiants au réseau $_selectedHomeWifi',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(),
        ],
      ],
    );
  }

  // ── STEP 1 AP: Connect to AdhanBox hotspot ──
  Widget _buildConnectAP({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          icon: Icons.link_rounded,
          title: 'Connexion à l\'AdhanBox',
          subtitle: 'Connectez votre téléphone au réseau WiFi de l\'appareil',
        ),
        const SizedBox(height: 20),

        if (_isBusy)
          _LoadingCard(
            icon: Icons.link_rounded,
            title: 'Connexion en cours…',
            subtitle: 'Vérification de la communication',
            pulseController: _pulseController,
          )
        else ...[
          _InstructionCard(
            icon: Icons.smartphone_rounded,
            iconColor: AppTheme.fajrColor,
            title: 'Connectez-vous au réseau AdhanBox',
            steps: const [
              'Ouvrez les paramètres WiFi de votre téléphone',
              'Sélectionnez le réseau "AdhanBox-XXXX"',
              'Aucun mot de passe nécessaire',
              'Revenez ici et appuyez sur le bouton ci-dessous',
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
              onPressed: _waitForAP,
              icon: const Icon(Icons.check_circle_rounded, size: 20),
              label: const Text('Je suis connecté'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _startBleScan,
              icon: const Icon(Icons.bluetooth_rounded, size: 16),
              label: const Text('Revenir à la configuration Bluetooth'),
            ),
          ),
        ],
      ],
    );
  }

  // ── STEP 3: Auto-polling + reconnect instructions ──
  Widget _buildSearching({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          icon: Icons.search_rounded,
          title: 'Presque terminé !',
          subtitle: 'L\'AdhanBox rejoint votre réseau…',
        ),
        const SizedBox(height: 20),

        _InstructionCard(
          icon: Icons.wifi_rounded,
          iconColor: AppTheme.gold,
          title: 'Reconnectez votre téléphone',
          steps: [
            'L\'AdhanBox se connecte à "${_selectedHomeWifi ?? 'votre WiFi'}"',
            'Reconnectez votre téléphone au même réseau',
            'La détection est automatique — aucun bouton à appuyer',
          ],
          action: OutlinedButton.icon(
            onPressed: _openWiFiSettings,
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: const Text('Ouvrir paramètres WiFi'),
          ),
        ),
        const SizedBox(height: 16),

        if (_isBusy)
          _LoadingCard(
            icon: Icons.devices_rounded,
            title: 'Recherche de l\'AdhanBox…',
            subtitle: _progressText.isNotEmpty ? _progressText : 'Connexion en cours',
            pulseController: _pulseController,
          )
        else if (_showManualEntry)
          _ThemedCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.edit_rounded, color: AppTheme.fajrColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Adresse IP manuelle',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 8),
                  Text('Trouvez l\'IP dans la liste des appareils de votre box internet.',
                      style: Theme.of(context).textTheme.bodySmall),
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() { _showManualEntry = false; _error = null; });
                            _startHomePolling();
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Relancer'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _testManualIp,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Tester'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── DONE ──
  Widget _buildDone({Key? key}) {
    return Column(
      key: key,
      children: [
        const SizedBox(height: 20),
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(color: AppTheme.emerald.withOpacity(0.12), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 54),
        ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
        const SizedBox(height: 24),
        Text('Configuration réussie !', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center)
            .animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 8),
        Text('Connecté · $_deviceIp', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center)
            .animate().fadeIn(delay: 300.ms),
        const SizedBox(height: 24),

        _ThemedCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.edit_rounded, color: AppTheme.emerald, size: 20),
                  const SizedBox(width: 10),
                  Text('Nom de l\'appareil', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(hintText: 'ex: AdhanBox Salon', prefixIcon: Icon(Icons.label_rounded)),
                ),
              ],
            ),
          ),
        ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.08),
        const SizedBox(height: 24),

        _ThemedCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.auto_awesome_rounded, color: AppTheme.gold, size: 20),
                  const SizedBox(width: 10),
                  Text('Prochaines étapes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 16),
                _NextStepItem(icon: Icons.mosque_rounded,    color: AppTheme.emerald,   label: 'Configurer votre mosquée Mawaqit'),
                const SizedBox(height: 10),
                _NextStepItem(icon: Icons.calculate_rounded, color: AppTheme.fajrColor, label: 'Choisir la méthode de calcul'),
                const SizedBox(height: 10),
                _NextStepItem(icon: Icons.volume_up_rounded, color: AppTheme.asrColor,  label: 'Ajuster le volume de l\'adhan'),
                const SizedBox(height: 10),
                _NextStepItem(icon: Icons.light_rounded,     color: AppTheme.gold,      label: 'Personnaliser l\'éclairage LED'),
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
              if (mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.home_rounded, size: 18),
            label: const Text('Revenir à l\'accueil'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ).animate().fadeIn(delay: 500.ms),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════
//  HELPER WIDGETS
// ══════════════════════════════════════════════════════

class _StepMeta {
  final IconData icon;
  final String label;
  const _StepMeta({required this.icon, required this.label});
}

// ── Header ──
class _SetupHeader extends StatelessWidget {
  final _Phase phase;
  const _SetupHeader({required this.phase});

  static const _titles = {
    _Phase.detecting:  'Recherche…',
    _Phase.bleScan:    'Bluetooth',
    _Phase.bleWifi:    'Votre WiFi',
    _Phase.connectAP:  'Connexion AP',
    _Phase.homeWifi:   'Votre WiFi',
    _Phase.searching:  'Synchronisation',
    _Phase.done:       'Terminé !',
  };
  static const _subtitles = {
    _Phase.detecting:  'Vérification du réseau local',
    _Phase.bleScan:    'Sélectionnez votre AdhanBox',
    _Phase.bleWifi:    'Réseau domestique',
    _Phase.connectAP:  'Liaison avec l\'AdhanBox',
    _Phase.homeWifi:   'Réseau domestique',
    _Phase.searching:  'Localisation sur le réseau',
    _Phase.done:       'Tout est prêt',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF064E3B), Color(0xFF065F46), Color(0xFF059669)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GeomPainter())),
          Positioned(
            bottom: 24, left: 20, right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titles[phase] ?? '',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitles[phase] ?? '',
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

// ── Step Indicator ──
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
          final done = current > (i ~/ 2) + 1;
          return Expanded(
            child: Container(
              height: 2, margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: done ? AppTheme.emerald : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }
        final stepNum = i ~/ 2 + 1;
        final isActive = current >= stepNum;
        final isCurrent = current == stepNum;
        final meta = steps[i ~/ 2];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isCurrent ? 40 : 32, height: isCurrent ? 40 : 32,
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
            Text(meta.label, style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: isActive
                  ? (isCurrent ? AppTheme.emerald : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))
                  : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
            )),
          ],
        );
      }),
    );
  }
}

// ── Step Title ──
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
        Row(children: [
          Icon(icon, color: AppTheme.emerald, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

// ── Themed Card ──
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

// ── Loading Card ──
class _LoadingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final AnimationController pulseController;
  const _LoadingCard({super.key, required this.icon, required this.title, required this.subtitle, required this.pulseController});

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
              builder: (_, child) => Opacity(opacity: 0.5 + 0.5 * pulseController.value, child: child),
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: AppTheme.emerald.withOpacity(0.12), shape: BoxShape.circle),
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

// ── Empty State Card ──
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
              width: 72, height: 72,
              decoration: BoxDecoration(color: AppTheme.gold.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, color: AppTheme.gold, size: 36),
            ),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            if (actions.isNotEmpty) ...[const SizedBox(height: 24), ...actions],
          ],
        ),
      ),
    );
  }
}

// ── Instruction Card ──
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
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: iconColor.withOpacity(0.12), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 16),
            ...steps.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(color: AppTheme.emerald.withOpacity(0.1), shape: BoxShape.circle),
                    child: Center(child: Text('${e.key + 1}', style: GoogleFonts.inter(color: AppTheme.emerald, fontSize: 12, fontWeight: FontWeight.w700))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(e.value, style: Theme.of(context).textTheme.bodyMedium))),
                ],
              ),
            )),
            if (action != null) ...[const SizedBox(height: 8), SizedBox(width: double.infinity, child: action)],
          ],
        ),
      ),
    );
  }
}

// ── WiFi Network Tile ──
class _WifiNetworkTile extends StatelessWidget {
  final String ssid;
  final int rssi;
  final bool isSelected;
  final bool isCurrent;
  final VoidCallback onTap;
  const _WifiNetworkTile({
    required this.ssid,
    required this.rssi,
    required this.isSelected,
    required this.onTap,
    this.isCurrent = false,
  });

  int get _strength {
    if (rssi >= -50) return 100;
    if (rssi <= -100) return 0;
    return ((rssi + 100) * 2).clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      dense: true,
      leading: _SignalIcon(strength: _strength),
      title: Row(
        children: [
          Flexible(
            child: Text(
              ssid,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.emerald.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.4)),
              ),
              child: Text(
                'connecté',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: AppTheme.emerald,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '$rssi dBm · $_strength%',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded,
              color: AppTheme.emerald, size: 22)
          : Icon(Icons.radio_button_unchecked_rounded,
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              size: 22),
      onTap: onTap,
    );
  }
}

// ── Signal Icon ──
class _SignalIcon extends StatelessWidget {
  final int strength;
  const _SignalIcon({required this.strength});

  @override
  Widget build(BuildContext context) {
    final color = strength >= 75 ? AppTheme.emerald : (strength >= 40 ? AppTheme.gold : Colors.red);
    final icon = strength >= 75
        ? Icons.signal_wifi_4_bar_rounded
        : (strength >= 40 ? Icons.network_wifi_3_bar_rounded : Icons.signal_wifi_0_bar_rounded);
    return Icon(icon, color: color, size: 20);
  }
}

// ── Error Banner ──
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
            GestureDetector(onTap: onDismiss, child: const Icon(Icons.close_rounded, color: Colors.red, size: 16)),
        ],
      ),
    );
  }
}

// ── Action Button ──
class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isPrimary;
  const _ActionBtn({required this.label, required this.icon, required this.onPressed, this.isPrimary = true});

  @override
  Widget build(BuildContext context) {
    if (isPrimary) return ElevatedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label));
    return OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label));
  }
}

// ── Next Step Item ──
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
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}

// ── Geometric Pattern ──
class _GeomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.04)..style = PaintingStyle.stroke..strokeWidth = 1;
    for (double x = 0; x < size.width + 50; x += 50) {
      for (double y = 0; y < size.height + 50; y += 50) {
        canvas.drawCircle(Offset(x, y), 18, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─── BLE Tutorial Banner ──────────────────────────────────────────────────────

class _BleTutorialBanner extends StatefulWidget {
  const _BleTutorialBanner();

  @override
  State<_BleTutorialBanner> createState() => _BleTutorialBannerState();
}

class _BleTutorialBannerState extends State<_BleTutorialBanner>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  late AnimationController _blinkCtrl;

  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = const Color(0xFF3B82F6).withOpacity(0.35);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header tap to expand/collapse
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lightbulb_rounded,
                          color: Color(0xFF3B82F6), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Comment configurer l\'AdhanBox ?',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.lightTextPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: isDark
                          ? AppTheme.darkTextMuted
                          : AppTheme.lightTextMuted,
                    ),
                  ],
                ),
              ),
            ),

            // Expandable content
            if (_expanded) ...[
              Divider(
                height: 1,
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  children: [
                    _BannerTip(
                      number: '1',
                      color: const Color(0xFFEF4444),
                      title: 'Redémarrez l\'AdhanBox',
                      desc: 'Débranchez puis rebranchez votre appareil pour activer le mode Bluetooth.',
                      trailing: AnimatedBuilder(
                        animation: _blinkCtrl,
                        builder: (_, __) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (i) {
                            final delay = i * 0.33;
                            final v = (_blinkCtrl.value - delay).clamp(0.0, 1.0);
                            return Container(
                              margin: const EdgeInsets.only(right: 3),
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color.fromARGB(
                                  (v * 255).round(),
                                  239, 68, 68,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _BannerTip(
                      number: '2',
                      color: const Color(0xFFEF4444),
                      title: 'LEDs rouges clignotantes',
                      desc: 'Le clignotement rouge signifie que l\'AdhanBox est en mode configuration Bluetooth. Il reste actif jusqu\'à la fin de la configuration.',
                      trailing: null,
                    ),
                    const SizedBox(height: 10),
                    _BannerTip(
                      number: '3',
                      color: const Color(0xFF3B82F6),
                      title: 'Sélectionnez votre appareil',
                      desc: 'Votre AdhanBox apparaît ci-dessous sous le nom "AdhanBox-XXXXXX". Appuyez dessus pour vous connecter.',
                      trailing: null,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.gold.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.touch_app_rounded,
                              color: AppTheme.gold, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Appuyez brièvement sur le bouton tactile pour quitter le mode Bluetooth, ou il s\'arrête seul après 5 min sans connexion.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BannerTip extends StatelessWidget {
  final String number;
  final Color color;
  final String title;
  final String desc;
  final Widget? trailing;

  const _BannerTip({
    required this.number,
    required this.color,
    required this.title,
    required this.desc,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Manual SSID Row (always visible in WiFi card, bottom section) ─────────────

class _ManualSsidRow extends StatefulWidget {
  final String? currentSsid;
  final String? selectedSsid;
  final ValueChanged<String> onSelect;
  final bool autoExpand;
  const _ManualSsidRow({
    required this.currentSsid,
    required this.selectedSsid,
    required this.onSelect,
    this.autoExpand = false,
  });

  @override
  State<_ManualSsidRow> createState() => _ManualSsidRowState();
}

class _ManualSsidRowState extends State<_ManualSsidRow> {
  late bool _expanded;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _expanded = widget.autoExpand;
    // Pré-remplir avec le SSID actuel si disponible
    _ctrl = TextEditingController(text: widget.currentSsid ?? '');
    // Notifier le parent si on a un SSID par défaut
    if (widget.autoExpand && (widget.currentSsid?.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onSelect(widget.currentSsid!);
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ligne cliquable — label contextuel selon le mode
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Icon(
                  widget.autoExpand
                      ? Icons.edit_rounded
                      : Icons.add_circle_outline_rounded,
                  size: 16,
                  color: widget.autoExpand
                      ? AppTheme.emerald
                      : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.autoExpand
                      ? 'Nom de votre réseau WiFi'
                      : 'Saisir un autre réseau (réseau caché)',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: widget.autoExpand ? FontWeight.w600 : FontWeight.normal,
                    color: widget.autoExpand
                        ? (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)
                        : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) {
                        widget.onSelect(v.trim());
                        setState(() => _expanded = false);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Nom du réseau (SSID)',
                      prefixIcon: const Icon(Icons.wifi_rounded,
                          color: AppTheme.emerald, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final v = _ctrl.text.trim();
                    if (v.isNotEmpty) {
                      widget.onSelect(v);
                      setState(() => _expanded = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── iOS Manual SSID Field ──────────────────────────────────────────────────────

class _IosManualSsidField extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;
  const _IosManualSsidField({required this.initialValue, required this.onChanged});

  @override
  State<_IosManualSsidField> createState() => _IosManualSsidFieldState();
}

class _IosManualSsidFieldState extends State<_IosManualSsidField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
    // Notify parent of the initial value
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onChanged(_ctrl.text.trim());
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      onChanged: (v) => widget.onChanged(v.trim()),
      decoration: InputDecoration(
        hintText: 'Nom du réseau WiFi (SSID)',
        prefixIcon: const Icon(Icons.wifi_rounded, color: AppTheme.emerald),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
