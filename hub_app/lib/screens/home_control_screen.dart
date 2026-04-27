import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

// ── Device model ──────────────────────────────────────────────────────────────

enum DeviceType {
  adhanbox, hub, ledStrip, bulb, speaker, sensorTemp, sensorCo2, sensorMotion, plug
}

enum DeviceStatus { online, offline, comingSoon }

class Device {
  final String id;
  final String name;
  final String room;
  final DeviceType type;
  DeviceStatus status;
  bool isOn;
  double sliderValue;      // brightness, volume, etc.
  Map<String, dynamic> state;

  Device({
    required this.id,
    required this.name,
    required this.room,
    required this.type,
    this.status = DeviceStatus.offline,
    this.isOn = false,
    this.sliderValue = 50,
    Map<String, dynamic>? state,
  }) : state = state ?? {};
}

// ── Provider ──────────────────────────────────────────────────────────────────

class DevicesNotifier extends StateNotifier<List<Device>> {
  DevicesNotifier() : super(_initialDevices());

  static List<Device> _initialDevices() => [
    Device(id: 'rpi5',         name: 'Islamic Hub',      room: 'Serveur',   type: DeviceType.hub,          status: DeviceStatus.offline),
    Device(id: 'adhanbox',     name: 'AdhanBox',         room: 'Salon',     type: DeviceType.adhanbox,     status: DeviceStatus.offline, sliderValue: 50),
    Device(id: 'led_salon',    name: 'LED Salon',        room: 'Salon',     type: DeviceType.ledStrip,     status: DeviceStatus.offline, isOn: true, sliderValue: 70, state: {'scenario': 8}),
    Device(id: 'speaker_main', name: 'Enceinte Salon',   room: 'Salon',     type: DeviceType.speaker,      status: DeviceStatus.comingSoon, sliderValue: 60),
    Device(id: 'bulb_salon1',  name: 'Ampoule Salon',    room: 'Salon',     type: DeviceType.bulb,         status: DeviceStatus.comingSoon, isOn: true, sliderValue: 80),
    Device(id: 'bulb_salon2',  name: 'Ampoule Bureau',   room: 'Bureau',    type: DeviceType.bulb,         status: DeviceStatus.comingSoon, isOn: false, sliderValue: 60),
    Device(id: 'plug_bureau',  name: 'Prise Bureau',     room: 'Bureau',    type: DeviceType.plug,         status: DeviceStatus.comingSoon, isOn: true),
    Device(id: 'sensor_salon', name: 'Temp/Humidité',    room: 'Salon',     type: DeviceType.sensorTemp,   status: DeviceStatus.comingSoon, state: {'temp': 22.3, 'humidity': 48}),
    Device(id: 'sensor_co2',   name: 'Capteur CO₂',      room: 'Chambre',   type: DeviceType.sensorCo2,    status: DeviceStatus.comingSoon, state: {'co2': 650}),
    Device(id: 'sensor_door',  name: 'Détecteur Mouv.',  room: 'Entrée',    type: DeviceType.sensorMotion, status: DeviceStatus.comingSoon, state: {'motion': false}),
    Device(id: 'bulb_chambre', name: 'Ampoule Chambre',  room: 'Chambre',   type: DeviceType.bulb,         status: DeviceStatus.comingSoon, isOn: false, sliderValue: 40),
    Device(id: 'plug_cuisine', name: 'Prise Cuisine',    room: 'Cuisine',   type: DeviceType.plug,         status: DeviceStatus.comingSoon, isOn: false),
  ];

  void setStatus(String id, DeviceStatus status) {
    state = [for (final d in state) d.id == id ? (d..status = status) : d];
  }

  void toggle(String id) {
    state = [for (final d in state) d.id == id ? (d..isOn = !d.isOn) : d];
  }

  void setSlider(String id, double value) {
    state = [for (final d in state) d.id == id ? (d..sliderValue = value) : d];
  }

