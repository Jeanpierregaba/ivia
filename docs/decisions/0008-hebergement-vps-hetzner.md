# 0008 — Hébergement sur VPS Hetzner, fichiers sur Cloudflare R2

- **Statut** : Accepté
- **Date** : 2026-10-30

## Contexte

Budget d'hébergement inférieur à 50 € par mois au lancement, pour l'API Go, PostgreSQL + PostGIS,
le back-office Next.js et le stockage des photos et documents.

## Options envisagées

- **VPS Hetzner (UE) + Docker Compose + Caddy** : quelques euros par mois (environ 6 € après les
  hausses de 2026, à confirmer sur le site officiel), contrôle total, mais sauvegardes et mises à
  jour à notre charge.
- **Hébergement géré** (ex. Render + Neon) : moins d'administration, sauvegardes incluses, mais
  30 à 50 € par mois dès le départ.
- Fichiers : **Cloudflare R2** (compatible S3, pas de frais de sortie, 10 Go gratuits) plutôt que
  le disque du VPS.

## Décision

Un VPS Hetzner en Europe avec Docker Compose (API, PostGIS, back-office, Caddy pour le HTTPS
automatique) pour la production, et un second petit VPS pour staging, mis en place au moment de
l'intégration du paiement, pour qu'un incident de test ne touche jamais la production. Photos et
documents sur R2.

## Conséquences

- Sauvegarde `pg_dump` nocturne vers R2 (30 jours) + instantané du VPS ; restauration testée
  chaque mois.
- Mises à jour de sécurité du système automatiques, accès SSH par clé uniquement, pare-feu
  n'ouvrant que 80/443.
- Latence Europe ↔ Lomé d'environ 100 à 150 ms, acceptable pour une API REST.
- Migration de la base vers un service géré à envisager quand le volume ou l'enjeu augmente.
