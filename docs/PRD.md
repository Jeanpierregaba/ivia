# PRD — Product Requirements Document

## Nom du projet

**ivia** — plateforme e-commerce avec réseau de livraison interne (MVP).

## Problème résolu

À Lomé, acheter auprès des commerces locaux demande de se déplacer, d'appeler ou d'écrire sur
WhatsApp, sans savoir si le produit est disponible ni à quel prix, puis de trouver soi-même un
moyen de livraison (zémidjan, coursier, ami). Les commerçants, eux, n'ont pas de vitrine en ligne
simple ni d'encaissement fiable à distance.

ivia permet à un acheteur de **trouver un produit près de chez lui, de le payer par Mobile Money
dans l'application, puis de le retirer en boutique ou de se le faire livrer** par un livreur de la
plateforme, avec un suivi à chaque étape.

## Utilisateurs cibles

| Profil | Qui | Ce qu'il veut | Niveau technique |
|---|---|---|---|
| Acheteur (`buyer`) | Particulier à Lomé, smartphone Android d'entrée/milieu de gamme | Trouver un produit disponible, payer en confiance, être livré vite | Utilise WhatsApp et Mobile Money, pas plus |
| Marchand (`seller`) | Commerçant ou petite boutique physique | Vendre en ligne sans site, recevoir des commandes payées d'avance | Faible à moyen |
| Livreur (`driver`) | Livreur à moto ou en voiture, recruté et validé par la plateforme | Recevoir des missions claires, être guidé jusqu'à la boutique et au client | Faible à moyen |
| Administrateur (`admin`) | Équipe ivia | Valider boutiques et livreurs, superviser commandes et paiements, régler les marchands | Bon |

Un même compte peut cumuler plusieurs rôles (ex. un marchand qui achète).

## Parcours principaux

1. **Achat avec livraison** — Inscription/connexion → recherche (nom, catégorie, prix, proximité)
   → fiche produit → panier (une seule boutique) → choix « livraison » + adresse + véhicule →
   affichage des frais et du total → paiement Mobile Money → confirmation par le prestataire →
   le marchand accepte et prépare → « prête » → attribution d'un livreur → récupération en boutique
   → livraison → l'acheteur donne son code à 4 chiffres → « livrée ».
2. **Achat avec retrait** — Mêmes étapes jusqu'au paiement, choix « retrait » → le marchand accepte
   et prépare → « prête pour retrait » → l'acheteur se présente avec son code → « retirée ».
3. **Mission de livraison** — Le livreur est en ligne → reçoit une proposition (boutique, distance,
   gain indicatif) → accepte dans le délai → itinéraire vers la boutique → confirme son arrivée →
   confirme la récupération → itinéraire vers le client → saisit le code de l'acheteur → mission
   terminée, il redevient disponible.
4. **Ouverture d'une boutique** — Le marchand crée son compte → crée sa boutique (infos, adresse,
   position, logo) → l'admin valide → le marchand ajoute ses produits (photos, prix, catégorie,
   taille de colis, stock suivi ou non) → la boutique est visible.

## Fonctionnalités du MVP

Une ligne = une fonctionnalité testable, ordre indicatif (le backlog ordonné est dans `TASKS.md`).

**Comptes**
- [ ] Inscription et connexion sans mot de passe par code à usage unique (OTP), un compte pour toutes les applications. Canal d'envoi interchangeable : **e-mail au lancement**, puis WhatsApp (canal principal) dès la validation de l'API WhatsApp Business, et SMS en secours.
- [ ] Rôles `buyer`, `seller`, `driver`, `admin` cumulables ; chaque appel API vérifie le rôle et la propriété de la ressource.
- [ ] Profil acheteur et carnet d'adresses de livraison (adresse texte + quartier + point sur la carte).
- [ ] Suppression du compte depuis chaque app (exigence du Play Store) : données personnelles anonymisées, commandes et paiements conservés pour la traçabilité financière.