  void updateState(String id, Map<String, dynamic> newState) {
    state = [for (final d in state) d.id == id ? (d..state = {...d.state, ...newState}) : d];
  }

  List<String> get rooms => state.map((d) => d.room).toSet().toList();
}

final devicesProvider = StateNotifierProvider<DevicesNotifier, List<Device>>(
  (_) => DevicesNotifier(),
);

// ── Screen ────────────────────────────────────────────────────────────────────

class HomeControlScreen extends ConsumerStatefulWidget {
  const HomeControlScreen({super.key});

  @override
  ConsumerState<HomeControlScreen> createState() => _HomeControlScreenState();
}

class _HomeControlScreenState extends ConsumerState<HomeControlScreen> {
  String _selectedRoom = 'Tous';

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final rooms = ['Tous', ...ref.read(devicesProvider.notifier).rooms];

    final filtered = _selectedRoom == 'Tous'
        ? devices
        : devices.where((d) => d.room == _selectedRoom).toList();

    final onlineCount = devices.where((d) => d.status == DeviceStatus.online).length;
    final totalCount = devices.length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── AppBar ──────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0C1A2E), Color(0xFF0F172A)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('Mes appareils',
                          style: GoogleFonts.poppins(fontSize: 22,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 4),
                        Row(children: [
                          _StatusPill(
                            label: '$onlineCount en ligne',
                            color: AppColors.emerald,
                            icon: Icons.wifi_rounded,
                          ),
                          const SizedBox(width: 8),
                          _StatusPill(
                            label: '$totalCount appareils',
                            color: AppColors.gold,
                            icon: Icons.devices_rounded,
                          ),
                        ]),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Filtre par pièce ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: rooms.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _RoomChip(
                  label: rooms[i],
                  selected: _selectedRoom == rooms[i],
                  onTap: () => setState(() => _selectedRoom = rooms[i]),
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ── Grille appareils ────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _DeviceCard(
                  device: filtered[i],
                  index: i,
                ).animate().fadeIn(duration: 300.ms, delay: (i * 50).ms.clamp(0.ms, 350.ms)),
                childCount: filtered.length,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── Scènes islamiques ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ScenesSection(),
            ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),

      // ── FAB ajouter appareil ────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.emerald,
        onPressed: () => _showAddDeviceSheet(context),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('Ajouter', style: GoogleFonts.inter(
          color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showAddDeviceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _AddDeviceSheet(),
    );
  }
}

// ── Device card ───────────────────────────────────────────────────────────────

class _DeviceCard extends ConsumerWidget {
  final Device device;
  final int index;
  const _DeviceCard({required this.device, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = _DeviceConfig.of(device.type);
    final isComingSoon = device.status == DeviceStatus.comingSoon;
    final isOnline = device.status == DeviceStatus.online;

    return GestureDetector(
      onTap: () => _showDeviceDetail(context, ref),
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: device.isOn && isOnline
              ? cfg.color.withValues(alpha: 0.12)
              : AppColors.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: device.isOn && isOnline
                ? cfg.color.withValues(alpha: 0.35)
                : AppColors.bgCardLight,
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isComingSoon
                      ? AppColors.bgCardLight
                      : cfg.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(cfg.icon,
                  color: isComingSoon ? AppColors.textMuted : cfg.color,
                  size: 20),
              ),
              const Spacer(),
              _StatusDot(status: device.status),
            ]),

            const Spacer(),

            // ── Nom + pièce ──────────────────────────────────────────────────
            Text(device.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: isComingSoon ? AppColors.textMuted : Colors.white)),
            Text(device.room,
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),

            const SizedBox(height: 10),

            // ── Contrôle principal ───────────────────────────────────────────
            _DeviceControl(device: device, cfg: cfg),
          ],
        ),
      ),
    );
  }

  void _showDeviceDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _DeviceDetailSheet(device: device, ref: ref),
    );
  }
}

// ── Contrôle inline sur la carte ─────────────────────────────────────────────

