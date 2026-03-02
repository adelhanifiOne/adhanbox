# AdhanBox Mobile App

Mobile Flutter app pour contrôler et configurer le device AdhanBox (IoT Adhan).

## 🎯 Fonctionnalités

- **Horaires de prière** - Affichage calculé + Mawaqit (mosquée proche)
- **Comparaison automatique** - Voir différences entre calcul et Mawaqit
- **Contrôle LED** - Couleurs, luminosité, scénarios
- **Gestion WiFi** - Scan et connexion
- **Géolocalisation** - GPS du téléphone pour configuration initiale
- **Configuration audio** - Volume, pistes Adhan, Duaa

## 📦 Installation

### Prérequis
- Flutter 3.0+
- Dart 3.0+
- Android SDK 21+ (ou iOS 12+)

### Étapes

```bash
# 1. Cloner le repo
cd flutter_app

# 2. Installer dépendances
flutter pub get

# 3. Générer code (Riverpod + Hive)
flutter pub run build_runner build

# 4. Lancer app
flutter run
```

## 🏗️ Architecture

```
lib/
├── main.dart                 # Entry point
├── screens/
│   ├── home_screen.dart
│   ├── prayer_times_screen.dart
│   ├── led_control_screen.dart
│   ├── settings_screen.dart
│   └── about_screen.dart
├── services/
│   ├── adhanbox_api.dart     # API REST client
│   └── location_service.dart # GPS
├── providers/
│   └── adhanbox_provider.dart # Riverpod state
├── models/
│   ├── prayer_time.dart
│   └── device_config.dart
└── widgets/
    ├── prayer_card.dart
    ├── led_control_widget.dart
    └── wifi_selector.dart
```

## 📱 Écrans

### 1. Home Screen (Accueil)
```
┌─────────────────────────┐
│ 14:30 | WiFi: Connected │
├─────────────────────────┤
│   Prochaine prière      │
│      Dhuhr - 12:45      │
│     Commencer dans 15mn │
├─────────────────────────┤
│ [Localiser] [Paramètres]│
└─────────────────────────┘
```

### 2. Prayer Times Screen
```
┌──────────────────────────────┐
│ Horaires du jour             │
├──────────────────────────────┤
│ Fajr      05:20 | 05:21  ✓ │
│ Dhuhr     12:45 | 12:46  ✓ │
│ Asr       16:10 | 16:11  ✓ │
│ Maghreb   19:20 | 19:21  ✓ │
│ Isha      20:50 | 20:51  ✓ │
├──────────────────────────────┤
│    [Synchroniser Mawaqit]    │
└──────────────────────────────┘
```

### 3. LED Control Screen
```
┌─────────────────────────┐
│ Contrôle LED            │
├─────────────────────────┤
│ Scénario:               │
│ [Dynamic Hue      ▼]    │
│ Luminosité:             │
│ [══════════] 50%        │
│ [Test LED]              │
└─────────────────────────┘
```

## 🔌 API Endpoints

L'app utilise ces endpoints REST de l'ESP32:

- `GET /api/status` - État global
- `GET /api/prayer/times` - Horaires calculés
- `GET /api/mawaqit/times` - Horaires Mawaqit
- `GET /api/mawaqit/comparison` - Comparaison
- `POST /api/mawaqit/sync` - Synchroniser
- `POST /api/led/scenario` - Changer LED
- `POST /api/led/brightness` - Luminosité
- `POST /api/audio/volume` - Volume
- `GET /api/wifi/scan` - Scan WiFi
- `POST /api/wifi/connect` - Connexion WiFi

[Voir documentation complète](../API_REST.md)

## 🔒 Permissions

L'app nécessite les permissions suivantes:

```xml
<!-- Android -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<!-- iOS -->
NSLocationWhenInUseUsageDescription
NSLocalNetworkUsageDescription
```

## 📊 État (State Management)

Utilise **Riverpod** avec architecture fonctionnelle:

```dart
// Récupérer horaires de prière
final prayerTimes = ref.watch(prayerTimesProvider);

// Changer la luminosité LED
ref.read(ledBrightnessProvider.notifier).state = 75;

// Rafraîchir toutes les données
RefreshController.refreshAll(ref);
```

## 🧪 Testing

```bash
# Tests unitaires
flutter test

# Tests intégration
flutter test integration_test/
```

## 🚀 Build & Déploiement

### Android APK
```bash
flutter build apk --release
```

### Android App Bundle (Play Store)
```bash
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

## 📝 Environnement de développement

### Avec FlutterFlow

1. Ouvrir [FlutterFlow Dashboard](https://app.flutterflow.io)
2. Importer ce repo
3. Générer code à partir de l'UI
4. Merger avec custom code local (dossier `custom_code/`)

### Avec VS Code

```bash
# Obtenir le code généré
git clone <flutterflow-repo>

# Brancher custom code
ln -s ../custom_code lib/custom_code

# Lancer en mode debug
flutter run -d web
```

## 📚 Ressources

- [Flutter Docs](https://flutter.dev/docs)
- [Riverpod Docs](https://riverpod.dev)
- [Mawaqit API](https://mawaqit.net/api)
- [AdhanBox API](../API_REST.md)

## 🤝 Contribution

1. Fork le repo
2. Créer une branche (`git checkout -b feature/amazing-feature`)
3. Commit les changements (`git commit -m 'Add amazing feature'`)
4. Push vers la branche (`git push origin feature/amazing-feature`)
5. Ouvrir une Pull Request

## 📄 Licence

Voir LICENSE file

## 👨‍💻 Auteur

Développé pour le projet AdhanBox

---

**Questions?** Ouvrir une issue ou contacter l'équipe.
