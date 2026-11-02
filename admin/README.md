# Back-office ivia (`admin/`)

Next.js 16 (App Router), React 19, TypeScript strict, Tailwind 4 — [ADR 0003](../docs/decisions/0003-back-office-nextjs.md).
Charte : [`docs/DESIGN.md`](../docs/DESIGN.md) (barre latérale Berkeley, Parkinsans, statuts avec icône).

## Démarrer

Prérequis : Node 20.9+ (Node 24 LTS en CI et en production), pnpm 10, et l'API lancée en local
(voir le [README](../README.md) : `APP_ENV=local`, `go run ./cmd/manage seed-dev`, `go run ./cmd/api`).

```bash
cd admin
pnpm install
API_BASE_URL=http://localhost:8080 pnpm dev   # http://localhost:3000
```

Connexion : `admin@ivia.local` (créé par `seed-dev`). Avec l'API lancée en `OTP_SENDER=smtp`, l'e-mail
du code arrive dans Mailpit : http://localhost:8025. Sinon : `POST http://localhost:8080/v1/dev/otp`
avec `{"recipient":"admin@ivia.local"}`.

Design : même langage visuel que les apps (`mobile/packages/ui`) — Berkeley Blue pour la barre
latérale et les en-têtes de fiche, Imperial Red pour l'action principale et la partie colorée des
titres, cartes blanches sans ombre (rayons 14/18), boutons pilules, surtitres en capitales, tuiles de
mosaïque au tableau de bord, icônes `lucide-react`. Briques : `components/ui.tsx` (cartes, en-têtes,
tableaux, statuts, états vides), `components/brand.tsx` (logotypes de `public/brand/`) et
`components/illustration.tsx` (mosaïque, fiches inclinées, pastilles).
Premier admin d'un autre environnement : `go run ./cmd/manage grant-admin <email>`.

## Commandes

| Commande                                 | Rôle                                                                                                         |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `pnpm dev` / `pnpm build` / `pnpm start` | développement, construction, serveur de production                                                           |
| `pnpm lint`                              | ESLint (`eslint-config-next`, règles React et TypeScript)                                                    |
| `pnpm typecheck`                         | `tsc --noEmit`                                                                                               |
| `pnpm test`                              | Vitest (logique : formats, libellés)                                                                         |
| `pnpm format` / `pnpm format:check`      | Prettier                                                                                                     |
| `pnpm gen:api`                           | régénère `lib/api-types.ts` depuis `backend/api/openapi.yaml` (à committer ; la CI vérifie qu'il est à jour) |

## Règles (non négociables)

- **Aucun accès à la base** : tout passe par l'API `/v1`, appelée **uniquement côté serveur**
  (`lib/api.ts`, marqué `server-only`). Aucune variable `NEXT_PUBLIC_*` : `API_BASE_URL` n'est lue
  que par le serveur Next.js.
- **Jeton de session** dans le cookie `ivia_admin_session` : `httpOnly`, `Secure` en production,
  `SameSite=Lax`. Jamais lisible par le JavaScript du navigateur. Écrit seulement par une Server
  Action (connexion) ou une Route Handler (`/logout`).
- **Droits vérifiés par l'API** à chaque requête : le back-office ne fait qu'afficher et appeler.
  Le layout `(admin)` relit `GET /v1/me` à chaque page : un rôle admin retiré coupe l'accès.
  Une session refusée (401) renvoie vers `/logout`, qui révoque la session et efface le cookie.
- **Mutations par Server Actions** (protégées contre le CSRF par Next.js : vérification de
  l'origine) ; toute action sensible passe par `ActionForm` avec confirmation qui rappelle l'objet
  et le montant, et un motif quand l'API l'exige. Les actions sont journalisées par l'API.
- **Types générés**, jamais écrits à la main : `Schemas["…"]` (alias de `lib/api-types.ts`).
- Composants serveur par défaut ; `"use client"` seulement pour l'interactivité (formulaires, barre latérale).

## Structure

```
app/
  layout.tsx              police, langue, métadonnées (non indexé)
  login/                  connexion par code e-mail (Server Action login), rôle admin exigé
  logout/route.ts         révocation de la session + effacement du cookie
  (admin)/layout.tsx      garde d'accès + barre latérale
  (admin)/page.tsx        tableau de bord (à traiter, indicateurs des 30 derniers jours)
  (admin)/shops/          boutiques : publier, refuser, suspendre, rétablir
  (admin)/drivers/        livreurs : liste, dossier (documents en lien temporaire), activation
  (admin)/orders/         commandes : liste, recherche par numéro, détail, actions admin
  (admin)/refunds/        file de remboursement
  (admin)/settings/       commission, barème de livraison, délais
  (admin)/audit/          journal des actions admin
components/ui.tsx         composants de base (esprit shadcn/ui, thémés par les tokens)
components/action-form.tsx  bouton d'action + confirmation + motif (Server Action)
lib/api.ts                client de l'API côté serveur, erreurs ApiError (message français de l'API)
lib/format.ts             FCFA, dates de Lomé, téléphone, libellés des statuts
lib/api-types.ts          généré (pnpm gen:api)
Dockerfile                image « standalone », utilisateur non privilégié (publiée par la CI sur main)
```

## Reste à faire (TASKS.md)

Relevés marchands (création, règlement), export des livraisons (CSV), catégories de produits et de
boutique, quartiers, comptes utilisateurs, paiements (liste, revérification, doublons), alertes
d'attribution détaillées ; tests end-to-end Playwright des parcours critiques (valider une
boutique, rembourser).
