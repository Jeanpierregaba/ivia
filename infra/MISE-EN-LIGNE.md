# Mise en ligne d'ivia (tâche 017)

Procédure du jour J, dans l'ordre. Chaque étape dit **qui** la fait et **comment vérifier** qu'elle
est réussie. Compter une demi-journée pour un premier environnement, comptes externes compris.

> **Production ou staging d'abord ?** En production, l'API refuse le faux prestataire de paiement.
> Tant que l'agrégateur n'est pas branché (tâche 016), on met en ligne **le staging** : même
> procédure, avec `APP_ENV=staging` et `PAYMENT_PROVIDER=fake`. La production suit, à l'identique,
> une fois le paiement réel intégré.

Fichiers utilisés : [`bootstrap-server.sh`](bootstrap-server.sh), [`init-secrets.sh`](init-secrets.sh),
[`preflight.sh`](preflight.sh), [`deploy.sh`](deploy.sh), [`backup.sh`](backup.sh),
[`restore.sh`](restore.sh). Fonctionnement au quotidien : [`README.md`](README.md).

---

## 0. Avant de commencer (porteur du projet)

| À avoir | Pourquoi |
|---|---|
| Nom de domaine (ex. `ivia.tg`) et accès à sa zone DNS | adresses de l'API, du back-office, des photos et des e-mails |
| Compte **Hetzner Cloud** | le serveur (ADR 0008) |
| Compte **Cloudflare** (R2 activé) | photos, documents privés, sauvegardes |
| Compte **Brevo** | envoi des codes de connexion par e-mail |
| Projet **Firebase** | notifications push (compte de service) |
| Compte **Sentry** (offre gratuite) | suivi des erreurs |
| Accès au dépôt GitHub | images publiées par la CI sur GHCR |
| Gestionnaire de mots de passe d'équipe | copie de secours des secrets et de la clé de chiffrement des sauvegardes |

## 1. Louer le serveur (Hetzner)

- Type : 2 vCPU, 4 Go de RAM, 40 Go de disque au moins (gamme CX ou CPX), région Europe.
- Image : **Ubuntu 24.04 LTS**. Ajouter la **clé SSH** de l'équipe à la création (pas de mot de passe).
- Activer les **sauvegardes Hetzner** (instantané quotidien du serveur, en plus des sauvegardes de la base).
- Noter l'adresse IPv4.

✅ `ssh root@<ip>` ouvre une session sans mot de passe.

## 2. DNS

Dans la zone du domaine (pour le staging, préfixer : `api-staging`, `admin-staging`…) :

| Nom | Type | Valeur |
|---|---|---|
| `api` | A | IPv4 du serveur |
| `admin` | A | IPv4 du serveur |
| `media` | CNAME (Cloudflare) | domaine personnalisé du compartiment R2 public (étape 5) |

Si la zone est chez Cloudflare : `api` et `admin` en **« DNS only »** (nuage gris), sinon Caddy ne
peut pas obtenir les certificats HTTPS.

✅ `dig +short api.<domaine>` renvoie l'IP du serveur.

## 3. Préparer le serveur

Depuis votre poste :

```sh
scp infra/bootstrap-server.sh root@<ip>:/root/
ssh root@<ip> sh /root/bootstrap-server.sh
```

Le script installe Docker, crée l'utilisateur `deploy`, ferme SSH par mot de passe et pour root,
active le pare-feu (22, 80, 443), fail2ban et les mises à jour de sécurité automatiques.

✅ **Avant de fermer la session root** : `ssh deploy@<ip>` fonctionne, `ssh root@<ip>` est refusé.

## 4. Code et réglages (utilisateur deploy)

```sh
ssh deploy@<ip>
git clone https://github.com/<propriétaire>/ivia.git /opt/ivia   # dépôt privé : clé de déploiement en lecture seule
cd /opt/ivia/infra
cp .env.example .env && chmod 600 .env
nano .env        # réglages SANS secret : domaines, APP_ENV, noms des compartiments… (voir les commentaires)
```

Pour `API_TAG` et `ADMIN_TAG`, mettre provisoirement le SHA du dernier commit de `develop`
(staging) ou de `main` (production) : `deploy.sh` les met à jour ensuite.

Si le paquet GHCR est privé : `docker login ghcr.io -u <compte>` avec un jeton GitHub limité à
**read:packages**.

## 5. Services externes

**Cloudflare R2**
- Créer trois compartiments : `ivia-public` (photos), `ivia-private` (documents), `ivia-backups`.
- `ivia-public` : brancher le domaine personnalisé `media.<domaine>` → c'est `R2_PUBLIC_BASE_URL`.
- Créer un jeton API R2 **limité à `ivia-public` et `ivia-private`** (lecture et écriture) pour
  l'API, et un second **limité à `ivia-backups`** pour les sauvegardes.

