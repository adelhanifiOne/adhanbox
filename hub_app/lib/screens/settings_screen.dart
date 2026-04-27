import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final notifier = ref.read(prefsProvider.notifier);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(title: Text('Paramètres'), pinned: true),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 8),

              _Section(title: '🕌 Islam', children: [
                _ChoiceRow(
                  label: 'Madhab',
                  value: prefs.madhab,
                  options: const ['hanafi', 'maliki', 'shafi', 'hanbali'],
                  onChanged: (v) => notifier.update(prefs.copyWith(madhab: v)),
                ),
                _ChoiceRow(
                  label: 'Langue réponses',
                  value: prefs.language,
                  options: const ['fr', 'ar', 'en'],
                  onChanged: (v) => notifier.update(prefs.copyWith(language: v)),
                ),
                _ChoiceRow(
                  label: 'Méthode calcul',
                  value: prefs.calculationMethod,
                  options: const ['MWL', 'ISNA', 'Egypt', 'Makkah', 'Karachi'],
                  onChanged: (v) => notifier.update(prefs.copyWith(calculationMethod: v)),
                ),
              ]),

              _Section(title: '🔔 Azkar automatiques', children: [
                _SwitchRow(
                  label: 'Azkar al-sabah (après Fajr)',
                  value: prefs.azkarMorningEnabled,
                  onChanged: (v) => notifier.update(prefs.copyWith(azkarMorningEnabled: v)),
                ),
                _SwitchRow(
                  label: 'Azkar al-masa (après Asr)',
                  value: prefs.azkarEveningEnabled,
                  onChanged: (v) => notifier.update(prefs.copyWith(azkarEveningEnabled: v)),
                ),
                _SwitchRow(
                  label: 'Azkar après prière',
                  value: prefs.azkarAfterPrayerEnabled,
                  onChanged: (v) => notifier.update(prefs.copyWith(azkarAfterPrayerEnabled: v)),
                ),
              ]),

              _Section(title: '🌐 Connexion Hub', children: [
                _TextFieldRow(
                  label: 'IP du Hub (RPi5)',
                  value: prefs.hubIp,
                  hint: 'http://192.168.1.100:8000',
                  onSaved: (v) => notifier.update(prefs.copyWith(hubIp: v)),
                ),
                _HubStatusRow(ref: ref),
              ]),

              _Section(title: '🎨 Affichage', children: [
                _SwitchRow(
                  label: 'Mode sombre',
                  value: prefs.darkMode,
                  onChanged: (v) => notifier.update(prefs.copyWith(darkMode: v)),
                ),
              ]),

              const SizedBox(height: 30),
              Center(child: Text('Islamic Hub v1.0.0',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted))),
              const SizedBox(height: 16),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(title, style: GoogleFonts.poppins(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.bgCard, borderRadius: BorderRadius.circular(14)),
        child: Column(children: children.asMap().entries.map((e) => Column(children: [
          e.value,
          if (e.key < children.length - 1)
            const Divider(height: 1, color: AppColors.bgCardLight, indent: 16),
        ])).toList()),
      ),
    ],
  );
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    title: Text(label, style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
    trailing: Switch(value: value, onChanged: onChanged,
      activeColor: AppColors.emerald),
  );
}

class _ChoiceRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _ChoiceRow({required this.label, required this.value,
    required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    title: Text(label, style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
    trailing: DropdownButton<String>(
      value: value,
      dropdownColor: AppColors.bgCard,
      underline: const SizedBox.shrink(),
      style: GoogleFonts.inter(fontSize: 13, color: AppColors.gold),
      items: options.map((o) => DropdownMenuItem(value: o,
        child: Text(o, style: GoogleFonts.inter(color: Colors.white)))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    ),
  );
}

class _TextFieldRow extends StatefulWidget {
  final String label;
  final String value;
  final String hint;
  final ValueChanged<String> onSaved;
  const _TextFieldRow({required this.label, required this.value,
    required this.hint, required this.onSaved});

  @override
  State<_TextFieldRow> createState() => _TextFieldRowState();
}

class _TextFieldRowState extends State<_TextFieldRow> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
      const SizedBox(height: 6),
      TextField(
        controller: _ctrl,
        style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
          filled: true,
          fillColor: AppColors.bgCardLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          suffixIcon: IconButton(
            icon: const Icon(Icons.check_rounded, color: AppColors.emerald, size: 18),
            onPressed: () => widget.onSaved(_ctrl.text.trim()),
          ),
        ),
        onSubmitted: widget.onSaved,
      ),
    ]),
  );
}

class _HubStatusRow extends StatelessWidget {
  final WidgetRef ref;
  const _HubStatusRow({required this.ref});

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(hubConnectedProvider);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text('Statut', style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
      trailing: status.when(
        loading: () => const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)),
        data: (ok) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(
            color: ok ? AppColors.emerald : Colors.red, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(ok ? 'Connecté' : 'Hors ligne',
            style: GoogleFonts.inter(fontSize: 12,
              color: ok ? AppColors.emerald : Colors.red)),
        ]),
        error: (_, __) => const Text('Erreur',
          style: TextStyle(color: Colors.red, fontSize: 12)),
      ),
      onTap: () => ref.invalidate(hubConnectedProvider),
    );
  }
}
