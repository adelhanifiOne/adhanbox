import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../providers/adhanbox_provider.dart';
import '../services/location_service.dart';
import '../services/wifi_service.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import 'privacy_policy_screen.dart';
import 'device_setup_screen.dart';
import 'audio_content_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _timezone = DateTime.now().timeZoneOffset.inMinutes ~/ 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTimezone());
  }

  Future<void> _loadTimezone() async {
    final api = ref.read(adhanboxApiProvider);
    if (api == null) return;
    try {
      final data = await api.getTimezone();
      if (mounted) {
        setState(() => _timezone = ((data['tz_min'] as num?) ?? 0).toInt() ~/ 60);
      }
    } catch (_) {}
  }

  // ── Sync time & location automatically (Simple 1-tap action for technophobes) ──
  Future<void> _syncTimeAndLocation() async {
    final api = ref.read(adhanboxApiProvider);
    if (api == null) {
      _showError("L'AdhanBox n'est pas connecté. Veuillez le configurer.");
      return;
    }

    _showLoading("Mise à jour en cours…");

    try {
      // 1. Sync time
      await api.setRtcTime(DateTime.now());

      // 2. Sync Timezone
      final tzOffsetMin = DateTime.now().timeZoneOffset.inMinutes;
      await api.setTimezone(tzOffsetMin);

      // 3. Sync Location (optional, try to get phone GPS)
      String locMsg = "";
      try {
        final locService = ref.read(locationServiceProvider);
        final pos = await locService.getCurrentLocation();
        if (pos != null) {
          await api.setLocation(pos.latitude, pos.longitude, pos.accuracy);
          locMsg = "\nLocalisation géographique mise à jour.";
        }
      } catch (_) {
        locMsg = "\n(Heure synchronisée, GPS ignoré)";
      }

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        _showSuccess("Mise à jour réussie !$locMsg");
        _loadTimezone(); // Refresh timezone display
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showError("Impossible de synchroniser : $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);
    final deviceIp = ref.watch(currentDeviceIpProvider) ?? '';
    final api = ref.read(adhanboxApiProvider);
    final localVersionAsync = ref.watch(deviceFirmwareVersionProvider);
    final latestVersionAsync = ref.watch(latestFirmwareVersionProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text('Réglages', style: Theme.of(context).appBarTheme.titleTextStyle),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── ÉTAT DE L'APPAREIL ──
                _SectionHeader('Mon AdhanBox'),
                _SettingsCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.emerald.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.router_rounded, color: AppTheme.emerald, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  deviceIp.isEmpty ? 'Non connecté' : 'AdhanBox connecté',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  deviceIp.isEmpty 
                                      ? 'Associez votre appareil pour commencer.' 
                                      : 'Fonctionne correctement sur votre réseau.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          _StatusBadge(isConnected: deviceIp.isNotEmpty),
                        ],
                      ),
                    ),
                    if (deviceIp.isNotEmpty) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _FirmwareUpdateTile(
                        localVersionAsync: localVersionAsync,
                        latestVersionAsync: latestVersionAsync,
                        onUpdatePressed: (latestVersion, url) => _runFirmwareUpdate(latestVersion, url),
                      ),
                    ],
                  ],
                ).animate().fadeIn(delay: 50.ms).slideY(begin: 0.06),

                const SizedBox(height: 20),

                // ── ACTIONS SIMPLIFIÉES ──
                _SectionHeader('Réglages Automatiques'),
                _ThemedClickableCard(
                  onTap: _syncTimeAndLocation,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 46, height: 46,
                          decoration: BoxDecoration(
                            color: AppTheme.gold.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.auto_fix_high_rounded, color: AppTheme.gold, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Mettre à jour l'AdhanBox",
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Règle l'heure et les horaires de prière en fonction de votre téléphone. Simple et rapide.",
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppTheme.emerald),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.06),

                const SizedBox(height: 20),

                // ── CONNEXION & WIFI ──
                _SectionHeader('Connexion & WiFi'),
                _SettingsCard(
                  children: [
                    _ActionTile(
                      icon: Icons.wifi_rounded,
                      iconColor: Colors.blue,
                      title: 'Changer le réseau WiFi',
                      subtitle: "Connecter l'appareil à une autre box internet",
                      onTap: _showWiFiPicker,
                    ),
                    _CardDivider(),
                    _ActionTile(
                      icon: Icons.add_rounded,
                      iconColor: AppTheme.emeraldDark,
                      title: 'Associer un autre appareil',
                      subtitle: "Configurer un nouvel AdhanBox",
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.06),

                const SizedBox(height: 20),

                // ── AUDIO & RÉCITATIONS (toujours visible) ──
                ...[
                  _SectionHeader('Audio & Récitations'),
                  _SettingsCard(
                    children: [
                      _ActionTile(
                        icon: Icons.library_music_rounded,
                        iconColor: Colors.blue,
                        title: 'Contenu audio',
                        subtitle: 'Synchroniser et voir les fichiers de la SD',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const AudioContentScreen()),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 220.ms).slideY(begin: 0.06),
                  const SizedBox(height: 20),
                ],

                // ── APPARENCE & THÈME ──
                _SectionHeader('Préférences'),
                _SettingsCard(
                  children: [
                    _ToggleTile(
                      icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      iconColor: isDark ? AppTheme.fajrColor : AppTheme.gold,
                      title: 'Mode Sombre',
                      subtitle: isDark ? 'Affichage sombre' : 'Affichage clair',
                      trailing: Switch(
                        value: themeMode == ThemeMode.dark,
                        activeColor: AppTheme.emerald,
                        onChanged: (v) {
                          ref.read(themeModeProvider.notifier).state =
                              v ? ThemeMode.dark : ThemeMode.light;
                        },
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.06),

                const SizedBox(height: 20),

                // ── SOUTENIR ADHANBOX ──
                _SectionHeader('Soutenir AdhanBox'),
                _SettingsCard(
                  children: [
                    _ActionTile(
                      icon: Icons.star_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      title: 'Laisser un avis',
                      subtitle: 'Notez l\'application sur le store',
                      onTap: _leaveReview,
                    ),
                    _CardDivider(),
                    _ActionTile(
                      icon: Icons.favorite_rounded,
                      iconColor: const Color(0xFFEC4899),
                      title: 'Soutenir le développeur',
                      subtitle: 'Offrez-moi un café ☕',
                      onTap: () => _launchExternal('https://buymeacoffee.com/overlayprayers'),
                    ),
                    _CardDivider(),
                    _ActionTile(
                      icon: Icons.shopping_bag_rounded,
                      iconColor: AppTheme.emerald,
                      title: 'Commander un AdhanBox',
                      subtitle: 'Découvrez nos offres',
                      onTap: () => _launchExternal('https://adelhanifione.github.io/adhanbox/#offres'),
                    ),
                  ],
                ).animate().fadeIn(delay: 280.ms).slideY(begin: 0.06),

                // ── ASSISTANCE ──
                _SectionHeader('Assistance'),
                _SettingsCard(
                  children: [
                    _ActionTile(
                      icon: Icons.privacy_tip_outlined,
                      iconColor: AppTheme.darkTextMuted,
                      title: 'Politique de confidentialité',
                      subtitle: 'Comment vos données sont protégées',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.06),

                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'AdhanBox · Version 1.0.0',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchExternal(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) _showError('Impossible d\'ouvrir le lien.');
    }
  }

  Future<void> _leaveReview() async {
    // Ouvre la fiche du store correspondant à la plateforme.
    // iOS : remplacer id000000000 par l'identifiant App Store une fois connu.
    final url = Platform.isIOS
        ? 'https://apps.apple.com/app/id0000000000?action=write-review'
        : 'https://play.google.com/store/apps/details?id=com.adhanbox.app';
    await _launchExternal(url);
  }

  Future<void> _showWiFiPicker() async {
    _showLoading('Recherche des réseaux WiFi…');
    try {
      final service = ref.read(wifiServiceProvider);
      final networks = await service.scanNetworks();
      if (!mounted) return;
      Navigator.pop(context);
      if (networks.isEmpty) { _showError('Aucun réseau trouvé.'); return; }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, controller) => Column(
            children: [
              const SizedBox(height: 8),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.darkBorder, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('Sélectionnez votre réseau', style: Theme.of(context).textTheme.titleLarge),
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
                      title: Text(n.ssid, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Signal de connexion : $strength%'),
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
      _showError('Erreur WiFi : $e');
    }
  }

  void _showPasswordDialog(String ssid) {
    final pwdCtrl = TextEditingController();
    bool obscurePwd = true;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Rejoindre $ssid',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: TextField(
            controller: pwdCtrl,
            obscureText: obscurePwd,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Mot de passe WiFi',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                icon: Icon(obscurePwd ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setDialogState(() => obscurePwd = !obscurePwd),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final api = ref.read(adhanboxApiProvider);
                if (api != null) {
                  try {
                    await api.connectWiFi(ssid, pwdCtrl.text);
                    _showSuccess('Configuration WiFi envoyée avec succès');
                  } catch (e) {
                    _showError('Erreur : $e');
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emerald),
              child: const Text('Connecter'),
            ),
          ],
        ),
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
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)), 
        backgroundColor: AppTheme.emerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)), 
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _runFirmwareUpdate(String latestVersion, String url) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Mise à jour v$latestVersion'),
        content: Text(
          'Voulez-vous télécharger et installer la version $latestVersion sur votre AdhanBox ?\n\n'
          'Ne débranchez pas le boîtier pendant l\'opération. L\'appareil redémarrera automatiquement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emerald),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Démarrer'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    _showLoading('Téléchargement du logiciel…');
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw Exception('Impossible de télécharger le fichier (HTTP ${res.statusCode})');
      }
      final bytes = res.bodyBytes;

      if (!mounted) return;
      Navigator.pop(context); // Close download dialog

      _showLoading('Installation sur l\'AdhanBox (1 à 2 minutes)…');

      final api = ref.read(adhanboxApiProvider);
      if (api == null) throw Exception('Appareil déconnecté');
      
      await api.uploadFirmware(bytes);

      if (mounted) {
        Navigator.pop(context); // Close install loading dialog
        _showSuccess('Mise à jour réussie ! Votre AdhanBox redémarre.');
        ref.invalidate(deviceFirmwareVersionProvider);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        _showError('Échec de la mise à jour : $e');
      }
    }
  }
}

