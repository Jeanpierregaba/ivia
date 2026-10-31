# 018 — Espace livreur : lancement, connexion, dossier de candidature

## Objectif

Permettre à un livreur d'ouvrir l'app livreur, de comprendre son fonctionnement, de se connecter
(même compte ivia) puis de déposer son dossier (véhicule, immatriculation, documents) et de suivre
sa vérification par l'équipe ivia ([PRD](../../PRD.md) : « Inscription du livreur validée par
l'admin » ; un compte acheteur ne donne jamais accès aux missions).

Maquettes du 2026-10-31 : elles guident, sans être la source de vérité. Reprend pour le livreur
[027](../027-splash-onboarding/spec.md), [001](../001-connexion-otp/spec.md) et la structure de
[004](../004-espace-marchand/spec.md).

## Comportement attendu

**Couleurs** : action, liens, champ actif et partie colorée des titres en Cobalt.

**1. Splash de chargement** : fond Cobalt, tuile blanche au logotype Cobalt (place du splash
natif), « Livreur », « Livrez près de chez vous. », trois points, au moins 800 ms.

**2. Présentation** (premier lancement), « [logo] Livreur » en tête de la page 1 :

| Page | Illustration | Titre (partie colorée) | Texte |
|---|---|---|---|
| 1 | Carte Cobalt : « Nouvelle mission · 1 200 FCFA · Gain indicatif », compte à rebours 31, « Chez Afi → Bè Kpota · 4,2 km », Accepter ; pastille « Vous êtes disponible » | Des missions **près de vous.** | Restez disponible et recevez des propositions avec la boutique, la distance et le gain indicatif. |
| 2 | Carte Berkeley : étapes Aller à la boutique ✓ · Récupérer le colis (en cours) · Livrer le client ; « Ouvrir l'itinéraire » | Guidé **à chaque étape.** | L'itinéraire s'ouvre dans votre application de cartes : la boutique, puis le client. |
| 3 | Carte Cobalt : « Code du client » 4 8 2 7 ; pastille sombre « Mission terminée » | Le code du client **valide la livraison.** | Saisissez le code à 4 chiffres. La mission est terminée et vous redevenez disponible. |

**3. « Espace livreur »** : pastille « Livreur », « Connectez-vous avec votre e-mail. Les missions
s'ouvrent après la validation de votre dossier par ivia. » ; écran du code comme le marchand.

**4. « Devenez livreur ivia »** (aucun dossier) : pastille « Votre dossier ». Si le profil est
incomplet (le serveur exige prénom, téléphone et consentement pour postuler, choix du
2026-10-31), le formulaire commence par prénom, nom, téléphone et la case de consentement
(préremplis avec ce qui existe) ; un compte au profil complet ne les voit pas. Puis véhicule (Moto /
Voiture), numéro d'immatriculation, documents (pièce d'identité, permis de conduire, carte grise :
« Ajouter » puis « Ajouté », photo prise ou choisie), mention « Vos documents sont visibles
uniquement par l'équipe ivia. », bouton « Envoyer mon dossier » actif quand tout est rempli. Le
retour déconnecte.

**5. « Votre dossier est en cours de vérification »** : étapes Compte créé ✓ · Dossier envoyé ✓
(« Moto · 3 documents ») · Vérification par ivia (en cours) · Missions activées ; bouton
« Voir mon dossier » (récapitulatif : véhicule, immatriculation, types de documents envoyés,
sans les documents eux-mêmes). Actualisation au retour dans l'app et en tirant vers le bas.

**Ensuite** : dossier refusé ⇒ motif de l'admin et « Corriger mon dossier » (formulaire prérempli ;
les documents sont renvoyés). Livreur suspendu ⇒ motif. Dossier validé ⇒ accueil provisoire
(disponibilité, propositions et missions : 019 à 022).

## Critères d'acceptation

- [ ] Étant donné l'app livreur, au lancement, alors le splash de chargement (tuile, « Livreur »,
      slogan) prend le relais du splash natif sans saut, au moins 800 ms ; l'app est en Cobalt.
- [ ] Étant donné un compte au profil incomplet, après connexion, alors le formulaire du dossier
      demande aussi prénom, nom, téléphone et consentement, envoyés au serveur avant la
      candidature ; un profil complet ne les demande pas.
- [ ] Étant donné le véhicule, l'immatriculation et les 3 documents, quand le livreur envoie, alors
      chaque document est envoyé dans le compartiment privé par URL signée, la candidature puis les
      documents sont transmis, et l'écran de vérification s'ouvre (« Moto · 3 documents »).
- [ ] Étant donné un document choisi, alors il est redimensionné (2048 px au plus, lisible) et
      débarrassé de ses métadonnées avant l'envoi.
- [ ] Étant donné un dossier refusé, alors le motif s'affiche et « Corriger mon dossier » rouvre le
      formulaire prérempli (véhicule, immatriculation).
- [ ] Étant donné un dossier validé, à la relance, alors l'accueil livreur s'ouvre.
- [ ] Le jeton de session n'est jamais envoyé au stockage ; aucun document n'est affiché par l'app
      après l'envoi.

## Cas limites et erreurs

- **Immatriculation** de 2 à 20 caractères : message sous le champ.
- **Document manquant** : bouton inactif ; la ligne indique « Ajouter ».
- **Échec d'envoi d'un document** (réseau) : message ; nouvel essai sans renvoyer les documents
  déjà transmis.
- **Envoi interrompu après la candidature** (documents en partie transmis) : au lancement suivant,
  l'écran de vérification indique le nombre de documents reçus ; « Corriger mon dossier » permet
  d'ajouter les manquants. (Le serveur accepte un dossier incomplet ; l'admin le voit.)
- **Photo trop lourde après compression** (> 5 Mo) : message, rien n'est retenu.
- **Appareil photo ou photos refusés** : message, l'autre source reste possible.
- **Double appui** sur « Envoyer mon dossier » : une seule candidature, chaque document une fois.
- **Profil refusé par le serveur** (téléphone déjà utilisé, champ invalide) : message sous le champ,
  rien d'autre n'est envoyé.
- **Police à 200 %, écran de 320 dp** : rien n'est masqué, les écrans défilent.

## Hors périmètre

- Disponibilité, position, propositions, missions (019 à 022) : accueil provisoire.
- Documents PDF (photos seulement, choix du 2026-10-31) et photo du livreur.
- Notifications push de validation (012).
- Validation des dossiers dans le back-office.

## Questions ouvertes

<!-- Vide = prêt pour le plan. -->
