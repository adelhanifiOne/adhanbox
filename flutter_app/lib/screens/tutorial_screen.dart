import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

// ─── Data ────────────────────────────────────────────────────────────────────

class _Slide {
  final IconData icon;
  final Color iconColor;
  final Color bgGradientStart;
  final Color bgGradientEnd;
  final String title;
  final String subtitle;
  final List<_Tip> tips;
  const _Slide({
    required this.icon,
    required this.iconColor,
    required this.bgGradientStart,
    required this.bgGradientEnd,
    required this.title,
    required this.subtitle,
    this.tips = const [],
  });
}

class _Tip {
  final IconData icon;
  final Color color;
  final String text;
  const _Tip({required this.icon, required this.color, required this.text});
}

const _slides = [
  // 0 — Bienvenue
  _Slide(
    icon: Icons.mosque_rounded,
    iconColor: AppTheme.emerald,
    bgGradientStart: Color(0xFF0F172A),
    bgGradientEnd: Color(0xFF064E3B),
    title: 'Bienvenue sur\nAdhanBox',
    subtitle: 'Votre compagnon intelligent pour les heures de prière, l\'adhan et l\'ambiance lumineuse.',
    tips: [],
  ),
  // 1 — Redémarrer l'appareil
  _Slide(
    icon: Icons.power_settings_new_rounded,
    iconColor: Color(0xFFEF4444),
    bgGradientStart: Color(0xFF0F172A),
    bgGradientEnd: Color(0xFF450A0A),
    title: 'Avant de commencer',
    subtitle: 'Débranchez puis rebranchez votre AdhanBox pour lancer le mode configuration.',
    tips: [
      _Tip(
        icon: Icons.circle,
        color: Color(0xFFEF4444),
        text: 'Les LEDs clignotent en rouge → l\'AdhanBox est en mode Bluetooth, prête à être configurée.',
      ),
      _Tip(
        icon: Icons.bluetooth_rounded,
        color: Color(0xFF3B82F6),
        text: 'Le mode Bluetooth reste actif jusqu\'à la fin de la configuration — prenez votre temps.',
      ),
      _Tip(
        icon: Icons.touch_app_rounded,
        color: AppTheme.emerald,
        text: 'Appui bref sur le bouton tactile = quitter le mode Bluetooth manuellement.',
      ),
    ],
  ),
  // 2 — Connexion Bluetooth
  _Slide(
    icon: Icons.bluetooth_searching_rounded,
    iconColor: Color(0xFF3B82F6),
    bgGradientStart: Color(0xFF0F172A),
    bgGradientEnd: Color(0xFF1E3A5F),
    title: 'Connexion\nBluetooth',
    subtitle: 'L\'app détecte automatiquement votre AdhanBox à proximité via Bluetooth.',
    tips: [
      _Tip(
        icon: Icons.bluetooth_rounded,
        color: Color(0xFF3B82F6),
        text: 'Activez le Bluetooth de votre téléphone avant de lancer la configuration.',
      ),
      _Tip(
        icon: Icons.router_rounded,
        color: AppTheme.emerald,
        text: 'L\'appareil apparaît sous le nom "AdhanBox-XXXXXX" dans la liste.',
      ),
      _Tip(
        icon: Icons.location_on_rounded,
        color: AppTheme.gold,
        text: 'Autorisez la localisation — requise sur certains appareils pour scanner le Bluetooth.',
      ),
    ],
  ),
  // 3 — Connexion WiFi
  _Slide(
    icon: Icons.wifi_rounded,
    iconColor: AppTheme.emerald,
    bgGradientStart: Color(0xFF0F172A),
    bgGradientEnd: Color(0xFF064E3B),
    title: 'Votre réseau\nWiFi',
    subtitle: 'Connectez l\'AdhanBox à votre réseau WiFi domestique pour accéder à toutes les fonctionnalités.',
    tips: [
      _Tip(
        icon: Icons.send_rounded,
        color: AppTheme.emerald,
        text: 'Sélectionnez votre réseau et entrez le mot de passe — envoyé sécurisément via Bluetooth.',
      ),
      _Tip(
        icon: Icons.check_circle_rounded,
        color: AppTheme.emeraldLight,
        text: 'L\'AdhanBox se souvient du WiFi même après un redémarrage.',
      ),
      _Tip(
        icon: Icons.offline_bolt_rounded,
        color: AppTheme.gold,
        text: 'Mode hors-ligne disponible : le calcul des prières fonctionne sans Internet.',
      ),
    ],
  ),
  // 4 — Horaires de prière
  _Slide(
    icon: Icons.access_time_rounded,
    iconColor: AppTheme.gold,
    bgGradientStart: Color(0xFF0F172A),
    bgGradientEnd: Color(0xFF451A03),
    title: 'Horaires\nde prière',
    subtitle: 'Synchronisez avec votre mosquée locale via Mawaqit ou utilisez le calcul automatique.',
    tips: [
      _Tip(
        icon: Icons.mosque_rounded,
        color: AppTheme.gold,
        text: 'Mawaqit : trouvez votre mosquée pour des horaires officiels synchronisés quotidiennement.',
      ),
      _Tip(
        icon: Icons.calculate_rounded,
        color: AppTheme.emerald,
        text: 'Calcul local : méthode MWL, ISNA, Egypt… basé sur votre position GPS.',
      ),
    ],
  ),
  // 5 — Adhan
  _Slide(
    icon: Icons.music_note_rounded,
    iconColor: Color(0xFF8B5CF6),
    bgGradientStart: Color(0xFF0F172A),
    bgGradientEnd: Color(0xFF2E1065),
    title: 'Adhan\npersonnalisé',
    subtitle: 'Choisissez la voix de l\'adhan pour chaque prière et activez le Doua après l\'adhan.',
    tips: [
      _Tip(
        icon: Icons.mic_rounded,
        color: Color(0xFF8B5CF6),
        text: 'Plusieurs voix disponibles — dont des appels spécifiques pour le Fajr (Soubh).',
      ),
      _Tip(
        icon: Icons.volume_up_rounded,
        color: AppTheme.emerald,
        text: 'Ajustez le volume indépendamment depuis l\'application.',
      ),
    ],
  ),
  // 6 — LEDs
  _Slide(
    icon: Icons.light_rounded,
    iconColor: AppTheme.goldLight,
    bgGradientStart: Color(0xFF0F172A),
    bgGradientEnd: Color(0xFF3B2800),
    title: 'Ambiance\nlumineuse',
    subtitle: 'Créez une atmosphère unique avec les scénarios lumineux de l\'AdhanBox.',
    tips: [
      _Tip(
        icon: Icons.wb_sunny_rounded,
        color: AppTheme.goldLight,
        text: 'Bougie, arc-en-ciel, respiration, couleurs statiques… et bien plus.',
      ),
      _Tip(
        icon: Icons.touch_app_rounded,
        color: AppTheme.emerald,
        text: 'Changez de scénario directement avec le bouton tactile de l\'appareil.',
      ),
    ],
  ),
  // 7 — Prêt !
  _Slide(
    icon: Icons.check_circle_rounded,
    iconColor: AppTheme.emerald,
    bgGradientStart: Color(0xFF0F172A),
    bgGradientEnd: Color(0xFF064E3B),
    title: 'C\'est parti !',
    subtitle: 'Votre AdhanBox est prête. Que Allah facilite vos prières.',
    tips: [],
  ),
];