class _DeviceControl extends ConsumerWidget {
  final Device device;
  final _DeviceConfig cfg;
  const _DeviceControl({required this.device, required this.cfg});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(devicesProvider.notifier);

    if (device.status == DeviceStatus.comingSoon) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.bgCardLight, borderRadius: BorderRadius.circular(8)),
        child: Text('Bientôt', style: GoogleFonts.inter(
          fontSize: 10, color: AppColors.textMuted)),
      );
    }

    switch (device.type) {
      case DeviceType.adhanbox:
        return _AdhanboxControl(device: device, ref: ref);

      case DeviceType.ledStrip:
      case DeviceType.bulb:
        return Row(children: [
          Expanded(child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: device.sliderValue,
              min: 0, max: 100,
              activeColor: cfg.color,
              inactiveColor: AppColors.bgCardLight,
              onChanged: (v) => notifier.setSlider(device.id, v),
            ),
          )),
          GestureDetector(
            onTap: () => notifier.toggle(device.id),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: device.isOn
                    ? cfg.color.withValues(alpha: 0.2)
                    : AppColors.bgCardLight,
                borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.power_settings_new_rounded,
                color: device.isOn ? cfg.color : AppColors.textMuted,
                size: 16),
            ),
          ),
        ]);

      case DeviceType.sensorTemp:
        final temp = device.state['temp'] ?? '--';
        final hum = device.state['humidity'] ?? '--';
        return Row(children: [
          _SensorPill(icon: Icons.thermostat_rounded, value: '$temp°C', color: cfg.color),
          const SizedBox(width: 6),
          _SensorPill(icon: Icons.water_drop_rounded, value: '$hum%', color: const Color(0xFF0EA5E9)),
        ]);

      case DeviceType.sensorCo2:
        final co2 = device.state['co2'] ?? '--';
        final color = (co2 is int && co2 > 1000) ? Colors.red : AppColors.emerald;
        return _SensorPill(icon: Icons.air_rounded, value: '$co2 ppm', color: color);

      case DeviceType.sensorMotion:
        final motion = device.state['motion'] == true;
        return _SensorPill(
          icon: motion ? Icons.directions_run_rounded : Icons.do_not_disturb_on_rounded,
          value: motion ? 'Mouvement' : 'Calme',
          color: motion ? Colors.orange : AppColors.textMuted,
        );

      case DeviceType.hub:
        return Row(children: [
          _SensorPill(icon: Icons.memory_rounded, value: 'RPi5', color: cfg.color),
        ]);

      case DeviceType.plug:
        return GestureDetector(
          onTap: () => notifier.toggle(device.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: device.isOn
                  ? cfg.color.withValues(alpha: 0.15)
                  : AppColors.bgCardLight,
              borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.power_rounded,
                color: device.isOn ? cfg.color : AppColors.textMuted, size: 14),
              const SizedBox(width: 4),
              Text(device.isOn ? 'ON' : 'OFF',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700,
                  color: device.isOn ? cfg.color : AppColors.textMuted)),
            ]),
          ),
        );

      case DeviceType.speaker:
        return SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: device.sliderValue,
            min: 0, max: 100,
            activeColor: cfg.color,
            inactiveColor: AppColors.bgCardLight,
            onChanged: (v) => notifier.setSlider(device.id, v),
          ),
        );
    }
  }
}

class _AdhanboxControl extends StatelessWidget {
  final Device device;
  final WidgetRef ref;
  const _AdhanboxControl({required this.device, required this.ref});

  @override
  Widget build(BuildContext context) {
    final api = ref.read(apiServiceProvider);
    return Row(children: [
      Expanded(child: GestureDetector(
        onTap: () => api.triggerAdhan(),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.emerald.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text('Adhan',
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.emerald,
              fontWeight: FontWeight.w600))),
        ),
      )),
      const SizedBox(width: 6),
      Expanded(child: GestureDetector(
        onTap: () => api.setLed(scenario: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text('LED',
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.gold,
              fontWeight: FontWeight.w600))),
        ),
      )),
    ]);
  }
}