**Boutiques et catalogue**
- [ ] Création d'une boutique par un marchand, soumise à validation de l'admin avant publication ; l'admin vérifie d'abord la pièce d'identité du marchand (registre du commerce facultatif).
- [ ] Gestion des produits : création, modification, désactivation, photo principale + photos supplémentaires, prix, catégorie, description, taille de colis (petit / moyen / grand).
- [ ] Gestion du stock : produit à stock suivi (quantité décrémentée, survente impossible) ou non suivi (disponibilité confirmée par le marchand à chaque commande).

**Recherche**
- [ ] Recherche de produits et de boutiques par nom, filtrée par catégorie, fourchette de prix et quartier, triée par pertinence ou par distance.
- [ ] Recherche « autour de moi » : produits et boutiques dans un rayon donné autour de la position de l'acheteur.

**Commande et paiement**
- [ ] Panier mono-boutique : ajouter un produit d'une autre boutique propose de vider le panier.
- [ ] Commande avec choix retrait / livraison ; en livraison : adresse, véhicule compatible (moto / voiture selon la plus grande taille de colis), frais calculés (forfait + prix au km selon le véhicule, distance à vol d'oiseau boutique → adresse × 1,3, coefficient réglable), total.
- [ ] Paiement Flooz / T-Money via un agrégateur ; commande confirmée **uniquement** sur notification serveur (webhook) du prestataire ; gestion des paiements en attente, échoués et expirés (15 minutes sans paiement ⇒ commande expirée).
- [ ] Réservation du stock à la commande, libérée si le paiement échoue ou expire.
- [ ] Paiement arrivé après l'expiration : la commande reprend si le stock est encore disponible, sinon elle est annulée et placée dans la file de remboursement.
- [ ] Annulation par l'acheteur tant que le marchand n'a pas accepté (remboursement intégral) ; ensuite, seul l'admin peut annuler.
- [ ] Suivi de la commande par l'acheteur avec l'historique horodaté des statuts (adaptés au mode retrait ou livraison).

**Marchand**
- [ ] Réception des commandes payées, acceptation ou refus sous 15 minutes ; refus ou absence de réponse ⇒ annulation et file de remboursement.
- [ ] Passage des commandes à « en préparation » puis « prête » ; remise au livreur ou à l'acheteur contrôlée par le code de remise (5 essais au maximum, puis intervention de l'admin).

**Livraison**
- [ ] Inscription du livreur validée par l'admin (identité, véhicule, documents) ; un compte acheteur ne donne jamais accès aux missions.
- [ ] Statut du livreur (disponible / occupé / hors ligne / suspendu) ; quand il est disponible ou en mission, l'app reste active (notification permanente) et envoie sa position régulièrement.
- [ ] Attribution automatique : proposition au livreur disponible le plus proche avec un véhicule compatible, 45 secondes pour répondre ; refus ou silence ⇒ livreur suivant ; après 5 livreurs ou 20 minutes sans preneur, alerte de l'admin. Jamais deux livreurs actifs sur une commande, une seule mission à la fois par livreur.
- [ ] Déroulé de mission : arrivée en boutique, récupération, livraison confirmée par le code à 4 chiffres de l'acheteur ; itinéraire ouvert dans l'application de cartes du téléphone ; prénom et numéro de l'acheteur visibles uniquement pendant la mission.
- [ ] Échec de livraison : après 10 minutes d'attente et deux appels sans réponse, le livreur déclare l'échec et rapporte le colis en boutique (retour confirmé par le marchand) ; produits remboursés, frais de livraison conservés.

**Notifications**
- [ ] Notifications push et liste des notifications dans chaque application, pour les événements listés dans le contexte (paiement, acceptation, préparation, livreur assigné, récupération, livraison, nouvelle mission, annulation).

