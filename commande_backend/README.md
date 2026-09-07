# Backend commande AdhanBox

Petites fonctions serverless (Vercel, région Paris `cdg1`) qui remplacent le
Payment Link « brut » : le client choisit sa configuration **une seule fois**
sur `adhanbox.fr/personnaliser.html`, et elle est visible partout.

## Endpoints

| Endpoint | Rôle |
|---|---|
| `POST /api/checkout` | Crée une session Stripe Checkout. Corps : `{ finish, mandala, mandalaColor }` (validés côté serveur, prix fixé côté serveur). La config part dans le **nom de l'article** + **métadonnées** (visibles dashboard + reçu). |
| `POST /api/stripe-webhook` | Sur paiement réussi : email de confirmation personnalisé au client + notification « nouvelle commande » à `contact@adhanbox.fr` (via Resend). |
| `POST /api/review` | Dépôt d'un avis depuis `adhanbox.fr/avis.html`. Corps : `{ note, texte, prenom, ville, email?, hp? }`. Stocké **en attente** dans Vercel Blob (`reviews/pending/{id}.json`) + notif email avec liens Approuver / Rejeter. Aucun email ni IP stocké. Badge « acheteur vérifié » si l'email correspond à un client Stripe. `hp` = piège à bots. |
| `GET /api/reviews` | Liste des avis **approuvés** (`reviews/approved/*.json`), triés du plus récent au plus ancien : `{ count, average, reviews[] }`. Mis en cache CDN 5 min. Consommé par `avis.html` et la section témoignages de la home. |
| `GET /api/review-moderate?id&action=approve\|reject&token` | Cible des liens de l'email de notif. Approuver déplace l'avis vers `reviews/approved/`, Rejeter le supprime. Protégé par `REVIEW_ADMIN_TOKEN`. Renvoie une page HTML de confirmation. |
| `GET /api/order-step?ref&step&token` | Envoie au client l'email de l'étape (`preparation`, `montage`, `expedition`, `avis`). Cliqué depuis l'email de notification. Idempotent grâce à une trace Blob `orders/{ref}/{step}.json`. Protégé par `ORDER_ADMIN_TOKEN` (repli : `REVIEW_ADMIN_TOKEN`). |
| `GET /api/cron-avis` | Tâche quotidienne (09:00, `vercel.json`) : envoie « Avis et photo » dix jours après « Expédiée ». `?dry=1` montre ce qui partirait. Protégé par `Authorization: Bearer CRON_SECRET`. |

### Système d'avis — stockage

Les avis vivent dans un **store Vercel Blob** connecté au projet (Vercel → Storage
→ Create/Connect Blob store → variable `BLOB_READ_WRITE_TOKEN` injectée
automatiquement). Un fichier JSON par avis, sans donnée personnelle :
`reviews/pending/{id}.json` (en attente) puis `reviews/approved/{id}.json` (publié).
Modération = un simple clic dans l'email de notification.

### Traces de commande — sans donnée personnelle

Le store est **public** (mode fixé à sa création, non modifiable) et les chemins
`orders/{ref}/{step}.json` sont prévisibles. Ces traces ne servent qu'à
l'idempotence : elles ne contiennent que `step`, `ref`, `sentAt` et, pour
l'expédition, `carrier`. **Jamais** d'email, de prénom, de configuration ni de
numéro de suivi. `cron-avis` retrouve le client chez Stripe pour le lot du jour,
et réécrit épurée toute trace qui porterait encore ces champs (traces antérieures
au 07/09/2026) — le compte apparaît dans sa réponse (`nettoyage`).

## Variables d'environnement (Vercel → Settings → Environment Variables)

| Variable | Obligatoire | Rôle |
|---|---|---|
| `STRIPE_SECRET_KEY` | ✅ | Clé secrète Stripe (`sk_live_…`) — dashboard Stripe → Développeurs → Clés API |
| `STRIPE_WEBHOOK_SECRET` | ✅ (webhook) | Secret `whsec_…` de l'endpoint webhook créé dans Stripe |
| `RESEND_API_KEY` | pour les emails | Clé API Resend. Absente → emails sautés, paiement OK quand même |
| `FROM_EMAIL` | non | Expéditeur, défaut `AdhanBox <commande@adhanbox.fr>` (domaine à vérifier chez Resend). Avant vérification : `AdhanBox <onboarding@resend.dev>` |
| `NOTIF_EMAIL` | non | Destinataire notif vendeur, défaut `contact@adhanbox.fr` |
| `SHIP_DATE` | non | Défaut `sous 1 à 2 semaines` |
| `AMOUNT_CENTS` | non | Prix en centimes, défaut `9500` (offre de lancement 95 €) |
| `SITE_URL` | non | Défaut `https://adhanbox.fr` |
| `BLOB_READ_WRITE_TOKEN` | ✅ (avis) | Injecté auto quand un store Vercel Blob est connecté au projet. Sans lui, `/api/review` et `/api/reviews` échouent. |
| `REVIEW_ADMIN_TOKEN` | ✅ (avis) | Secret partagé qui protège les liens Approuver/Rejeter. À définir (chaîne longue aléatoire). Sans lui, aucune notif d'avis n'est envoyée et la modération refuse tout. |
| `ORDER_ADMIN_TOKEN` | non | Secret des liens d'étape de commande. Absent → `REVIEW_ADMIN_TOKEN` est utilisé. |
| `CRON_SECRET` | ✅ (cron) | Vercel l'envoie en `Authorization: Bearer` à `/api/cron-avis`. Sans lui, la tâche refuse tout. |
| `AVIS_DELAI_JOURS` | non | Délai entre « Expédiée » et « Avis et photo », défaut `10`. |
| `BACKEND_URL` | non | Base publique de ce backend pour les liens de modération, défaut `https://adhanbox-commande.vercel.app` |

## Webhook Stripe à créer (dashboard → Développeurs → Webhooks)

- URL : `https://adhanbox-commande.vercel.app/api/stripe-webhook`
- Événements : `checkout.session.completed` **et** `checkout.session.async_payment_succeeded`

## Déploiement

```bash
cd commande_backend
vercel deploy --prod
```

## Côté site (docs/configurator.js)

`CHECKOUT_BACKEND` pointe vers ce déploiement. Si le backend échoue, le bouton
retombe automatiquement sur le Payment Link Stripe (qui garde ses champs
personnalisés obligatoires → la config est capturée dans tous les cas).