**Brevo**
- Ajouter et **authentifier le domaine d'envoi** : enregistrements SPF, DKIM et DMARC fournis par
  Brevo, à créer dans la zone DNS. Sans eux, les codes tombent en courrier indésirable.
- Créer l'expéditeur (`no-reply@<domaine>`) et une clé API.

**Firebase** : télécharger le compte de service (JSON) du projet.
**Sentry** : créer un projet Go, copier le DSN.

## 6. Secrets (root)

```sh
cd /opt/ivia/infra
sudo ./init-secrets.sh            # génère base, sessions, webhooks ; demande Brevo, R2, Sentry sans les afficher
sudo cp ~/firebase.json secrets/fcm.json && sudo chown 65532:65532 secrets/fcm.json && sudo chmod 400 secrets/fcm.json
rm ~/firebase.json
```

Recopier les secrets générés dans le gestionnaire de mots de passe de l'équipe
(`sudo cat secrets/<nom>`, puis effacer l'écran). Staging et production n'ont **jamais** les mêmes.

## 7. Sauvegardes chiffrées (root)

```sh
sudo rclone config
#  1. « r2 »          : type s3, provider Cloudflare, jeton limité à ivia-backups
#  2. « ivia-backup » : type crypt, remote = r2:ivia-backups, noms de fichiers chiffrés,
#                       mot de passe et sel générés par rclone
sudo crontab -e
#  15 2 * * * cd /opt/ivia/infra && ./backup.sh >> /var/log/ivia-backup.log 2>&1
```

**Recopier le mot de passe et le sel de `ivia-backup`** dans le gestionnaire de mots de passe :
sans eux, les sauvegardes sont illisibles.

## 8. Vérifications

```sh
cd /opt/ivia/infra && sudo ./preflight.sh
```

Le script contrôle les réglages, la présence et les droits des secrets, Docker, le pare-feu, le
disque, le DNS et les sauvegardes, sans jamais afficher un secret. **Tout doit être « ok »**
(les « attention » sur un service pas encore branché sont tolérés en staging).

## 9. Premier déploiement

1. Fusionner sur `develop` (staging) ou `main` (production) : la CI publie les images
   `ivia-api:<sha>` et `ivia-admin:<sha>` (jobs `api-image` et `admin-image`), chacune seulement
   si son code a changé (voir infra/README.md, « Déployer une version »).
2. Sur le serveur :

```sh
cd /opt/ivia/infra && ./deploy.sh <sha>
```

`deploy.sh` télécharge les images, démarre, applique les migrations (au démarrage de l'API) et
vérifie `https://api…/ready` et `https://admin…/login`. En cas d'échec, il remet la version
précédente tout seul. Historique : `deploy-history.log`.

3. Premier compte admin :

```sh
docker compose run --rm --entrypoint /usr/local/bin/manage api grant-admin <email>
```

## 10. Recette (à cocher)

- [ ] `https://api.<domaine>/ready` répond 200 ; le certificat HTTPS est valide.
- [ ] Back-office : connexion avec le code reçu **dans une vraie boîte mail** (pas en indésirable).
- [ ] App acheteur (build de test pointé sur l'API) : connexion, recherche, panier, commande.
- [ ] Staging : paiement simulé ; production : petit paiement réel puis remboursement.
- [ ] App marchand : création de boutique, pièce d'identité envoyée, boutique publiée depuis le back-office.
- [ ] App livreur : dossier envoyé et validé ; une mission de bout en bout.
- [ ] Notification push reçue sur un téléphone.
- [ ] Une erreur volontaire apparaît dans Sentry, sans donnée personnelle.
- [ ] Le lendemain : une sauvegarde chiffrée est présente (`sudo rclone ls ivia-backup:postgres/`).

## 11. Test de restauration (staging, le jour même puis chaque mois)

Suivre « Sauvegardes et restauration » dans [`README.md`](README.md). Une sauvegarde jamais
restaurée n'est pas une sauvegarde.

## 12. Ensuite

- Déployer une nouvelle version : `./deploy.sh <sha>` ; revenir en arrière : `./deploy.sh <sha-précédent>`.
- Changer un secret (fuite, départ d'une personne, chaque année) : [`README.md`](README.md), « Secrets ».
- Surveiller : Sentry (erreurs), `docker compose logs -f api`, espace disque, e-mails de Hetzner.
- Les mises à jour de sécurité du système s'installent seules ; redémarrage automatique à 3 h 30
  si le noyau l'exige.
