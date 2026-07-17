// [PLAYER] État de lecture de l'AdhanBox — alimente la barre « en cours de
// lecture » (façon app de streaming). Le téléphone ne lit PAS l'audio : il
// pilote la box. On sonde /api/audio/status (firmware >= 2.3.19) toutes les
// 2,5 s pour refléter l'état RÉEL, y compris un adhan lancé par la box
// elle-même ou un audio lancé par un autre téléphone du foyer.
import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/quran_data.dart';
import 'adhanbox_provider.dart';

class PlaybackState {
  final bool playing;        // un fichier est chargé (même en pause)
  final bool paused;
  final String file;         // chemin SD du fichier en cours ('' si rien)
  final int pos;             // octets lus
  final int size;            // taille du fichier (octets)
  final int volume;          // 0-30 (volume de la box)
  final List<String> queue;  // file d'attente pilotée par l'app
  final int queueIndex;      // -1 si le fichier en cours ne vient pas de la file
  final bool autoplay;       // enchaîner automatiquement la file
  final bool shuffle;        // piocher au hasard dans la file

  const PlaybackState({
    this.playing = false,
    this.paused = false,
    this.file = '',
    this.pos = 0,
    this.size = 0,
    this.volume = 20,
    this.queue = const [],
    this.queueIndex = -1,
    this.autoplay = false,
    this.shuffle = false,
  });

  double get progress => size > 0 ? (pos / size).clamp(0.0, 1.0) : 0.0;
  bool get hasAudio => playing || file.isNotEmpty;
  bool get hasQueue => queue.length > 1;

  PlaybackState copyWith({
    bool? playing,
    bool? paused,
    String? file,
    int? pos,
    int? size,
    int? volume,
    List<String>? queue,
    int? queueIndex,
    bool? autoplay,
    bool? shuffle,
  }) {
    return PlaybackState(
      playing: playing ?? this.playing,
      paused: paused ?? this.paused,
      file: file ?? this.file,
      pos: pos ?? this.pos,
      size: size ?? this.size,
      volume: volume ?? this.volume,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      autoplay: autoplay ?? this.autoplay,
      shuffle: shuffle ?? this.shuffle,
    );
  }

  /// Titre lisible du fichier en cours (chemins SD -> noms parlants).
  String get title => prettyTitle(file);
  String get subtitle => prettySubtitle(file);

  static String prettyTitle(String path) {
    if (path.isEmpty) return '';
    final p = path.toLowerCase();
    // /quran/<slug>/NNN.mp3 -> nom de la sourate
    final m = RegExp(r'^/quran/([^/]+)/(\d{3})\.mp3$').firstMatch(p);
    if (m != null) {
      final num_ = int.tryParse(m.group(2)!) ?? 0;
      final s = kSurahs.where((s) => s.number == num_);
      if (s.isNotEmpty) return 'Sourate ${s.first.name}';
      return 'Sourate $num_';
    }
    if (p.contains('al-kahf')) return 'Sourate Al-Kahf';
    if (p.contains('al-mulk')) return 'Sourate Al-Mulk';
    if (p.contains('/azkar/sabah')) return 'Azkar du matin';
    if (p.contains('/azkar/masaa')) return 'Azkar du soir';
    if (p.startsWith('/mp3/0001')) return 'Doua après l\'adhan';
    if (p.startsWith('/mp3/')) return 'Adhan';
    // défaut : nom de fichier sans extension
    final name = path.split('/').last;
    return name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
  }

  static String prettySubtitle(String path) {
    final m = RegExp(r'^/quran/([^/]+)/\d{3}\.mp3$').firstMatch(path.toLowerCase());
    if (m != null) {
      final r = kReciters.where((r) => r.slug == m.group(1));
      if (r.isNotEmpty) return r.first.name;
    }
    if (path.toLowerCase().startsWith('/mp3/')) return 'AdhanBox';
    return '';
  }
}

class PlaybackController extends StateNotifier<PlaybackState> {
  final Ref ref;
  Timer? _poll;
  final _rng = Random();

