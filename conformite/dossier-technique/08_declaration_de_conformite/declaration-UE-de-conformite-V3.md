# DÉCLARATION UE DE CONFORMITÉ — modèle ADHBX-V3

*(Déclaration distincte du modèle ADHBX-V2. Le module radio est identique ;
les différences portent sur l'horloge temps réel, la pile de sauvegarde et
la prise en compte des exigences de cybersécurité de la RED.
À imprimer, dater, signer. Conserver dix ans.)*

**Référence de la déclaration :** DOC-ADHBX-V3-2026-01

---

**1. Produit (identification permettant la traçabilité)**

Boîtier d'appel à la prière connecté « **AdhanBox** »
Modèle : **ADHBX-V3**
Numéros de série : **AB3-0001** et suivants
Version matérielle : carte AdhanBoxPCBV3
Version de micrologiciel à la mise sur le marché : **3.0.5**

**2. Nom et adresse du fabricant**

Adel Hanifi — Entrepreneur Individuel, sous l'enseigne AdhanBox
14 rue du Corps Franc Pommiès, 65500 Vic-en-Bigorre, France
SIRET : 932 355 589 00023
contact@adhanbox.fr — adhanbox.fr

**3.** La présente déclaration de conformité est établie sous la seule
responsabilité du fabricant.

**4. Objet de la déclaration**

Appareil de diffusion audio et de lumière d'ambiance à usage domestique
intérieur, communiquant en Wi-Fi 2,4 GHz et Bluetooth Low Energy, alimenté
en 5 V ⎓ par connecteur USB-C. Il comporte une pile bouton lithium CR1225
non rechargeable, interne et non accessible sans outil, dédiée à la seule
sauvegarde de l'horloge temps réel.

**5. L'objet de la déclaration décrit ci-dessus est conforme à la
législation d'harmonisation de l'Union applicable :**

- **Directive 2014/53/UE** (RED — équipements radioélectriques), y compris
  les exigences des articles 3.3(d) et 3.3(e) rendues applicables par le
  règlement délégué (UE) 2022/30 depuis le 1er août 2025
- **Directive 2011/65/UE** modifiée par (UE) 2015/863 (RoHS)

**6. Références des normes harmonisées appliquées**

| Exigence essentielle (2014/53/UE) | Norme appliquée |
|---|---|
| Art. 3.1(a) — Santé, exposition RF | **EN 50665:2017** |
| Art. 3.1(a) — Sécurité | **EN IEC 62368-1:2020 + A11:2020** |
| Art. 3.1(b) — Compatibilité électromagnétique | **ETSI EN 301 489-1 V2.2.3** et **ETSI EN 301 489-17 V3.2.4** |
| Art. 3.2 — Utilisation efficace du spectre | **ETSI EN 300 328 V2.2.2** |
| Art. 3.3(d) — Résilience du réseau | **EN 18031-1:2024** |
| Art. 3.3(e) — Protection des données personnelles | **EN 18031-2:2024** |
| RoHS — documentation technique | **EN IEC 63000:2018** |

L'article 3.3(f) (protection contre la fraude aux transactions monétaires)
n'est pas applicable : l'appareil ne réalise ni ne facilite aucun paiement.

**7. Organisme notifié**

Le module radio intégré **Espressif ESP32-S3-WROOM-1** a fait l'objet d'un
**certificat d'examen UE de type** (annexe III, module B de la directive
2014/53/UE) délivré le **26 janvier 2022** par :

> **Eurofins Electrical and Electronic Testing NA, Inc.**
> Organisme notifié n° **0980**

Ce certificat couvre les exigences des articles 3.1 et 3.2 pour le module.
Il est **antérieur** à l'entrée en application des exigences de
cybersécurité : la conformité aux articles 3.3(d) et 3.3(e) relève de
l'évaluation du produit fini par le fabricant, documentée au point 9 et
en pièce 05 du dossier technique.

**8. Caractéristiques radio**

- Wi-Fi : 2412 – 2472 MHz — puissance maximale **19,9 dBm EIRP**
- Bluetooth LE : 2402 – 2480 MHz — puissance maximale **10 dBm EIRP**
- L'antenne PCB d'origine du module (gain 3,26 dBi) n'est ni modifiée ni
  remplacée ; les règles d'intégration publiées par Espressif sont
  respectées (zone d'exclusion de cuivre sous l'antenne, module placé en
  bord de carte).

**9. Mesures répondant aux exigences de cybersécurité (art. 3.3(d) et (e))**

| Exigence | Mesure mise en œuvre |
|---|---|
| Contrôle d'accès à l'interface locale | Jeton d'authentification **généré aléatoirement par appareil** à la première mise en service ; aucune valeur par défaut commune à la série |
| Mise à jour du micrologiciel | Mot de passe OTA **distinct par appareil** ; **signature cryptographique ECDSA** vérifiée avant écriture — tout micrologiciel non signé par la clé du fabricant est rejeté |
| Protection des données personnelles | Aucune donnée personnelle transmise ni stockée sur les serveurs du fabricant ; horaires, position et réglages restent sur l'appareil et dans l'application |
| Identifiants du réseau de l'utilisateur | Le SSID et la clé Wi-Fi sont fournis par appairage Bluetooth Low Energy local, stockés chiffrés en mémoire non volatile, jamais transmis à un tiers |
| Résilience du réseau | L'appareil n'expose aucun service accessible depuis Internet, n'accepte aucune connexion entrante hors du réseau local et ne relaie aucun trafic |
| Traitement des vulnérabilités | Procédure documentée en pièce 09 du dossier technique ; contact de sécurité publié : contact@adhanbox.fr |

**10. Informations complémentaires**

- **Adaptateur secteur** : il n'est pas partie intégrante du produit.
  Lorsqu'il est fourni, il porte son propre marquage CE et sa propre
  déclaration de conformité.
- **Pile de sauvegarde** : pile bouton lithium **CR1225** du commerce,
  non rechargeable, jamais rechargée par le circuit (diode d'aiguillage
  BAT54C). Le marquage CE et le symbole de collecte séparée exigés par le
  règlement (UE) 2023/1542 sont portés par le fabricant de la cellule.
  La pile est retirable et remplaçable par l'utilisateur final au moyen
  d'un tournevis cruciforme courant, conformément à l'article 11 dudit
  règlement (applicable au 18 février 2027).
- **Dossier technique** : constitué et conservé par le fabricant pendant
  dix ans à compter de la dernière mise sur le marché, tenu à la
  disposition des autorités de surveillance du marché (DGCCRF, ANFR).
- **Déclaration publiée** : https://adhanbox.fr/conformite.html

---

Signé par et au nom de : **Adel Hanifi**, fabricant

Fait à Vic-en-Bigorre, le ____ / ____ / ________

Signature : ______________________