// ── Detail sheet ──────────────────────────────────────────────────────────────

class _DeviceDetailSheet extends StatelessWidget {
  final Device device;
  final WidgetRef ref;
  const _DeviceDetailSheet({required this.device, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cfg = _DeviceConfig.of(device.type);
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(24),
        children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.textMuted,
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cfg.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16)),
              child: Icon(cfg.icon, color: cfg.color, size: 28),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(device.name, style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              Text('${device.room} • ${cfg.label}',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
            ]),
            const Spacer(),
            _StatusDot(status: device.status, size: 10),
          ]),
          const SizedBox(height: 24),
          ..._detailControls(context),
        ],
      ),
    );
  }

  List<Widget> _detailControls(BuildContext context) {
    final notifier = ref.read(devicesProvider.notifier);

    if (device.status == DeviceStatus.comingSoon) {
      return [_ComingSoonPanel()];
    }

    switch (device.type) {
      case DeviceType.adhanbox:
        return [_AdhanboxDetailPanel(device: device, ref: ref)];
      case DeviceType.ledStrip:
        return [_LedDetailPanel(device: device, notifier: notifier)];
      case DeviceType.bulb:
        return [_BulbDetailPanel(device: device, notifier: notifier)];
      case DeviceType.sensorTemp:
        return [_SensorTempPanel(device: device)];
      default:
        return [Text('Contrôles à venir',
          style: GoogleFonts.inter(color: AppColors.textMuted))];
    }
  }
}

class _AdhanboxDetailPanel extends StatelessWidget {
  final Device device;
  final WidgetRef ref;
  const _AdhanboxDetailPanel({required this.device, required this.ref});

  @override
  Widget build(BuildContext context) {
    final api = ref.read(apiServiceProvider);
    final notifier = ref.read(devicesProvider.notifier);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Audio', style: GoogleFonts.poppins(
        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _ActionBtn(
          label: '🕌  Adhan Fajr',
          color: AppColors.emerald,
          onTap: () => api.triggerAdhan(track: 2),
        )),
        const SizedBox(width: 10),
        Expanded(child: _ActionBtn(
          label: '⏹  Stop',
          color: Colors.red,
          onTap: () => api.setLed(scenario: 0),
        )),
      ]),
      const SizedBox(height: 16),
      Text('Volume', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
      Slider(
        value: device.sliderValue,
        min: 0, max: 30,
        activeColor: AppColors.emerald,
        inactiveColor: AppColors.bgCardLight,
        label: '${device.sliderValue.round()}',
        onChanged: (v) => notifier.setSlider(device.id, v),
      ),
      const SizedBox(height: 16),
      Text('LED', style: GoogleFonts.poppins(
        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _LedSceneBtn(label: 'Off',      scenario: 0,  color: Colors.grey),
        _LedSceneBtn(label: 'Hue',      scenario: 8,  color: AppColors.emerald),
        _LedSceneBtn(label: 'Prière',   scenario: 10, color: const Color(0xFF10B981)),
        _LedSceneBtn(label: 'Respir.',  scenario: 11, color: const Color(0xFF0EA5E9)),
        _LedSceneBtn(label: 'Fête',     scenario: 12, color: AppColors.gold),
      ].map((w) => Consumer(builder: (_, r, __) {
        final a = r.read(apiServiceProvider);
        return GestureDetector(
          onTap: () => a.setLed(scenario: (w as _LedSceneBtn).scenario),
          child: w,
        );
      })).toList()),
    ]);
  }
}

class _LedDetailPanel extends StatelessWidget {
  final Device device;
  final DevicesNotifier notifier;
  const _LedDetailPanel({required this.device, required this.notifier});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Luminosité', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
      Slider(
        value: device.sliderValue,
        min: 0, max: 100,
        activeColor: AppColors.gold,
        inactiveColor: AppColors.bgCardLight,
        label: '${device.sliderValue.round()}%',
        onChanged: (v) => notifier.setSlider(device.id, v),
      ),
    ],
  );
}

