# 001 — Connexion par code e-mail (app acheteur)

## Objectif

Permettre à un acheteur de se connecter ou de créer son compte sans mot de passe, avec un code à
6 chiffres reçu par e-mail ([PRD](../../PRD.md), « Comptes » ; [ADR 0006](../../decisions/0006-authentification-otp-sessions.md)),
puis de compléter son profil (prénom, nom, téléphone) et de donner son consentement au traitement
de ses données (loi togolaise n° 2019-014, [SECURITY](../../SECURITY.md)).

Ce premier lot couvre l'**app acheteur** ; les apps marchand et livreur reprendront les mêmes écrans
quand leurs maquettes seront prêtes. Maquettes du 2026-10-31 : elles guident, sans être la source
de vérité.

## Comportement attendu

**Démarrage** (pendant le splash de chargement, voir [027](../027-splash-onboarding/spec.md)) :
- pas de session enregistrée ⇒ présentation (premier lancement) ou écran de connexion ;
- session enregistrée ⇒ l'app vérifie le profil auprès du serveur :
  - session refusée (expirée, révoquée) ⇒ elle est effacée, écran de connexion ;
  - profil incomplet ⇒ écran « Faisons connaissance » ;
  - profil complet ⇒ accueil (écran provisoire : « Bonjour Awa », « Se déconnecter ») ;
  - serveur injoignable ⇒ accueil avec le profil gardé sur le téléphone ; sans profil gardé,
    écran d'erreur « Pas de connexion » avec « Réessayer ».

**1. « Bienvenue sur ivia »** : logo, texte d'explication, champ « Adresse e-mail », bouton
« Recevoir le code ». En dessous, « Continuer avec WhatsApp » désactivé avec la mention « bientôt ».
En bas : « En continuant, vous acceptez les Conditions d'utilisation et la Politique de
confidentialité » (liens).

**2. « Vérifiez vos e-mails »** : rappel de l'adresse avec « Modifier » (retour à l'étape 1),
6 cases pour le code (le collage d'un code entier remplit les 6 cases), compte à rebours « Renvoyer le
code dans 0:42 » puis lien « Renvoyer le code », encart « Rien reçu ? Regardez dans les courriers
indésirables. Le code est valable 10 minutes. », bouton « Valider » actif dès que les 6 chiffres sont
saisis.

**3. « Faisons connaissance »** (nouveau compte ou profil incomplet) : prénom, nom, téléphone
(indicatif +228 fixe, 8 chiffres) avec la mention « Visible par le livreur uniquement pendant une
livraison », case « J'accepte que ivia traite mes données selon la Politique de confidentialité »,
bouton « Créer mon compte ». Le retour (flèche) déconnecte et ramène à l'étape 1.

Un utilisateur dont le profil est déjà complet passe directement de l'étape 2 à l'accueil.

## Critères d'acceptation

- [ ] Étant donné une adresse valide, quand l'utilisateur appuie sur « Recevoir le code », alors un
      code est demandé au serveur et l'écran « Vérifiez vos e-mails » s'ouvre avec cette adresse.
- [ ] Étant donné une adresse mal formée ou vide, alors aucune requête n'est envoyée et le champ
      affiche « Saisissez une adresse e-mail valide. ».
- [ ] Étant donné le code reçu, quand l'utilisateur le saisit (ou le colle) et valide, alors la
      session est enregistrée dans le stockage sécurisé du téléphone.
- [ ] Étant donné un nouveau compte, après validation du code, alors l'écran « Faisons
      connaissance » s'ouvre ; étant donné un profil complet, alors l'accueil s'ouvre.
- [ ] Étant donné « Faisons connaissance », quand prénom, nom, un mobile togolais valide et le
      consentement sont fournis, alors le profil et le consentement sont envoyés au serveur et
      l'accueil s'ouvre.
- [ ] Étant donné la case de consentement non cochée, alors le compte n'est pas créé et un message
      l'indique.
- [ ] Étant donné le compte à rebours terminé, quand l'utilisateur appuie sur « Renvoyer le code »,
      alors un nouveau code est demandé et le compte à rebours repart.
- [ ] Étant donné une session enregistrée et un profil complet, quand l'app est relancée, alors
      l'accueil s'ouvre sans repasser par la connexion.
- [ ] Étant donné l'accueil, quand l'utilisateur appuie sur « Se déconnecter », alors la session est
      révoquée côté serveur, effacée du téléphone, et l'écran de connexion s'ouvre.
- [ ] Le jeton de session n'apparaît jamais dans les journaux ni dans une URL.

## Cas limites et erreurs

Le message affiché est celui du serveur (`error.message`, en français) quand il existe.
- **Code faux** (`otp_invalid`) : message sous les cases, cases vidées, focus sur la première.
- **Code expiré** (`otp_expired`) ou **trop d'essais** (`otp_too_many_attempts`) : message, cases
  vidées ; l'utilisateur renvoie un code.
- **Trop de demandes** (`otp_rate_limited`, `otp_daily_limit`) : message, pas de changement d'écran.
- **Téléphone refusé** par le serveur (erreur de validation par champ) : message sous le champ.
- **Réseau coupé ou lent** (délai de 15 s) : « Pas de connexion internet. Vérifiez votre réseau et
  réessayez. » ; le bouton redevient actif. Un double appui n'envoie qu'une requête.
- **Adresse avec espaces ou majuscules** : espaces retirés avant l'envoi (le serveur normalise).
- **Prénom ou nom vides, ou de plus de 100 caractères** : message sous le champ.
- **Numéro saisi avec espaces, ou avec +228** : accepté (8 chiffres retenus).
- **Session refusée pendant l'utilisation** (401) : session effacée, retour à la connexion.
- **Police agrandie à 200 %, écran de 320 dp, clavier ouvert** : rien n'est masqué, l'écran défile.

## Hors périmètre

- Apps marchand et livreur (même parcours, plus tard).
- Connexion par WhatsApp ou SMS (bouton présent mais désactivé).
- Le quartier sur le profil (présent sur la maquette, retiré : il viendra avec la recherche et les
  adresses, 002 et 007).
- Les textes des Conditions d'utilisation et de la Politique de confidentialité : pas encore rédigés
  (démarche suivie dans `TASKS.md`). Les liens affichent « Document disponible prochainement ».
- L'écran d'accueil réel (007) et le profil modifiable (002).

## Questions ouvertes

<!-- Vide = prêt pour le plan. -->
