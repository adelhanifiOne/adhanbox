# Demande d'autorisation à Mawaqit

Rédigé le 13/09/2026. **À envoyer à support@mawaqit.net.**

## Ce qu'il faut savoir avant d'envoyer

Leur page d'aide « Puis-je utiliser votre API ? » dit noir sur blanc : *« Our API
is currently private and not publicly available »*, et invite à les contacter.
Leurs mentions légales exigent une **autorisation écrite préalable** pour toute
réutilisation. Ils sont une association (MAWAQIT ASSO, 66 avenue des
Champs-Élysées, 75008 Paris).

Le mail ci-dessous **dit ce que fait la box aujourd'hui**, sans rien cacher.
C'est le seul angle tenable : ils peuvent le constater en dix minutes, et être
devancé serait bien pire que de le dire soi-même.

**Deux choses à faire avant de l'envoyer :**

1. Corriger la vérification du certificat TLS dans le firmware
   (`client.setInsecure()` dans `performMawaqitSync`). Qu'ils ne trouvent pas un
   défaut de sécurité en regardant le produit de près.
2. Remplacer `[NOMBRE]` par le nombre réel de boîtiers en service.

---

## Objet

> Demande d'autorisation d'accès aux horaires — AdhanBox, boîtier artisanal français

## Corps du message

> As-salāmu ʿalaykum wa rahmatullah,
>
> Je m'appelle Adel Hanifi, je suis artisan fabricant en France, à Vic-en-Bigorre
> dans les Hautes-Pyrénées. Je conçois et j'assemble à la main un petit boîtier,
> l'AdhanBox, qui diffuse l'appel à la prière à la maison — à l'heure exacte de
> la mosquée que la famille a choisie.
>
> Je vous écris pour deux raisons : vous dire précisément ce que fait mon
> appareil aujourd'hui, et vous demander l'autorisation de continuer, dans les
> conditions qui vous conviendront.
>
> **Ce que fait le boîtier aujourd'hui**
>
> Lors de l'installation, le client choisit sa mosquée dans mon application.
> Ensuite, une fois par jour environ — une requête toutes les vingt heures — le
> boîtier interroge `mawaqit.net/api/2.0/mosque/search` pour retrouver cette
> mosquée et en lire les horaires du jour. Les requêtes portent l'en-tête
> `User-Agent: AdhanBox/1.0`, elles sont donc identifiables dans vos journaux.
> Quand vos serveurs ne répondent pas, l'appareil bascule sur un calcul
> astronomique local, afin de ne jamais laisser une famille sans appel.
>
> J'ai découvert en lisant votre centre d'aide que cette API est privée. Je ne
> l'utilise pas pour contourner quoi que ce soit : je n'avais pas vu qu'un autre
> chemin existait, et j'aurais dû vous écrire avant. Je le fais maintenant,
> plutôt que d'attendre que vous le découvriez.
>
> Le parc est aujourd'hui de [NOMBRE] boîtiers. C'est modeste, et c'est justement
> le bon moment pour mettre les choses au propre.
>
> **Ce que je vous demande**
>
> Votre centre d'aide mentionne une adresse d'horaires dédiée par mosquée. Mon
> besoin est proche, mais porte sur **la mosquée que le client choisit**, et non
> sur une seule : chaque famille suit la sienne. Existe-t-il un accès qui
> corresponde à cet usage — une clé, un point d'accès dédié, un quota ? Je
> m'adapterai à ce que vous proposerez, y compris si cela demande de réécrire
> cette partie du logiciel.
>
> **Ce que je vous propose en retour**
>
> Vous rendez ce service gratuitement aux mosquées, en grande partie grâce à des
> bénévoles. Mon produit est vendu, et il vit de votre travail : il me paraît
> juste d'y contribuer. Je vous propose donc :
>
> - une contribution financière pour chaque boîtier vendu, ou un versement
>   annuel — le montant, je vous laisse me dire ce qui a du sens pour vous ;
> - la mention « Horaires fournis par Mawaqit » de façon visible dans
>   l'application, sur le site adhanbox.fr et dans la notice papier, avec un lien
>   vers vous ;
> - un boîtier offert à votre équipe, avec plaisir, si vous souhaitez le voir.
>
> Si vous préférez que je cesse d'utiliser vos serveurs, dites-le-moi simplement
> et je le ferai. Je préfère mille fois une réponse claire, même négative, qu'un
> usage que vous n'auriez pas choisi.
>
> Je reste à votre disposition pour tout détail technique, et je peux vous
> envoyer le dossier technique du produit si cela vous est utile.
>
> BarakAllahu fikoum pour ce que vous faites.
>
> Fraternellement,
>
> Adel Hanifi
> AdhanBox — fabriqué à la main en France
> 14 rue du Corps Franc Pommiès, 65500 Vic-en-Bigorre
> SIRET 932 355 589 00023
> contact@adhanbox.fr — adhanbox.fr

---

## Si la réponse est négative

Le repli astronomique existe déjà dans le firmware et fonctionne. Il faudra
alors :

- retirer la mention Mawaqit de l'application, du site et de la notice ;
- prévenir les clients dont la mosquée était suivie, honnêtement : les horaires
  deviendront calculés et non plus ceux de leur mosquée ;
- chercher une autre source d'horaires de mosquée, ou proposer au client de
  saisir lui-même les horaires affichés dans sa mosquée.

Ce dernier point est peut-être la meilleure porte de sortie : il rend le produit
indépendant de tout tiers, au prix d'une saisie à l'installation.
