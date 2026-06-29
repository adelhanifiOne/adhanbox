import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/prayers_screen.dart';
import 'screens/led_control_screen.dart';
import 'screens/adhan_config_screen.dart';
import 'screens/azkar_coran_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tutorial_screen.dart';
import 'theme/app_theme.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final prefs = await SharedPreferences.getInstance();
  final isFirstLaunch = prefs.getBool('tutorial_done') != true;

  runApp(ProviderScope(child: AdhanBoxApp(showTutorial: isFirstLaunch)));
}

class AdhanBoxApp extends ConsumerWidget {
  final bool showTutorial;
  const AdhanBoxApp({Key? key, required this.showTutorial}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'AdhanBox',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: showTutorial ? const _TutorialEntry() : const MainNav(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ─── Tutorial entry wrapper (handles page state + nav overlay) ───────────────

class _TutorialEntry extends StatefulWidget {
  const _TutorialEntry();

  @override
  State<_TutorialEntry> createState() => _TutorialEntryState();
}

class _TutorialEntryState extends State<_TutorialEntry>
    with TickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  late AnimationController _iconAnim;
  late AnimationController _contentAnim;
  int _page = 0;

  // Slides count — must match tutorial_screen.dart _slides list
  static const int _total = 8;

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
    if (_page < _total - 1) {
      _contentAnim.reset();
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      _contentAnim.forward();
    } else {
      _done();
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

  Future<void> _done() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tutorial_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => const MainNav(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Accent color per slide (must match _slides in tutorial_screen.dart)
    const accents = [
      AppTheme.emerald,
      Color(0xFFEF4444),
      Color(0xFF3B82F6),
      AppTheme.emerald,
      AppTheme.gold,
      Color(0xFF8B5CF6),
      AppTheme.goldLight,
      AppTheme.emerald,
    ];
    final accent = accents[_page.clamp(0, accents.length - 1)];
    final isLast = _page == _total - 1;

    return Scaffold(
      body: Stack(
        children: [
          // Page view (slides)
          PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: _total,
            itemBuilder: (_, i) => TutorialSlidePage(
              slideIndex: i,
              iconAnim: _iconAnim,
              contentAnim: _contentAnim,
            ),
          ),

          // Navigation overlay (dots + buttons)
          TutorialNav(
            page: _page,
            total: _total,
            accentColor: accent,
            isLast: isLast,
            onNext: _goNext,
            onPrev: _page > 0 ? _goPrev : null,
            onSkip: _done,
          ),
        ],
      ),
    );
  }
}

// ─── Main navigation ─────────────────────────────────────────────────────────

class MainNav extends ConsumerStatefulWidget {
  const MainNav({Key? key}) : super(key: key);

  @override
  ConsumerState<MainNav> createState() => _MainNavState();
}

class _MainNavState extends ConsumerState<MainNav> {
  int _index = 0;

  static const _pages = [
    PrayersScreen(),
    LedControlScreen(),
    AdhanConfigScreen(),
    AzkarCoranScreen(),
    SettingsScreen(),
  ];

  static const _items = [
    _NavItem(icon: Icons.mosque_rounded,       label: 'Prières'),
    _NavItem(icon: Icons.light_rounded,        label: 'Lumière'),
    _NavItem(icon: Icons.music_note_rounded,   label: 'Adhan'),
    _NavItem(icon: Icons.auto_stories_rounded, label: 'Récitations'),
    _NavItem(icon: Icons.tune_rounded,         label: 'Réglages'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: _items.map((item) => NavigationDestination(
            icon: Icon(item.icon),
            label: item.label,
          )).toList(),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
