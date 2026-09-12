# Poser une AdhanBox à la mosquée — marche à suivre

Le fidèle scanne un QR code posé à côté de la boîte. Son téléphone ouvre
`adhanbox.fr/mosquee.html`, il touche un bouton, la boîte répond devant lui.
Puis il voit « commander la mienne », avec le code RENTREE10.

**Son téléphone reste sur sa propre connexion.** C'est pour cela qu'on ne fait
pas de point d'accès Wi-Fi sur la boîte : s'il devait se connecter à la boîte,
il perdrait internet, et les boutons Instagram, TikTok et « commander » ne
marcheraient plus — c'est-à-dire tout ce qui rapporte. La boîte est sur le
Wi-Fi de la mosquée, le téléphone sur la 4G, et un serveur public au milieu
transmet les ordres.

Il te faut : le Wi-Fi de la mosquée, le firmware **3.0.30** sur la boîte de
démonstration, et une impression A5.

---

## 1. Chez toi, avant de partir

**a. Mets la boîte en 3.0.30.** Par l'application, « Mettre à jour par le
réseau ». Les versions antérieures n'ont pas le mode démonstration.

**b. Relève l'identifiant de la carte.** Application, page *À propos* — douze
caractères, par exemple `b0937af61b44`. C'est lui qui relie le QR à CETTE
boîte, et à elle seule.

**c. Connecte la boîte au Wi-Fi de la mosquée.** Si tu as le mot de passe,
fais-le maintenant : sur place tu n'auras peut-être ni le temps ni le réseau.
L'application le fait, ou le point d'accès de configuration.

**d. Allume le mode démonstration.** Sur ton réseau, la boîte joignable :

```bash
curl -X POST http://adhanbox.local/api/mosquee \
  -H "X-API-Key: TON_JETON" -H "Content-Type: application/json" \
  -d '{"actif":true,"broker":"broker.hivemq.com","volume_max":18,"delai_s":45,"avant_priere_min":5,"apres_priere_min":20}'
```

La réponse te redonne tout, avec `device_id` et `prefixe` : c'est la preuve que
c'est bien pris. Vérifie que `connecte` passe à `true` dans les secondes qui
suivent.

**e. Imprime l'affiche AVEC l'identifiant.** Ouvre dans Chrome :

```
store_assets/marketing/affiche-mosquee-demo.html?id=B0937AF61B44
```

en remplaçant par ton identifiant, puis Imprimer, format A5, marges *aucune*.
Une seule page.

Le fichier `affiche-mosquee-demo-EXEMPLE.pdf` du dépôt est **un exemple** gravé
sur une autre carte : ne l'imprime pas tel quel, son QR ne pilotera pas ta
boîte. Sans identifiant dans l'adresse, l'affiche imprime volontairement un QR
mort et te prévient en rouge à l'écran — plutôt qu'un QR qui mènerait nulle part
devant les fidèles.

**f. Scanne ton propre QR avant de partir**, avec ton téléphone en 4G, Wi-Fi
coupé. Tu dois voir « Prête — à vous de jouer » et la boîte doit répondre. Si
tu ne testes qu'une chose, c'est celle-là.

---

## 2. Sur place

Branche, attends que la boîte retrouve le Wi-Fi, pose l'affiche à côté.
Reteste une fois depuis ton téléphone.

Préviens l'imam, et dis-lui ces deux choses : le volume est plafonné, et la
boîte **refuse de jouer autour des heures de prière** — cinq minutes avant,
vingt minutes après. Personne ne pourra lancer un adhan pendant l'appel du
muezzin. C'est ce qui fait la différence entre un objet qu'on tolère et un
objet qu'on laisse.

---

## 3. Les garde-fous

Ils sont **dans le firmware**, pas dans la page web : une page se contourne en
ouvrant les outils du navigateur, un boîtier non.

| garde-fou | par défaut | règle |
|---|---|---|
| volume plafonné | 18 / 30 | `volume_max` |
| délai entre deux déclenchements | 45 s | `delai_s` |
| silence avant la prière | 5 min | `avant_priere_min` |
| silence après la prière | 20 min | `apres_priere_min` |

Quand la boîte refuse, elle le dit, et la page l'affiche au fidèle, mot pour
mot : « ⏸ patientez 12 s », « ⏸ la priere approche », « ⏸ priere en cours ».
Il comprend, il attend, il ne croit pas que c'est cassé.

Pour ajuster sur place, refais l'appel du **1.d** avec d'autres valeurs. Le
volume est aussi plafonné à la source : même un ordre de volume 30 est ramené
au plafond.

---

## 4. Quand la démonstration est finie — à ne pas oublier

```bash
curl -X POST http://adhanbox.local/api/mosquee \
  -H "X-API-Key: TON_JETON" -H "Content-Type: application/json" \
  -d '{"actif":false}'
```

**Pourquoi c'est important.** Tous ceux qui ont scanné le QR connaissent
l'identifiant de la carte. Tant que la boîte est reliée au serveur public, ils
peuvent la piloter de n'importe où dans le monde — y compris une fois rentrée
chez toi. Cet appel coupe la démonstration *et* efface le serveur : plus
personne ne peut rien envoyer. C'est un seul geste, fais-le le soir même.

Vérifie ensuite que `broker` est vide et `connecte` à `false` :

```bash
curl -H "X-API-Key: TON_JETON" http://adhanbox.local/api/mosquee
```

---

## Ce que ça vaut

Le serveur utilisé est le broker public de HiveMQ : gratuit, sans compte, mais
sans garantie. Les sujets contiennent l'identifiant de la carte, donc les autres
boîtes ne bougent pas et personne ne devine les sujets au hasard — mais ce n'est
pas un secret : c'est une démonstration surveillée, pas une installation
permanente. Pour une pose longue durée, il faudrait un serveur à toi, avec mot
de passe. Dis-le-moi le jour où ça se présente.
