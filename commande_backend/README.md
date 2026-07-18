# Backend commande AdhanBox

Petites fonctions serverless (Vercel, région Paris `cdg1`) qui remplacent le
Payment Link « brut » : le client choisit sa configuration **une seule fois**
sur `adhanbox.fr/personnaliser.html`, et elle est visible partout.

## Endpoints

| Endpoint | Rôle |
|---|---|
| `POST /api/checkout` | Crée une session Stripe Checkout. Corps : `{ finish, mandala, mandalaColor }` (validés côté serveur, prix fixé côté serveur). La config part dans le **nom de l'article** + **métadonnées** (visibles dashboard + reçu). |
| `POST /api/stripe-webhook` | Sur paiement réussi : email de confirmation personnalisé au client + notification « nouvelle commande » à `contact@adhanbox.fr` (via Resend). |

## Variables d'environnement (Vercel → Settings → Environment Variables)

| Variable | Obligatoire | Rôle |
|---|---|---|
| `STRIPE_SECRET_KEY` | ✅ | Clé secrète Stripe (`sk_live_…`) — dashboard Stripe → Développeurs → Clés API |
| `STRIPE_WEBHOOK_SECRET` | ✅ (webhook) | Secret `whsec_…` de l'endpoint webhook créé dans Stripe |
| `RESEND_API_KEY` | pour les emails | Clé API Resend. Absente → emails sautés, paiement OK quand même |
| `FROM_EMAIL` | non | Expéditeur, défaut `AdhanBox <commande@adhanbox.fr>` (domaine à vérifier chez Resend). Avant vérification : `AdhanBox <onboarding@resend.dev>` |
| `NOTIF_EMAIL` | non | Destinataire notif vendeur, défaut `contact@adhanbox.fr` |
| `SHIP_DATE` | non | Défaut `automne 2026` |
| `AMOUNT_CENTS` | non | Prix en centimes, défaut `9500` (offre de lancement 95 €) |
| `SITE_URL` | non | Défaut `https://adhanbox.fr` |

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
