# AdhanBox

AdhanBox est un système automatisé de diffusion de l'adhan (appel à la prière) basé sur ESP32.

## Caractéristiques

- 🕌 **Calcul automatique** des horaires de prière basé sur la géolocalisation
- 🔊 **DFPlayer Mini** pour la lecture audio
- 💡 **Bande LED adressable** SK6812/WS2812 (150 LEDs RGB+W)
- 🌐 **Interface Web** de configuration via point d'accès WiFi
- ⏰ **Horloge RTC DS3231** pour le timing précis
- 📍 **Géolocalisation** WiFi (API HERE) ou manuelle

## Séquence de lecture

- **Fajr** : Piste 2 (0002.mp3) + Duaa (0003.mp3)
- **Autres prières** : Piste 1 (0001.mp3) + Duaa (0003.mp3)

## Matériel requis

- ESP32 (240MHz)
- DS3231 RTC avec batterie
- DFPlayer Mini + carte microSD
- Bande LED SK6812/WS2812 (150 LEDs)
- Haut-parleur/amplificateur
- Bouton de configuration

## Brochage

| Composant | Pin ESP32 |
|-----------|-----------|
| LED Data  | GPIO 13   |
| RTC SDA   | GPIO 5    |
| RTC SCL   | GPIO 4    |
| RTC INT   | GPIO 7    |
| DFPlayer RX | GPIO 2  |
| DFPlayer TX | GPIO 1  |
| Bouton Config | GPIO 11 |

## Installation

1. Installer Arduino IDE ou PlatformIO
2. Installer les bibliothèques :
   - RTClib
   - DFRobotDFPlayerMini
   - Preferences (incluse ESP32)
3. Préparer carte SD avec fichiers audio :
   - `0001.mp3` : Adhan standard
   - `0002.mp3` : Adhan Fajr
   - `0003.mp3` : Duaa
4. Téléverser le sketch sur ESP32

## Configuration

1. Au démarrage, l'ESP32 crée un point d'accès WiFi `AdhanBox-XXXX`
2. Se connecter avec smartphone/PC
3. Accéder à l'interface web (redirection automatique)
4. Configurer :
   - Position géographique
   - Fuseau horaire
   - WiFi (optionnel, pour sync NTP)
   - Volume et luminosité

## Interface Web

- **Tableau** : Vue d'ensemble, contrôles rapides
- **Localisation** : Configuration manuelle ou auto (WiFi)
- **Horaires** : Visualisation des heures de prière
- **Avancé** : RTC, LED, diagnostics

## Scènes lumineuses

- Off / Couleurs statiques (Rouge, Rose, Bleu, Violet, Vert, Jaune)
- Dynamic hue : Cycle de couleurs
- Dynamic fade : Transitions douces
- Luminosité réglable 0-100%

## Licence

Projet open source - libre d'utilisation et modification

## Auteur

Développé pour la communauté musulmane 🤲

---
**Version:** 1.3.0