class _BulbDetailPanel extends StatelessWidget {
  final Device device;
  final DevicesNotifier notifier;
  const _BulbDetailPanel({required this.device, required this.notifier});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Text('Allumée', style: GoogleFonts.inter(fontSize: 14, color: Colors.white)),
        const Spacer(),
        Switch(value: device.isOn, onChanged: (_) => notifier.toggle(device.id),
          activeColor: AppColors.gold),
      ]),
      const SizedBox(height: 8),
      Text('Luminosité', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
      Slider(
        value: device.sliderValue,
        min: 0, max: 100,
        activeColor: AppColors.gold,
        inactiveColor: AppColors.bgCardLight,
        label: '${device.sliderValue.round()}%',
        onChanged: (v) => notifier.setSlider(device.id, v),
      ),
    ],
  );
}

class _SensorTempPanel extends StatelessWidget {
  final Device device;
  const _SensorTempPanel({required this.device});

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _BigStat(
      icon: Icons.thermostat_rounded,
      value: '${device.state['temp'] ?? '--'}°C',
      label: 'Température',
      color: Colors.orange,
    )),
    Expanded(child: _BigStat(
      icon: Icons.water_drop_rounded,
      value: '${device.state['humidity'] ?? '--'}%',
      label: 'Humidité',
      color: const Color(0xFF0EA5E9),
    )),
  ]);
}

class _ComingSoonPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.bgCardLight, borderRadius: BorderRadius.circular(16)),
    child: Column(children: [
      const Icon(Icons.construction_rounded, color: AppColors.gold, size: 32),
      const SizedBox(height: 10),
      Text('Bientôt disponible', style: GoogleFonts.poppins(
        fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
      const SizedBox(height: 6),
      Text('Cet appareil sera intégré via Zigbee / Home Assistant (Phase 2)',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
    ]),
  );
}

// ── Scènes islamiques ─────────────────────────────────────────────────────────

class _ScenesSection extends ConsumerWidget {
  static const _scenes = [
    ('Mode Prière',   '🤲', [Color(0xFF064E3B), Color(0xFF065F46)]),
    ('Fajr',          '🌅', [Color(0xFF1E3A5F), Color(0xFF1E40AF)]),
    ('Tahajjud',      '🌙', [Color(0xFF1A1035), Color(0xFF2D1B69)]),
    ('Ramadan',       '🌙', [Color(0xFF3D1A00), Color(0xFF92400E)]),
    ('Do Not Disturb','🤫', [Color(0xFF1F1F1F), Color(0xFF374151)]),
    ('Étude',         '📖', [Color(0xFF0C2340), Color(0xFF1E3A5F)]),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Scènes islamiques', style: GoogleFonts.poppins(
        fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
      const SizedBox(height: 10),
      SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _scenes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final s = _scenes[i];
            return GestureDetector(
              onTap: () {},
              child: Container(
                width: 120,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: s.$3),
                  borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Text(s.$2, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.$1, style: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white))),
                ]),
              ),
            );
          },
        ),
      ),
    ],
  );
}

// ── Add Device sheet ──────────────────────────────────────────────────────────

class _AddDeviceSheet extends StatelessWidget {
  const _AddDeviceSheet();

