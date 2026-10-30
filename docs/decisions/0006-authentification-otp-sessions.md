# 0006 — Connexion par OTP multi-canal et sessions opaques

- **Statut** : Accepté
- **Date** : 2026-10-30

## Contexte

Les utilisateurs se connectent sans mot de passe, par un code à usage unique. Le canal cible est
WhatsApp, avec le SMS en secours, mais l'API WhatsApp Business demande une validation de Meta au
délai incertain : le lancement se fait par e-mail. Un même compte sert dans les trois apps et le
back-office.

## Options envisagées

- **Service d'authentification externe** (Firebase Auth, Supabase Auth…) : rapide, mais l'OTP par
  WhatsApp n'y est pas natif et l'identité dépend d'un tiers.
- **OTP maison + jetons JWT** : sans état, mais difficile à révoquer (suspension d'un livreur).
- **OTP maison + jetons de session opaques** : un jeton aléatoire, haché en base, révocable
  immédiatement ; une requête en base par appel, négligeable à ce volume.

## Décision

OTP géré par le backend, envoyé via une interface `OTPSender` (implémentations : `email` avec
Brevo, puis `whatsapp`, `sms`, et une implémentation factice en local). Jetons de session opaques.

## Conséquences

- Code à 6 chiffres haché, valable 10 minutes, 5 essais, 1 envoi par minute et 10 par jour par
  destinataire. La limite par adresse IP reste haute : au Togo, les opérateurs mobiles font
  partager une même IP à beaucoup d'utilisateurs, une limite basse bloquerait des clients légitimes.
- Au lancement, l'e-mail est l'identifiant de connexion ; le numéro est saisi mais non vérifié.
  Au passage à WhatsApp, il faudra vérifier les numéros existants (point d'attention).
- Le back-office garde le jeton dans un cookie `httpOnly` côté serveur Next.js.
- Les rôles `driver` et `admin` ne s'obtiennent jamais par l'inscription.