// ─── UI COMPONENTS ───

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
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

class _ThemedClickableCard extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _ThemedClickableCard({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: child,
        ),
      ),
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
              width: 40, height: 40,
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
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
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
            width: 40, height: 40,
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
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
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
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      indent: 16,
      color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isConnected;
  const _StatusBadge({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    final color = isConnected ? AppTheme.emerald : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'Actif' : 'Inactif',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _FirmwareUpdateTile extends ConsumerWidget {
  final AsyncValue<Map<String, dynamic>> localVersionAsync;
  final AsyncValue<Map<String, dynamic>> latestVersionAsync;
  final Function(String version, String url) onUpdatePressed;

  const _FirmwareUpdateTile({
    required this.localVersionAsync,
    required this.latestVersionAsync,
    required this.onUpdatePressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return localVersionAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald),
            ),
            SizedBox(width: 12),
            Text('Vérification du logiciel...', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Impossible de lire la version : $err',
                style: const TextStyle(fontSize: 13, color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
      data: (localData) {
        final currentVer = localData['version']?.toString() ?? '1.0.0';
        final isLegacy = localData['isLegacy'] == true;
        final displayVer = isLegacy ? 'Ancienne version' : 'v$currentVer';
        
        return latestVersionAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Logiciel : $displayVer', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.emerald),
                ),
              ],
            ),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Logiciel : $displayVer', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text(
                  'Mise à jour indisponible',
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[600] : Colors.grey[400]),
                ),
              ],
            ),
          ),
          data: (latestData) {
            final latestVer = latestData['version']?.toString() ?? '1.0.0';
            final updateUrl = latestData['url']?.toString() ?? '';
            
            final hasUpdate = _isNewerVersion(currentVer, latestVer);
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Logiciel : $displayVer',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      if (hasUpdate)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'Mise à jour disponible !',
                            style: TextStyle(fontSize: 11, color: AppTheme.emerald, fontWeight: FontWeight.bold),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'À jour',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                        ),
                    ],
                  ),
                  if (hasUpdate && updateUrl.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: AppTheme.emerald,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => onUpdatePressed(latestVer, updateUrl),
                      icon: const Icon(Icons.system_update_alt_rounded, size: 14),
                      label: Text('Installer v$latestVer', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _isNewerVersion(String current, String latest) {
    try {
      final curParts = current.split('.').map(int.parse).toList();
      final latParts = latest.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final curV = i < curParts.length ? curParts[i] : 0;
        final latV = i < latParts.length ? latParts[i] : 0;
        if (latV > curV) return true;
        if (curV > latV) return false;
      }
    } catch (_) {}
    return false;
  }
}