  PlaybackController(this.ref) : super(const PlaybackState()) {
    // Nouvelle box sélectionnée -> on repart d'un état neuf et on resonde.
    ref.listen<String?>(currentDeviceIpProvider, (prev, next) {
      if (prev != next) {
        state = PlaybackState(autoplay: state.autoplay, shuffle: state.shuffle);
        _tick();
      }
    });
    _poll = Timer.periodic(const Duration(milliseconds: 2500), (_) => _tick());
    _tick();
  }

  Future<void> _tick() async {
    final api = ref.read(adhanboxApiProvider);
    if (api == null) return;
    try {
      final st = await api.getAudioStatus();
      final playing = st['playing'] == true;
      final paused = st['paused'] == true;
      final file = (st['file'] as String?) ?? '';
      final wasPlaying = state.playing;
      final prevFile = state.file;

      // Le fichier a changé sous nos pieds (adhan auto, autre téléphone…) :
      // si ce n'est pas celui de notre file, on désindexe la file.
      int qIndex = state.queueIndex;
      if (file != prevFile) {
        qIndex = state.queue.indexOf(file);
      }

      state = state.copyWith(
        playing: playing,
        paused: paused,
        file: file,
        pos: (st['pos'] as num?)?.toInt() ?? 0,
        size: (st['size'] as num?)?.toInt() ?? 0,
        volume: (st['volume'] as num?)?.toInt() ?? state.volume,
        queueIndex: qIndex,
      );

      // [AUTOPLAY] La piste vient de se terminer naturellement (pas une pause,
      // pas un stop pendant pause) -> on enchaîne si l'utilisateur l'a demandé.
      if (wasPlaying && !playing && !paused && state.autoplay && state.queue.isNotEmpty) {
        await next();
      }
    } catch (_) {
      // box injoignable ou firmware < 2.3.19 : la barre reste discrète
      if (state.playing || state.file.isNotEmpty) {
        state = state.copyWith(playing: false, paused: false, file: '', pos: 0, size: 0);
      }
    }
  }

  /// Lance la lecture d'une file (ex. les 114 sourates du récitateur choisi)
  /// à partir de l'index donné.
  Future<void> playQueue(List<String> files, int index) async {
    final api = ref.read(adhanboxApiProvider);
    if (api == null || files.isEmpty) return;
    final i = index.clamp(0, files.length - 1);
    await api.playFile(files[i]);
    state = state.copyWith(
      queue: List.unmodifiable(files),
      queueIndex: i,
      file: files[i],
      playing: true,
      paused: false,
      pos: 0,
      size: 0,
    );
  }

  /// Pause <-> reprise (sans repartir du début).
  Future<void> togglePause() async {
    final api = ref.read(adhanboxApiProvider);
    if (api == null || !state.playing) return;
    try {
      if (state.paused) {
        await api.resumeAudio();
        state = state.copyWith(paused: false);
      } else {
        await api.pauseAudio();
        state = state.copyWith(paused: true);
      }
    } catch (_) {}
  }

  /// Piste suivante de la file (aléatoire si shuffle).
  Future<void> next() async {
    if (state.queue.isEmpty) return;
    int i;
    if (state.shuffle) {
      i = _rng.nextInt(state.queue.length);
      if (state.queue.length > 1 && i == state.queueIndex) {
        i = (i + 1) % state.queue.length;
      }
    } else {
      i = (state.queueIndex + 1) % state.queue.length;
    }
    await playQueue(state.queue, i);
  }

  Future<void> stop() async {
    final api = ref.read(adhanboxApiProvider);
    if (api == null) return;
    await api.stopAudio();
    state = state.copyWith(playing: false, paused: false, file: '', pos: 0, size: 0, queueIndex: -1);
  }

  void toggleAutoplay() => state = state.copyWith(autoplay: !state.autoplay);
  void toggleShuffle() => state = state.copyWith(shuffle: !state.shuffle);

  Future<void> setVolume(int v) async {
    final api = ref.read(adhanboxApiProvider);
    if (api == null) return;
    state = state.copyWith(volume: v);
    try {
      await api.setVolume(v);
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

final playbackProvider =
    StateNotifierProvider<PlaybackController, PlaybackState>((ref) {
  return PlaybackController(ref);
});