// ─── Screen ──────────────────────────────────────────────────────────────────

class TutorialScreen extends StatefulWidget {
  final VoidCallback onDone;
  const TutorialScreen({super.key, required this.onDone});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen>
    with TickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int _page = 0;
  late AnimationController _iconAnim;
  late AnimationController _contentAnim;

  @override
  void initState() {
    super.initState();
    _iconAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _contentAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _iconAnim.dispose();
    _contentAnim.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_page < _slides.length - 1) {
      _contentAnim.reset();
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      _contentAnim.forward();
    } else {
      widget.onDone();
    }
  }

  void _goPrev() {
    if (_page > 0) {
      _contentAnim.reset();
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      _contentAnim.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _pageCtrl,
        onPageChanged: (i) => setState(() => _page = i),
        itemCount: _slides.length,
        itemBuilder: (_, i) => _SlidePage(
          slide: _slides[i],
          iconAnim: _iconAnim,
          contentAnim: _contentAnim,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildNav() {
    final slide = _slides[_page];
    final isLast = _page == _slides.length - 1;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              slide.bgGradientEnd.withOpacity(0),
              slide.bgGradientEnd.withOpacity(0.9),
            ],
          ),
        ),
        child: Row(
          children: [
            // Dots
            Expanded(
              child: Row(
                children: List.generate(_slides.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(right: 6),
                    width: active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? slide.iconColor : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
            // Prev
            if (_page > 0)
              IconButton(
                onPressed: _goPrev,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
              ),
            const SizedBox(width: 8),
            // Next / Done
            GestureDetector(
              onTap: _goNext,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: slide.iconColor,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: slide.iconColor.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isLast ? 'Commencer' : 'Suivant',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      isLast ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Public alias so main.dart can use it directly
class TutorialSlidePage extends StatelessWidget {
  final int slideIndex;
  final AnimationController iconAnim;
  final AnimationController contentAnim;

  const TutorialSlidePage({
    super.key,
    required this.slideIndex,
    required this.iconAnim,
    required this.contentAnim,
  });

  @override
  Widget build(BuildContext context) {
    return _SlidePage(
      slide: _slides[slideIndex],
      iconAnim: iconAnim,
      contentAnim: contentAnim,
    );
  }
}



class _SlidePage extends StatelessWidget {
  final _Slide slide;
  final AnimationController iconAnim;
  final AnimationController contentAnim;

  const _SlidePage({
    required this.slide,
    required this.iconAnim,
    required this.contentAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [slide.bgGradientStart, slide.bgGradientEnd],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ── Icon area ──
            Expanded(
              flex: 4,
              child: Center(
                child: AnimatedBuilder(
                  animation: iconAnim,
                  builder: (_, __) {
                    final pulse = 0.92 + 0.08 * iconAnim.value;
                    return Transform.scale(
                      scale: pulse,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer glow ring
                          ...List.generate(3, (i) {
                            final opacity = (0.06 - i * 0.015) * iconAnim.value;
                            final size = 160.0 + i * 40;
                            return Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: slide.iconColor.withValues(alpha: opacity.clamp(0.0, 1.0)),
                              ),
                            );
                          }),
                          // Icon container
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: slide.iconColor.withValues(alpha: 0.15),
                              border: Border.all(
                                color: slide.iconColor.withValues(alpha: 0.4),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: slide.iconColor.withValues(alpha: 0.3),
                                  blurRadius: 40,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Icon(slide.icon, size: 56, color: slide.iconColor),
                          ),
                          // Special: red blink animation for slide 1
                          if (slide.bgGradientEnd == const Color(0xFF450A0A))
                            Positioned(
                              top: 10,
                              right: 10,
                              child: AnimatedBuilder(
                                animation: iconAnim,
                                builder: (_, __) {
                                  final alpha = (iconAnim.value * 255).round();
                                  return Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color.fromARGB(alpha, 239, 68, 68),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFEF4444).withValues(alpha: 0.6 * iconAnim.value),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── Text + Tips ──
            Expanded(
              flex: 6,
              child: FadeTransition(
                opacity: contentAnim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: contentAnim, curve: Curves.easeOut)),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slide.title,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          slide.subtitle,
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                        if (slide.tips.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          ...slide.tips.map((tip) => _TipCard(tip: tip)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final _Tip tip;
  const _TipCard({required this.tip});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tip.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: tip.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(tip.icon, color: tip.color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tip.text,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Navigation Bottom (overlay) ─────────────────────────────────────────────

class TutorialNav extends StatelessWidget {
  final int page;
  final int total;
  final Color accentColor;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback? onPrev;
  final VoidCallback onSkip;

  const TutorialNav({
    super.key,
    required this.page,
    required this.total,
    required this.accentColor,
    required this.isLast,
    required this.onNext,
    this.onPrev,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Row(
          children: [
            // Dots
            Expanded(
              child: Row(
                children: List.generate(total, (i) {
                  final active = i == page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(right: 6),
                    width: active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? accentColor : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
            // Skip (not on last)
            if (!isLast)
              TextButton(
                onPressed: onSkip,
                child: Text(
                  'Passer',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
                ),
              ),
            if (onPrev != null)
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
              ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onNext,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        isLast ? 'Commencer !' : 'Suivant',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      isLast ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