**Administration (back-office web)**
- [ ] Validation / suspension des boutiques et des livreurs.
- [ ] Supervision des commandes et des paiements ; file des commandes à rembourser, remboursement déclenché par l'admin (transfert Mobile Money via l'API du prestataire).
- [ ] Journal des actions des admins (qui a validé, suspendu, remboursé, réglé quoi et quand).
- [ ] Paramétrage : taux de commission, barème de livraison par véhicule, délai de réponse des livreurs, catégories de produits.
- [ ] Relevé des montants dus à chaque marchand sur une période et marquage manuel « réglé ».
- [ ] Export du nombre de livraisons par livreur et par période (base de la paie, faite hors application).

## Hors scope (pour l'instant)

- Transport de passagers, VTC, réservation de trajets (vision long terme).
- Paiement à la livraison et paiement par carte bancaire.
- Panier multi-boutiques.
- Recherche par marque ou caractéristiques libres, recommandations personnalisées.
- Carte de suivi du livreur en temps réel pour l'acheteur (statuts + push uniquement).
- Remboursement sans validation humaine : au MVP, chaque remboursement est déclenché par un admin depuis la file de remboursement.
- Plusieurs missions simultanées pour un même livreur.
- Calcul et versement de la paie des livreurs (fixe, primes) : seulement l'export des livraisons.
- Virement automatique aux marchands : relevé + règlement manuel.
- Avis et notes sur produits, boutiques et livreurs.
- Promotions, codes promo, programme de fidélité.
- Catégories de véhicules autres que moto et voiture ; poids et volume précis des produits.
- Messagerie intégrée entre acheteur, marchand et livreur.
- Version iOS publiée sur l'App Store (le code Flutter reste compatible, publication Android d'abord — à confirmer à l'étape Architecture).
- Autres langues que le français, autres devises que le FCFA.

## Vocabulaire du domaine

| Terme | Définition |
|---|---|
| Utilisateur (`user`) | Une personne avec un compte unique. Elle donne un e-mail et un numéro de téléphone, uniques chacun. Au lancement, elle se connecte avec son e-mail ; avec WhatsApp ou SMS, elle se connectera avec son numéro. |
| OTP | Code à 6 chiffres, à usage unique et valable quelques minutes, envoyé pour se connecter ou s'inscrire. |
| Canal OTP | Moyen d'envoi de l'OTP : `email` (lancement), `whatsapp` (cible), `sms` (secours). |
| Rôle | `buyer`, `seller`, `driver` ou `admin`. Un utilisateur peut en avoir plusieurs. |
| Boutique (`shop`) | Commerce physique d'un marchand, avec une position géographique. Statuts : en attente de validation, publiée, suspendue. |
| Produit (`product`) | Article vendu par une seule boutique. Possède une taille de colis et un mode de stock. |
| Stock suivi | Le système connaît la quantité ; une commande la réserve, la survente est impossible. |
| Stock non suivi | Pas de quantité ; le marchand confirme la disponibilité à chaque commande. |
| Taille de colis | `small`, `medium` ou `large` ; détermine les véhicules compatibles. |
| Panier (`cart`) | Produits choisis par un acheteur, tous d'une même boutique. |
| Commande (`order`) | Achat validé auprès d'une boutique, avec un mode de remise et un historique de statuts. |
| Mode de remise | `pickup` (retrait en boutique) ou `delivery` (livraison). |
| Catégorie de véhicule | `motorbike` ou `car`. |
| Frais de livraison | Forfait + prix au km selon le véhicule, distance boutique → adresse. |
| Paiement (`payment`) | Transaction Mobile Money d'un acheteur pour une commande. Statuts : initié, en attente, réussi, échoué, expiré, remboursé. |
| Webhook | Notification envoyée par le prestataire de paiement au serveur ; seule source de vérité d'un paiement réussi. |
| Commission | Pourcentage du montant des produits gardé par la plateforme. |
| Relevé marchand (`settlement`) | Somme due à un marchand sur une période (produits − commission − remboursements), marquée réglée par l'admin. |
| Livreur (`driver`) | Utilisateur validé par l'admin, avec un véhicule. Statuts : disponible, occupé, hors ligne, suspendu. |
| Mission (`delivery`) | Livraison d'une commande par un livreur, de la boutique à l'adresse de l'acheteur. |
| Proposition (`delivery offer`) | Offre d'une mission à un livreur, à accepter avant un délai. |
| Code de remise | Code à 4 chiffres affiché dans l'app de l'acheteur, saisi par le livreur (livraison) ou le marchand (retrait) pour prouver la remise. 5 essais au maximum. |
| File de remboursement | Liste, dans le back-office, des commandes annulées après paiement et pas encore remboursées. |
| Échec de livraison | Le livreur n'a pas pu remettre le colis ; il le rapporte en boutique. |
| Quartier | Zone nommée de la ville (ex. Bè, Tokoin, Adidogomé), choisie dans une liste. |

