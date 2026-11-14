# 030 — Écran d'autorisation de la localisation (4 apps)

## Objectif

Expliquer à l'utilisateur pourquoi l'app a besoin de sa position **avant** que le système ne la lui
demande. Une fenêtre système qui arrive sans contexte est souvent refusée, et un refus est difficile à
rattraper (iOS ne redemande plus, Android au plus une fois). La position sert à montrer ce qui est
proche (acheteur), à placer la boutique (marchand), à proposer des courses proches (livreur) et à
recevoir les demandes du quartier (pharmacie) ([PRD](../../PRD.md)).

Maquettes fournies par le porteur du projet le 2026-11-06, une par app.

## Comportement attendu

**L'écran** : en haut, un grand panneau de la couleur de l'app, à coins inférieurs arrondis. Il
contient la tuile du logo et le nom de l'espace, puis une illustration : cercles concentriques, une
pastille centrale et quatre pastilles autour, icônes dans la couleur de l'app. En dessous viennent le
titre, en deux tons, puis le texte, le bouton « Autoriser la localisation » (pilule de la couleur de
l'app, avec une épingle) et le lien « Refuser ».

| App | Couleur | Nom à côté du logo | Pastille centrale · autour | Titre (partie colorée en gras) | Texte |
|---|---|---|---|---|---|
| Acheteur | Imperial Red `#ED1C2F` | — | épingle avec personne · boutique, pharmacie, taxi, restaurant | Tout ce qu'il vous faut, **près de vous** | Activez la localisation pour voir ce qui est autour de vous et être livré. |
| Marchand | Berkeley Blue `#0E2E54` | Business | boutique · boutique, immeuble, restaurant, outils | Soyez visible **dans votre quartier** | Activez la localisation pour placer votre activité sur la carte. |
| Livreur | Cobalt Blue `#004DA8` | Livreur | moto · boutique, maison, maison, pharmacie | Des missions **près de vous** | Activez la localisation pour recevoir les missions proches et guider le client. |
| Pharmacie | vert `#0B7A55` | Pharmacie | pharmacie · 4 personnes | Les alertes **de votre quartier** | Activez la localisation pour recevoir les demandes des clients proches. |

Le lien du bas des maquettes (« Choisir mon quartier », « Saisir l'adresse », « Plus tard ») est
remplacé par **« Plus tard »** (pharmacie : « Saisir l'adresse ») : l'écran ne propose ni choix de
quartier ni saisie d'adresse. D'abord « Refuser » ; libellés de Gedeon gardés par décision du
porteur du projet (2026-11-07). Dans la suite de cette spec, « Refuser » désigne ce lien.

**Premier lancement**
1. Splash, puis l'écran de localisation, si la position n'est pas déjà autorisée.
2. « Autoriser la localisation » ouvre la fenêtre du système. Quelle que soit la réponse, on passe à la
   suite.
3. « Refuser » passe à la suite sans ouvrir la fenêtre du système.
4. La suite est la présentation (027), puis la connexion. La pharmacie n'a pas de présentation : elle
   passe directement à la connexion.
5. L'écran ne revient plus au lancement, une fois l'un des deux boutons appuyé.

**Quand une fonctionnalité a besoin de la position**

Si la position n'est pas autorisée, le même écran s'affiche par-dessus avant toute demande :
- « Autoriser » ouvre la fenêtre du système, puis la fonctionnalité continue avec la position obtenue ;
- « Refuser » ferme l'écran, et la fonctionnalité continue sans position, comme aujourd'hui en cas de
  refus.

Cela concerne les actions que l'utilisateur déclenche lui-même :

| App | Actions |
|---|---|
| Acheteur | « Utiliser ma position » à l'Accueil, alerte médicament sans zone, ajout d'une adresse |
| Marchand | épingle de la boutique |
| Livreur | position pour les courses |
| Pharmacie | position de l'officine dans le dossier |

Une lecture automatique (l'Accueil acheteur à l'ouverture) n'affiche jamais l'écran. Elle lit la
position seulement si elle est déjà autorisée.

**Refus définitif** : si le système ne peut plus redemander (refusée deux fois sur Android, une fois
sur iOS), « Autoriser la localisation » ouvre les réglages de l'app.

## Critères d'acceptation

- [x] Étant donné un premier lancement sans autorisation, quand le splash se termine, alors l'écran
      de localisation de l'app s'affiche (titre, texte, bouton et « Refuser » de la maquette) avant la
      présentation (acheteur, marchand, livreur) ou la connexion (pharmacie).
- [x] Étant donné l'écran au premier lancement, quand on appuie sur « Refuser », alors la
      présentation (ou la connexion) s'ouvre sans fenêtre du système.
- [x] Étant donné l'écran au premier lancement, quand on appuie sur « Autoriser » puis qu'on
      accepte ou refuse dans la fenêtre du système, alors la présentation (ou la connexion) s'ouvre.
- [x] Étant donné un des deux boutons déjà appuyé, quand l'app est relancée, alors l'écran n'est
      plus montré au lancement.
- [x] Étant donné la position déjà autorisée au premier lancement, alors l'écran n'est pas montré.
- [x] Étant donné une position non autorisée, quand l'utilisateur déclenche une action qui en a
      besoin (liste ci-dessus), alors l'écran s'affiche par-dessus ; « Refuser » ramène à l'action
      sans position, « Autoriser » fait la demande au système puis continue l'action.
- [x] Étant donné une position autorisée, quand l'utilisateur déclenche ces actions, alors l'écran
      n'est pas montré.
- [x] Étant donné l'Accueil acheteur ouvert sans autorisation, alors l'écran n'est pas montré et
      aucune fenêtre du système ne s'ouvre.
- [x] Étant donné un refus définitif, quand on appuie sur « Autoriser la localisation », alors les
      réglages de l'app s'ouvrent.
- [x] Les 4 apps déclarent la permission de localisation : texte d'explication iOS et permission
      Android. La pharmacie et le livreur n'en ont pas aujourd'hui.

## Cas limites et erreurs

- **Localisation désactivée sur le téléphone** : « Autoriser » donne la même suite qu'un refus (on
  continue). L'action concernée garde son message actuel (« La localisation est désactivée… »).
- **Fenêtre du système sans réponse ou erreur de la plateforme** : on continue, sans rester bloqué
  sur l'écran.
- **Appui répété sur « Autoriser »** : une seule demande à la fois, avec le bouton occupé pendant la
  demande.
- **Préférences illisibles** : l'écran est montré, sans bloquer l'app. Comme pour la présentation,
  il peut revenir au lancement suivant.
- **Grandes polices et petits écrans** : tout reste lisible et atteignable, le contenu défile.
- **Retour système (Android) sur l'écran de lancement** : il quitte l'app, comme sur la présentation.
  Sur l'écran affiché par une fonctionnalité, il vaut « Refuser ».

## Hors périmètre

- **Hors de cet écran, rien ne change** : le choix du quartier sur l'Accueil acheteur, l'adresse de
  la boutique ou du dossier, les messages actuels en cas de refus.
- La localisation en arrière-plan, et le suivi du livreur pendant une course.
- L'aperçu web.

## Questions ouvertes

- Aucune.