  static const _types = [
    (DeviceType.bulb,         'Ampoule',           Icons.lightbulb_rounded,         'Zigbee / WiFi'),
    (DeviceType.ledStrip,     'Bandeau LED',        Icons.linear_scale_rounded,       'Zigbee / WiFi'),
    (DeviceType.speaker,      'Enceinte',           Icons.speaker_rounded,            'WiFi / BT'),
    (DeviceType.plug,         'Prise connectée',    Icons.power_rounded,              'Zigbee / WiFi'),
    (DeviceType.sensorTemp,   'Capteur T°/Hum.',   Icons.thermostat_rounded,         'Zigbee'),
    (DeviceType.sensorCo2,    'Capteur CO₂',        Icons.air_rounded,                'Zigbee / WiFi'),
    (DeviceType.sensorMotion, 'Détecteur mouv.',    Icons.sensors_rounded,            'Zigbee'),
    (DeviceType.adhanbox,     'AdhanBox (ESP32)',   Icons.mosque_rounded,             'WiFi / MQTT'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 16),
      Text('Ajouter un appareil', style: GoogleFonts.poppins(
        fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
      const SizedBox(height: 4),
      Text('Sélectionnez le type d\'appareil à intégrer',
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
      const SizedBox(height: 16),
      ...(_types.map((t) => ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _DeviceConfig.of(t.$1).color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10)),
          child: Icon(t.$3, color: _DeviceConfig.of(t.$1).color, size: 20),
        ),
        title: Text(t.$2, style: GoogleFonts.inter(fontSize: 13, color: Colors.white)),
        subtitle: Text(t.$4, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded,
          color: AppColors.textMuted, size: 14),
        onTap: () => Navigator.pop(context),
      ))),
    ]),
  );
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final DeviceStatus status;
  final double size;
  const _StatusDot({required this.status, this.size = 8});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DeviceStatus.online     => AppColors.emerald,
      DeviceStatus.offline    => Colors.red,
      DeviceStatus.comingSoon => AppColors.gold,
    };
    return Container(width: size, height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusPill({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 12),
      const SizedBox(width: 5),
      Text(label, style: GoogleFonts.inter(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    ]),
  );
}

class _RoomChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RoomChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: 200.ms,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.emerald : AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.emerald : AppColors.bgCardLight)),
      child: Text(label, style: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w500,
        color: selected ? Colors.white : AppColors.textMuted)),
    ),
  );
}

class _SensorPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _SensorPill({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 4),
      Text(value, style: GoogleFonts.inter(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Center(child: Text(label, style: GoogleFonts.inter(
        fontSize: 13, color: color, fontWeight: FontWeight.w600))),
    ),
  );
}

class _LedSceneBtn extends StatelessWidget {
  final String label;
  final int scenario;
  final Color color;
  const _LedSceneBtn({required this.label, required this.scenario, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.3))),
    child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
  );
}

class _BigStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _BigStat({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
    child: Column(children: [
      Icon(icon, color: color, size: 24),
      const SizedBox(height: 6),
      Text(value, style: GoogleFonts.poppins(
        fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
      Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
    ]),
  );
}

// ── Device config (couleur + icône + label par type) ─────────────────────────

class _DeviceConfig {
  final Color color;
  final IconData icon;
  final String label;
  const _DeviceConfig(this.color, this.icon, this.label);

  static _DeviceConfig of(DeviceType type) => switch (type) {
    DeviceType.adhanbox     => const _DeviceConfig(AppColors.emerald,          Icons.mosque_rounded,          'AdhanBox'),
    DeviceType.hub          => const _DeviceConfig(Color(0xFF0EA5E9),           Icons.developer_board_rounded, 'Hub RPi5'),
    DeviceType.ledStrip     => const _DeviceConfig(Color(0xFF8B5CF6),           Icons.linear_scale_rounded,    'LED Strip'),
    DeviceType.bulb         => const _DeviceConfig(AppColors.gold,              Icons.lightbulb_rounded,       'Ampoule'),
    DeviceType.speaker      => const _DeviceConfig(Color(0xFFEC4899),           Icons.speaker_rounded,         'Enceinte'),
    DeviceType.sensorTemp   => const _DeviceConfig(Colors.orange,               Icons.thermostat_rounded,      'Capteur T°'),
    DeviceType.sensorCo2    => const _DeviceConfig(Color(0xFF10B981),           Icons.air_rounded,             'Capteur CO₂'),
    DeviceType.sensorMotion => const _DeviceConfig(Color(0xFFF59E0B),           Icons.sensors_rounded,         'Mouvement'),
    DeviceType.plug         => const _DeviceConfig(Color(0xFF64748B),           Icons.power_rounded,           'Prise'),
  };
}
