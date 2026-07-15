# Fiche Google Play Store — AdhanBox

> Tout est prêt à copier-coller dans la Play Console.
> Application : **AdhanBox : Appel à la prière** — `com.adhanbox.app`
> Chaque section correspond à un écran de la Play Console (Développement de l'app → Fiche du Play Store principale, Classification du contenu, Sécurité des données).

---

## 1. Fiche du Play Store principale

### Nom de l'application (max 30 caractères)
```
AdhanBox : Appel à la prière
```
*(28 caractères — déjà en place)*

### Description courte (max 80 caractères)
```
Pilotez votre boîtier AdhanBox : adhan, horaires de prière, Coran et azkar.
```
*(75 caractères)*

**Variante possible :**
```
L'app compagnon de votre boîtier AdhanBox : prière, adhan, Coran, ambiance.
```

### Description complète (max 4000 caractères)
```
AdhanBox, c'est le rappel de la prière chez vous — sans écran intrusif, sans notification qui dérange. Cette application est le compagnon de votre boîtier AdhanBox : elle le configure, le pilote et l'enrichit, où que vous soyez dans la maison.

⚠️ Cette application nécessite un boîtier AdhanBox pour fonctionner pleinement.

🕌 HORAIRES DE PRIÈRE PRÉCIS
Les cinq horaires (Fajr, Dhuhr, Asr, Maghrib, Isha) sont calculés selon votre localisation. Vous pouvez aligner les horaires sur ceux de votre mosquée pour être toujours en accord avec votre communauté.

🔊 L'ADHAN AU BON MOMENT
Le boîtier lance automatiquement l'appel à la prière à l'heure. Choisissez le récitateur, réglez le volume, et laissez l'adhan résonner comme à la mosquée.

📖 CORAN & AZKAR
Écoutez le Saint Coran — 114 sourates par 4 récitateurs — ainsi que les azkar du matin et du soir, directement diffusés par votre boîtier.

💡 UNE AMBIANCE APAISANTE
Réglez la lumière de votre AdhanBox : intensité, couleur et scénarios lumineux pour une atmosphère sereine, notamment aux heures de prière.

📱 SIMPLE ET FAMILIAL
Appairage du boîtier en quelques secondes sur votre Wi-Fi. Toute la famille peut piloter l'appareil depuis son téléphone, à la maison. Interface claire, en français, pensée pour tous les âges.

🔄 MISES À JOUR À VIE
Votre boîtier reçoit régulièrement des améliorations à distance. Vous profitez des nouveautés sans rien faire.

🔒 RESPECT DE VOTRE VIE PRIVÉE
Pas de publicité, pas de traceur, pas de revente de données. La localisation sert uniquement à calculer vos horaires de prière.

AdhanBox est un objet artisanal, fabriqué en France, pensé pour ramener un instant de spiritualité au cœur du foyer. Cinq fois par jour, un rappel doux et lumineux.

Découvrez le boîtier sur adhanbox.fr
```
*(≈ 1 750 caractères)*

---

## 2. Détails de la fiche

| Champ | Valeur à saisir |
|---|---|
| **Catégorie de l'application** | Mode de vie |
| **Tags** (jusqu'à 5, choisis dans la liste Google) | Islam / Religion / Style de vie / Musique et audio / Maison connectée |
| **Adresse e-mail** | contact@adhanbox.fr |
| **Site Web** | https://adhanbox.fr |
| **Téléphone** | (facultatif — laisser vide si non souhaité) |
| **Règles de confidentialité (URL)** | https://adhanbox.fr/privacy.html |

> ✅ Vérifier que **https://adhanbox.fr/privacy.html** s'ouvre bien avant de valider.

---

## 3. Ressources graphiques (déjà prêtes ✅)

| Ressource | Fichier dans le repo | Dimensions | Statut |
|---|---|---|---|
| Icône de l'app | `store_assets/google_play/icon.png` | 512×512 | ✅ conforme |
| Image de présentation (feature graphic) | `store_assets/google_play/feature_graphic_1024x500_1.png` | 1024×500 | ✅ conforme |
| Captures téléphone (×5) | `store_assets/screenshots/01_adhan → 05_leds.png` | 1242×2688 | ✅ conformes (min. 2 requises) |
| Captures tablette 7"/10" (×3) | `store_assets/screenshots_ipad/*.png` | 2048×2732 | ✅ conformes |

Ordre conseillé des captures téléphone : **01_adhan → 02_horaires → 03_volume → 05_leds → 04_setup**
(on met les fonctions « vitrine » d'abord, l'installation à la fin).

---

## 4. Classification du contenu (questionnaire IARC)

Rubrique **Politique → Classification du contenu → Démarrer le questionnaire**.

- **Catégorie** : Utilitaire, productivité, communication ou autre → *« Autre »* (ou « Référence »).
- Violence : **Non**
- Contenu sexuel : **Non**
- Grossièretés : **Non**
- Drogues / alcool / tabac : **Non**
- Jeux d'argent / hasard : **Non**
- Contenu généré par les utilisateurs / partage social : **Non**
- Localisation partagée avec d'autres utilisateurs : **Non**
- Achats numériques : **Non**

➡️ Résultat attendu : **Tous publics / PEGI 3 / ESRB Everyone**.
Répondre honnêtement « Non » à tout — l'app ne contient que du contenu religieux (audio) sans élément sensible.

---

## 5. Sécurité des données (Data safety)

Rubrique **Politique → Sécurité des données**. Voici les réponses recommandées, basées sur le code de l'app (aucun analytics/traceur ; localisation utilisée pour les horaires ; stockage local).

**Votre application collecte-t-elle des données utilisateur ?** → **Oui** (la localisation).

### Données collectées
| Type de données | Collectée ? | Partagée ? | Obligatoire ? | Finalité |
|---|---|---|---|---|
| **Position approximative** | Oui | Non | Facultative | Fonctionnalité de l'app (calcul des horaires de prière) |
| **Position précise** | Oui | Non | Facultative | Fonctionnalité de l'app (calcul des horaires de prière) |

> Rien d'autre : ni nom, ni e-mail, ni identifiants, ni contacts, ni photos, ni activité in-app envoyés à un serveur. Aucune donnée à des fins publicitaires.

### Questions de sécurité
- **Les données sont-elles chiffrées en transit ?** → **Oui** (appels en HTTPS vers les fournisseurs d'horaires).
- **L'utilisateur peut-il demander la suppression de ses données ?** → **Oui** — via contact@adhanbox.fr. (La localisation n'est pas stockée durablement côté serveur ; la demande de suppression est proposée par courtoisie.)
- **Collecte conforme à une politique de confidentialité ?** → **Oui** (https://adhanbox.fr/privacy.html).

> ⚠️ À CONFIRMER PAR TOI : ces réponses reflètent le comportement observé dans le code (localisation → API d'horaires mawaqit / ip-api, aucun traceur). Si tu ajoutes plus tard un analytics, un login, ou un paiement in-app, il faudra mettre à jour cette section.

---

## 6. Autres sections à vérifier avant publication

- [ ] **Public cible et contenu** : sélectionner une tranche d'âge **adulte / 13+** (ou « tous » selon ton choix), app **non destinée aux enfants**.
- [ ] **Appli gouvernementale** : Non.
- [ ] **Publicités** : déclarer **« Cette application ne contient pas de publicité »**.
- [ ] **Accès à l'application** : si certaines fonctions exigent le boîtier, l'indiquer dans « Toutes les fonctionnalités sont accessibles sans identifiants » ou fournir une note pour les évaluateurs Google (voir §7).
- [ ] **Coordonnées du développeur** : adresse (14 rue du Corps Franc Pommiès, 65500 Vic-en-Bigorre), e-mail contact@adhanbox.fr.

---

## 7. Note pour les évaluateurs Google (champ « Accès à l'application »)

Comme l'app pilote un objet physique, ajoute cette note pour éviter un rejet « fonctionnalité non testable » :

```
AdhanBox est l'application compagnon d'un boîtier matériel (appareil Wi-Fi
AdhanBox). Certaines fonctions (lecture de l'adhan, du Coran, contrôle des
LED) nécessitent un boîtier physique connecté au même réseau Wi-Fi.
Sans boîtier, l'application reste navigable : horaires de prière, réglages
et écrans de configuration sont visibles. Aucun identifiant n'est requis
pour ouvrir l'application.
```

---

## Récapitulatif — ce qu'il reste à faire dans la Play Console
1. Coller nom / description courte / description complète (§1).
2. Renseigner catégorie, tags, contacts, URL confidentialité (§2).
3. Uploader icône, feature graphic, captures (§3) — fichiers déjà prêts.
4. Remplir le questionnaire de classification (§4).
5. Remplir la Sécurité des données (§5).
6. Cocher les sections annexes (§6) + note évaluateurs (§7).

Une fois l'accès production accordé par Google → uploader l'AAB signé et envoyer pour examen.