## Critères de succès

Mesurés sur les 3 premiers mois après lancement à Lomé :

- **Fiabilité** : 0 commande confirmée sans paiement réussi côté prestataire ; 0 commande avec deux livreurs actifs ; 0 survente sur un produit à stock suivi.
- **Parcours** : un acheteur passe de la recherche au paiement en moins de 3 minutes.
- **Livraison** : 80 % des commandes « prêtes » ont un livreur assigné en moins de 10 minutes ; délai médian commande prête → livrée inférieur à 45 minutes.
- **Adoption** (objectifs à ajuster) : 30 boutiques publiées, 10 livreurs actifs, 300 commandes payées par mois au 3e mois.
- **Qualité** : moins de 5 % des commandes payées annulées ou remboursées.

## Contraintes connues

- **Marché** : Togo, Lomé au lancement. Langue : français. Devise : FCFA (XOF), montants entiers sans décimales.
- **Paiement** : Flooz (Moov Africa) et T-Money (Yas) via un agrégateur, comparé à l'étape Architecture (frais, documentation, mode test, délai d'intégration).
- **Authentification** : l'API WhatsApp Business demande que Meta vérifie l'entreprise et approuve un modèle de message d'authentification. Comme ce délai n'est pas maîtrisé, le MVP démarre avec l'OTP par e-mail. Côté backend, l'envoi est isolé derrière une interface « canal » : ajouter WhatsApp ou le SMS ne touche ni à la génération ni à la vérification des codes. Les applications mobiles devront seulement proposer de saisir un numéro au lieu d'un e-mail.
- **Juridique (à vérifier avant l'intégration du paiement)** : une société enregistrée (RCCM, NIF) est nécessaire pour ouvrir un compte chez le prestataire de paiement et un compte Google Play « organisation » (numéro D-U-N-S, plusieurs semaines d'obtention). Encaisser pour le compte des marchands peut relever de la réglementation BCEAO : à faire confirmer par l'agrégateur ou un juriste. L'hébergement en Europe peut demander une déclaration auprès de l'autorité togolaise de protection des données.
- **Équipe** : deux développeurs (le porteur du projet et un collaborateur).
- **Délai** : lancement visé à environ 6 mois (vers avril 2027). Jalon de repli vers le 4e mois : une première version **retrait en boutique seulement** (sans app livreur) si la livraison prend du retard ; le backlog est ordonné pour le permettre.
- **Budget d'hébergement** : moins de 50 € par mois au départ.
- **Appareils** : smartphones Android d'entrée et de milieu de gamme, connexion mobile parfois lente ou instable ; les applications doivent rester utilisables en 3G et tolérer les coupures. Back-office : navigateur d'ordinateur.
- **Données personnelles** : numéros de téléphone, adresses, positions des livreurs, documents d'identité des livreurs. La loi togolaise sur la protection des données personnelles (loi n° 2019-014) s'applique : collecte limitée au nécessaire, consentement, accès restreint aux documents. Le détail est dans `docs/SECURITY.md`.
- **Argent** : chaque opération financière doit être traçable (journal non modifiable des paiements, remboursements et règlements).
