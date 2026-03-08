import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/adhanbox_provider.dart';
import '../services/location_service.dart';
import '../services/wifi_service.dart';
import '../services/esp32_discovery_service.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import 'adhan_config_screen.dart';
import 'calculation_setup_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _ipController;
  double _volume = 20;
  int _timezone = 1;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final api = ref.read(adhanboxApiProvider);
    if (api != null) {
      try {
        final vol = await api.getAudioVolume();
        if (mounted) setState(() { _volume = vol.toDouble(); _isLoading = false; });
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceIp = ref.watch(currentDeviceIpProvider) ?? '';
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _ipController.text = deviceIp;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text('Réglages', style: Theme.of(context).appBarTheme.titleTextStyle),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppTheme.emerald)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Apparence ──
                  _SectionHeader(label: 'Apparence'),
                  _SettingsCard(children: [
                    _ToggleTile(
                      icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      iconColor: isDark ? AppTheme.fajrColor : AppTheme.gold,
                      title: 'Thème',
                      subtitle: isDark ? 'Mode sombre' : 'Mode clair',
                      trailing: Switch(
                        value: themeMode == ThemeMode.dark,
                        onChanged: (v) {
                          ref.read(themeModeProvider.notifier).state =
                              v ? ThemeMode.dark : ThemeMode.light;
                        },
                      ),
                    ),
                  ]).animate().fadeIn(delay: 50.ms).slideY(begin: 0.06),

                  const SizedBox(height: 24),

                  // ── Connexion ──
                  _SectionHeader(label: 'Connexion'),
                  _SettingsCard(children: [
                    _ActionTile(
                      icon: Icons.search_rounded,
                      iconColor: AppTheme.emerald,
                      title: 'Détecter automatiquement',
                      subtitle: 'Rechercher l\'AdhanBox sur le réseau',
                      onTap: _discoverDevice,
                    ),
                    const _CardDivider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ipController,
                              decoration: const InputDecoration(
                                labelText: 'Adresse IP',
                                hintText: '192.168.1.x',
                                prefixIcon: Icon(Icons.router_rounded),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () async {
                              ref.read(currentDeviceIpProvider.notifier).state = _ipController.text;
                              await saveDeviceIp(ref, _ipController.text);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('IP sauvegardée'), backgroundColor: AppTheme.emerald),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            ),
                            child: const Icon(Icons.check_rounded),
                          ),
                        ],
                      ),
                    ),
                  ]).animate().fadeIn(delay: 100.ms).slideY(begin: 0.06),

                  const SizedBox(height: 24),

                  // ── Audio ──
                  _SectionHeader(label: 'Audio'),
                  _SettingsCard(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Icon(Icons.volume_up_rounded, color: AppTheme.asrColor, size: 20),
                            const SizedBox(width: 10),
                            Text('Volume', style: Theme.of(context).textTheme.titleMedium),
                          ]),
                          Text(
                            '${_volume.toInt()} / 30',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.emerald),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Slider(
                        value: _volume,
                        min: 0,
                        max: 30,
                        divisions: 30,
                        onChanged: (v) async {
                          setState(() => _volume = v);
                          final api = ref.read(adhanboxApiProvider);
                          if (api != null) await api.setAudioVolume(v.toInt());
                        },
                      ),
                    ),
                    const _CardDivider(),
                    _ActionTile(
                      icon: Icons.music_note_rounded,
                      iconColor: AppTheme.fajrColor,
                      title: 'Configurer les adhans',
                      subtitle: 'Choisir l\'appel à la prière par prière',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AdhanConfigScreen()),
                      ),
                    ),
                  ]).animate().fadeIn(delay: 150.ms).slideY(begin: 0.06),

                  const SizedBox(height: 24),

                  // ── Localisation & Calcul ──
                  _SectionHeader(label: 'Prières'),
                  _SettingsCard(children: [
                    _ActionTile(
                      icon: Icons.my_location_rounded,
                      iconColor: AppTheme.emerald,
                      title: 'Ma position GPS',
                      subtitle: 'Envoyer la localisation à l\'appareil',
                      onTap: _sendGPSLocation,
                    ),
                    const _CardDivider(),
                    _ActionTile(
                      icon: Icons.calculate_rounded,
                      iconColor: AppTheme.ishaColor,
                      title: 'Méthode de calcul',
                      subtitle: 'MWL, UOIF, ISNA et autres',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CalculationSetupScreen()),
                      ),
                    ),
                  ]).animate().fadeIn(delay: 200.ms).slideY(begin: 0.06),

                  const SizedBox(height: 24),

                  // ── WiFi ──
                  _SectionHeader(label: 'WiFi'),
                  _SettingsCard(children: [
                    _ActionTile(
                      icon: Icons.wifi_rounded,
                      iconColor: Colors.blue,
                      title: 'Changer le réseau WiFi',
                      subtitle: 'Connecter l\'appareil à un autre réseau',
                      onTap: _showWiFiPicker,
                    ),
                  ]).animate().fadeIn(delay: 250.ms).slideY(begin: 0.06),

                  const SizedBox(height: 24),

                  // ── Heure ──
                  _SectionHeader(label: 'Heure'),
                  _SettingsCard(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            const Icon(Icons.schedule_rounded, color: AppTheme.gold, size: 20),
                            const SizedBox(width: 10),
                            Text('Fuseau horaire', style: Theme.of(context).textTheme.titleMedium),
                          ]),
                          Text(
                            'UTC ${_timezone >= 0 ? '+' : ''}$_timezone',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.emerald),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Slider(
                        value: _timezone.toDouble(),
                        min: -12,
                        max: 14,
                        divisions: 26,
                        onChanged: (v) async {
                          setState(() => _timezone = v.toInt());
                          final api = ref.read(adhanboxApiProvider);
                          if (api != null) await api.setTimezone(_timezone * 60);
                        },
                      ),
                    ),
                    const _CardDivider(),
                    _ActionTile(
                      icon: Icons.sync_rounded,
                      iconColor: AppTheme.emerald,
                      title: 'Synchroniser l\'heure',
                      subtitle: 'Envoyer l\'heure actuelle du téléphone',
                      onTap: () async {
                        final api = ref.read(adhanboxApiProvider);
                        if (api != null) {
                          try {
                            await api.setRtcTime(DateTime.now());
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Heure synchronisée'), backgroundColor: AppTheme.emerald),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erreur: $e')),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ]).animate().fadeIn(delay: 300.ms).slideY(begin: 0.06),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _discoverDevice() async {
    _showLoading('Recherche de l\'AdhanBox...');
    try {
      final service = ref.read(esp32DiscoveryServiceProvider);
      final device = await service.findAdhanBox(timeout: const Duration(seconds: 6));

      if (!mounted) return;
      Navigator.pop(context);

      if (device != null) {
        ref.read(currentDeviceIpProvider.notifier).state = device.host;
        await saveDeviceIp(ref, device.host);
        _ipController.text = device.host;
        _showSuccess('AdhanBox trouvé : ${device.host}');
        return;
      }

      final subnet = await service.getLocalSubnet();
      if (subnet == null) { _showError('Sous-réseau introuvable'); return; }
      final hosts = await service.scanLocalNetwork(subnet: subnet);
      if (!mounted) return;

      if (hosts.isEmpty) {
        _showError('Aucun appareil trouvé');
        return;
      }
      _showDeviceList(hosts);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError('Erreur: $e');
    }
  }

  void _showDeviceList(List<String> hosts) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.7,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.darkBorder, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Appareils trouvés', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: hosts.length,
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.devices_rounded, color: AppTheme.emerald),
                  title: Text(hosts[i]),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () async {
                    ref.read(currentDeviceIpProvider.notifier).state = hosts[i];
                    await saveDeviceIp(ref, hosts[i]);
                    _ipController.text = hosts[i];
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showSuccess('IP configurée : ${hosts[i]}');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendGPSLocation() async {
    _showLoading('Récupération GPS...');
    try {
      final service = ref.read(locationServiceProvider);
      final pos = await service.getCurrentLocation();
      if (!mounted) return;
      Navigator.pop(context);

      if (pos == null) { _showError('GPS indisponible'); return; }

      final api = ref.read(adhanboxApiProvider);
      if (api != null) {
        await api.setLocation(pos.latitude, pos.longitude, pos.accuracy);
        _showSuccess('Position envoyée : ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError('Erreur GPS: $e');
    }
  }

  Future<void> _showWiFiPicker() async {
    _showLoading('Scan WiFi...');
    try {
      final service = ref.read(wifiServiceProvider);
      final networks = await service.scanNetworks();
      if (!mounted) return;
      Navigator.pop(context);

      if (networks.isEmpty) { _showError('Aucun réseau trouvé'); return; }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, controller) => Column(
            children: [
              const SizedBox(height: 8),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.darkBorder, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('Réseaux WiFi', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: networks.length,
                  itemBuilder: (_, i) {
                    final n = networks[i];
                    final strength = service.signalStrengthPercent(n.level);
                    final signalColor = strength >= 75 ? AppTheme.emerald : (strength >= 40 ? AppTheme.gold : Colors.red);
                    return ListTile(
                      leading: Icon(Icons.wifi_rounded, color: signalColor),
                      title: Text(n.ssid),
                      subtitle: Text('Signal $strength%'),
                      trailing: n.capabilities.contains('WPA')
                          ? const Icon(Icons.lock_rounded, size: 16, color: AppTheme.darkTextMuted)
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showPasswordDialog(n.ssid);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError('Erreur WiFi: $e');
    }
  }

  void _showPasswordDialog(String ssid) {
    final pwdCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Connexion à $ssid'),
        content: TextField(
          controller: pwdCtrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Mot de passe',
            prefixIcon: Icon(Icons.key_rounded),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final api = ref.read(adhanboxApiProvider);
              if (api != null) {
                try {
                  await api.connectWiFi(ssid, pwdCtrl.text);
                  _showSuccess('Configuration WiFi envoyée');
                } catch (e) {
                  _showError('Erreur: $e');
                }
              }
            },
            child: const Text('Connecter'),
          ),
        ],
      ),
    );
  }

  void _showLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.emerald),
              const SizedBox(height: 16),
              Text(message, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.emerald),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
  }
}

// ─────────────────────────── UI COMPONENTS ───────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.emerald,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Column(children: children),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
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
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      indent: 70,
      color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
    );
  }
}
