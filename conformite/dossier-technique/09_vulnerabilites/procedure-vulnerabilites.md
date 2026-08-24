# Procédure de traitement des vulnérabilités — pièce 09

**Produit concerné :** AdhanBox (ADHBX-V2, ADHBX-V3) et son application
compagnon.
**Fabricant :** Adel Hanifi — AdhanBox, 14 rue du Corps Franc Pommiès,
65500 Vic-en-Bigorre, France.
**Établie en :** août 2026. **Rédacteur :** Adel Hanifi.

## Pourquoi ce document

Deux textes l'imposent :

- la **directive 2014/53/UE**, articles 3.3(d) et 3.3(e), applicables
  depuis le 1er août 2025 — un équipement radio connecté doit disposer
  d'un mécanisme de traitement des failles ;
- le **règlement (UE) 2024/2847** (Cyber Resilience Act), dont les
  obligations de **signalement** s'appliquent au **11 septembre 2026**.
  Les obligations complètes (conception sécurisée, SBOM, documentation)
  suivent au 11 décembre 2027.

## 1. Point de contact sécurité

Une seule adresse, publiée sur adhanbox.fr et dans la notice :

> **contact@adhanbox.fr** — objet commençant par `[SECURITE]`

Toute personne, cliente ou non, peut signaler une faille. Aucune poursuite
ne sera engagée contre un signalement de bonne foi qui n'a pas exploité la
faille au-delà de ce qui est nécessaire à sa démonstration, ni exfiltré ni
divulgué de données.

Accusé de réception sous **72 heures ouvrées**.

## 2. Qualification

À réception, la faille est qualifiée sous 5 jours ouvrés :

| Niveau | Définition | Délai de correctif visé |
|---|---|---|
| **Critique** | Prise de contrôle à distance, contournement de la signature du micrologiciel, fuite de données personnelles | **7 jours** |
| **Élevé** | Contournement de l'authentification locale, déni de service persistant | 30 jours |
| **Modéré** | Faille exploitable seulement depuis le réseau local avec accès physique préalable | 90 jours |
| **Faible** | Défaut de robustesse sans impact démontré | Prochaine version |

## 3. Obligation de signalement (CRA, à partir du 11/09/2026)

Elle ne se déclenche que dans deux cas : **vulnérabilité activement
exploitée**, ou **incident grave affectant la sécurité du produit**.
Une faille signalée mais non exploitée n'est pas à déclarer.

Le signalement se fait via la **plateforme unique de l'ENISA**, en trois
temps :

| Étape | Délai à compter de la connaissance | Contenu |
|---|---|---|
| Alerte précoce | **24 heures** | Nature du fait, États membres potentiellement concernés |
| Notification complète | **72 heures** | Description, gravité, impact, mesures correctives engagées |
| Rapport final | **14 jours** après disponibilité du correctif (1 mois pour un incident grave) | Cause racine, correctif, mesures d'atténuation |

Les utilisateurs concernés sont informés en parallèle par courriel et par
une notice dans l'application.

## 4. Diffusion du correctif

Le correctif est diffusé par **mise à jour OTA signée ECDSA**. Un
micrologiciel dont la signature ne correspond pas à la clé du fabricant est
refusé par l'appareil : c'est la mesure qui rend la voie de mise à jour
elle-même non exploitable.

Les trois canaux (V1, V2, V3) sont **distincts et ne doivent jamais être
croisés** : publier un binaire V2 sur le canal V3 briquerait les appareils
déployés. La clé privée de signature est conservée hors du dépôt, et sa
perte rendrait impossible toute mise à jour ultérieure du parc : sa
sauvegarde fait partie intégrante de la présente procédure.

## 5. Durée du support

Les correctifs de sécurité sont fournis pendant **cinq ans à compter de la
livraison** de chaque appareil, durée annoncée au consommateur dans les CGV
(section 10) au titre des obligations applicables aux biens comportant des
éléments numériques.

## 6. Registre

Chaque signalement est consigné dans `registre-vulnerabilites.md` (même
dossier) : date de réception, source, description, qualification, décision
de déclaration ou non, date et version du correctif, date d'information des
utilisateurs. Ce registre est présenté sur demande aux autorités de
surveillance du marché.

## 7. Surface d'attaque connue

Recensée pour orienter la veille :

| Élément | Exposition | Contrôle en place |
|---|---|---|
| Serveur HTTP embarqué | Réseau local uniquement | Jeton par appareil, aucune valeur par défaut partagée |
| Appairage Bluetooth LE | Portée radio, à la mise en service | Fenêtre d'appairage limitée dans le temps |
| Mise à jour OTA | Réseau local | Mot de passe par appareil + signature ECDSA |
| Carte microSD | Accès physique, boîtier ouvert | Hors modèle de menace : suppose le démontage |
| Dépendances tierces | ESP-IDF/Arduino, Adafruit_NeoPixel, bibliothèques audio | Veille sur les avis Espressif ; à formaliser en SBOM avant le 11/12/2027 |
