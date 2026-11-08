# 033 — Ivia Driver : nouveau nom et écrans d'après les maquettes D00 à D19

<!-- Le QUOI, pas le COMMENT. Lisible par quelqu'un qui ne code pas. -->

## Objectif

L'app des livreurs s'appelle désormais **Ivia Driver** (ex-« ivia Livreur »). Ses écrans sont
refaits d'après les 20 maquettes du designer (`maquettes/D00.png` à `D19.png`), au pixel près.

Le livreur doit pouvoir :
- s'inscrire ;
- passer en ligne ;
- accepter une mission ;
- faire le retrait puis la livraison ;
- signaler un problème ;
- suivre ses missions et ses gains.

Couvre le parcours livreur du PRD et la remise au livreur des courses pharmacie (ADR 0014), qui
était la tâche 20 de la spec 032.

## Arbitrages (validés le 2026-11-08)

1. **Nom** : « Ivia Driver » remplace « ivia Livreur » dans :
   - le nom sous l'icône (Android, iOS) ;
   - le titre de l'app ;
   - le splash ;
   - le badge à côté du logo (« Driver »).

   Le mot « livreur » reste dans les phrases en français (« Devenez livreur ivia »).
2. **Couleurs** :
   - la barre de menu du bas est **claire** (fond blanc, onglet actif en bleu Ivia Driver), au
     lieu du fond sombre des maquettes ;
   - les cartes sombres des maquettes restent sombres : chiffres du jour, en-tête « Missions »,
     carte « Gains », code de retrait, gain de la course.
3. **Connexion par numéro** (ADR 0012), pas par e-mail. Les écrans D04 et D05 sont repris avec
   les écrans de connexion par numéro existants, dans le style des maquettes. La note « Même compte
   sur toutes les apps ivia » parle du numéro.
4. **Dossier** : le style des maquettes, avec le contenu du serveur de Gedeon :
   - véhicule : vélo, moto ou voiture, avec marque et modèle facultatifs ;
   - pièces demandées selon le véhicule ;
   - zone de travail, exigée par le serveur ;
   - compte de versement Mobile Money.

   Activité **livraison seulement** : le taxi VTC viendra dans une autre spec.
5. **Ce que le serveur ne fournit pas** : on le calcule depuis l'historique des missions quand
   c'est possible, sinon on le masque. La liste des manques est notée pour Gedeon dans `TASKS.md`
   (voir « Manques côté serveur »).

## Comportement attendu

### Lancement et inscription

| Écran | Maquette | Contenu |
|---|---|---|
| Splash | D00 | Fond bleu, logo, « Driver », « Livrez près de chez vous. » |
| Présentation (3 pages) | D01 à D03 | Mission proposée, étapes guidées, code du client. « Passer », « Suivant », « Commencer », retour. |
| Connexion | D04 | « Espace livreur », numéro de téléphone, « Recevoir le code », conditions d'utilisation. |
| Code | D05 | 6 chiffres envoyés au numéro, « Modifier », renvoi après 0:42, « Valider ». |
| Dossier | D06 | Véhicule (vélo, moto, voiture), plaque d'immatriculation (sauf vélo), marque et modèle (facultatifs), zone de travail, pièces avec « Ajouté » ou « Ajouter », compte de versement. « Envoyer mon dossier » actif quand tout est rempli. |
| En vérification | D07 | Étapes « Compte créé », « Dossier envoyé (véhicule · n documents) », « Vérification par ivia : en cours », « Missions activées ». « Voir mon dossier ». |

Après le splash, la demande de localisation (spec 030) reste avant la présentation.

### Travail

| Écran | Maquette | Contenu |
|---|---|---|
| Accueil hors ligne | D08 | « Bonsoir / Bonjour » et nom, initiales. Carte du jour : livraisons, gains du jour. Carte « Vous êtes hors ligne » avec « Glisser pour passer en ligne ». |
| Accueil en ligne | D09 | Bandeau « En ligne · depuis … · quartier » et « Pause ». Carte autour de la position. Volet « Recherche de missions… » avec livraisons et gains du jour. |
| Mission proposée | D10 | Gain indicatif, compte à rebours, distance, taille du colis, retrait (boutique ou pharmacie, distance), livraison (quartier, distance après le retrait). « Glisser pour accepter », « Refuser ». |
| Vers le retrait | D11 | Carte et itinéraire. Étape 1 sur 2, nom, adresse, articles, taille du colis, « Payée ». Appeler, « Ouvrir dans Maps », « Glisser à l'arrivée ». |
| Retrait | D12 | Lieu et n° de commande, colis à vérifier (cases à cocher), « Glisser : colis récupéré », « Signaler un problème ». |
| Vers le client | D13 | Distance, temps restant, heure d'arrivée estimée, progression, client (nom, adresse, quartier), consigne. Appeler, « Glisser à l'arrivée ». |
| Preuve de remise | D14 | Commande, code du client (4 chiffres), case « J'ai vu l'original de l'ordonnance » si besoin, « Confirmer la livraison ». |
| Livraison terminée | D15 | « Commande #… remise à … à hh:mm », gain de la course, totaux du jour. « Rester en ligne », « Faire une pause ». |
| Un problème ? | D16 | Situations proposées selon l'étape, et « Appeler le support ». |

**Course pharmacie** (ADR 0014, ex-tâche 20 de la spec 032). Au retrait (D12), la carte sombre
« Votre code de retrait » affiche le code à 4 chiffres et « Montrez ce code au pharmacien ». Il
n'y a pas de glissière : la pharmacie valide la remise. L'écran passe alors seul à « La pharmacie
a validé la remise · hh:mm » avec le montant payé en espèces, puis à l'étape suivante.

Une course de boutique n'a pas de code : le livreur glisse « colis récupéré », comme aujourd'hui.

### Onglets

| Écran | Maquette | Contenu |
|---|---|---|
| Missions | D17 | En-tête sombre « Missions » et recherche par n° de commande. Onglets « En cours · n », « Terminées », « Annulées ». Cartes : n°, retrait → livraison, statut, gain, heures. |
| Gains | D18 | « Semaine » et « Mois », total de la période, barres par jour, nombre de livraisons, liste par jour. Le compte de versement (opérateur et numéro masqué) est affiché sans date ni montant de versement. |
| Profil | D19 | Initiales, nom, « Validé », véhicule, plaque et modèle (« Modifier » ouvre le dossier), documents, zone de travail (à la place de « Zones préférées »), application de navigation, sonnerie des missions, aide et support, « Se déconnecter ». |

La barre du bas a 4 onglets (Accueil, Missions, Gains, Profil). Elle est claire, avec l'onglet
actif en pastille bleue et son libellé.

### Ce qui est calculé ou masqué (arbitrage 5)

| Élément de maquette | Décision |
|---|---|
| Gains du jour, de la semaine, du mois, par jour ; nombre de livraisons | **Calculés** depuis l'historique des missions (gains des missions livrées, jours de Lomé). |
| Variation « +14 % » | **Calculée** : comparaison avec la période précédente, si elle a des missions. |
| Heure d'arrivée estimée (D13, D17) | **Calculée** : distance et durée de l'itinéraire du serveur (`POST /v1/geo/route`, profil moto ou voiture, durée ralentie pour le vélo) ; repli sur la distance à vol d'oiseau et une vitesse moyenne selon le véhicule. |
| Application de navigation (D19) | **Réglage du téléphone** : Google Maps, Waze ou Plans (iPhone). |
| Sonnerie des missions (D19) | **Réglage du téléphone** : activée, une nouvelle proposition fait sonner et vibrer l'app. Ivia Driver n'a pas de notifications push (les propositions arrivent app ouverte) : `alert_sound` ne s'applique pas. Les notifications push des livreurs sont notées pour Gedeon. |
| Km parcourus, temps en ligne, « 5/8 » objectif, note « 4,9 · 212 courses », demande par quartier (D08), « 4 commandes bientôt prêtes », plusieurs zones préférées | **Masqués**. Le nombre de courses terminées est affiché à la place de la note. |
| Tracé de la proposition sur la carte (D10) | **Masqué** : la proposition ne donne pas les positions du retrait et du client. La carte reste centrée sur le livreur ; les distances et la durée estimée sont dans le volet. |
| Versement prévu (« Versement vendredi 54 200 F ») | **Masqué** : seul le compte de versement est affiché. |
| Guidage tour par tour dans l'app (« 250 m, tournez à droite ») | **Masqué**. Le bandeau affiche la destination et la distance à vol d'oiseau ; le guidage se fait dans l'application de navigation choisie. |
| Messagerie avec la boutique ou le client | **Masquée** : seul l'appel est proposé. Sur D13, la place du bouton de messagerie sert à l'itinéraire. |
| Arrivée à la pharmacie et chez le client (course pharmacie) | **Dans l'app** : le serveur n'a pas ces étapes pour les courses pharmacie ; « Glisser à l'arrivée » passe à l'écran suivant sans appel. |
| Photo du colis remis (D14) | **Masquée**. |
| « Colis endommagé », « Code refusé », « Adresse introuvable » (D16) | **Non proposés seuls**. Ils ouvrent l'appel au support. « Client injoignable » déclenche la livraison impossible existante (10 min d'attente, 2 appels). « Accident ou urgence » appelle le support. |
| « Chez Afi a validé la remise » pour une boutique | **Masqué** : seules les pharmacies valident la remise. |
| Carte de fond | Carte Google si la clé est fournie, sinon fond neutre (comme l'app marchand). |

## Critères d'acceptation

- [ ] Le nom affiché de l'app est « Ivia Driver » sur Android et iPhone, et le titre de l'app
      aussi. Plus aucune mention « ivia Livreur » dans l'app, les outils et la doc (hors historique).
- [ ] Étant donné un premier lancement, alors l'ordre est : splash D00, localisation, présentation
      D01 à D03, connexion par numéro D04. « Passer » mène à la connexion.
- [ ] La connexion se fait par numéro et code à 6 chiffres. Aucun champ e-mail n'apparaît.
- [ ] Étant donné un véhicule choisi, alors le dossier demande exactement les pièces exigées par
      le serveur pour ce véhicule (`/v1/driver/options`). « Envoyer » reste inactif tant qu'une
      pièce, la plaque (sauf vélo), la zone de travail ou le compte de versement manque.
- [ ] Étant donné un dossier envoyé, alors D07 montre les 4 étapes, avec le véhicule et le nombre
      de pièces.
- [ ] Étant donné un livreur validé hors ligne, quand il glisse jusqu'au bout, alors il passe en
      ligne (D09). Un glissement incomplet ne fait rien. « Pause » le repasse hors ligne.
- [ ] Étant donné une mission proposée, alors D10 montre le gain, le compte à rebours, la
      distance, la taille du colis, le retrait et la livraison. Le compte à rebours fini retire la
      proposition. « Glisser pour accepter » et « Refuser » appellent le serveur.
- [ ] Étant donné une course de boutique au retrait, alors « Glisser : colis récupéré » n'est
      actif qu'une fois toutes les cases du colis cochées.
- [ ] Étant donné une course pharmacie au retrait :
      - le code de retrait est affiché en grand ;
      - il n'y a pas de glissière ;
      - quand la pharmacie valide, l'écran passe seul à l'étape suivante et affiche le montant
        avancé.
- [ ] Étant donné une preuve de remise, alors « Confirmer » reste inactif sans les 4 chiffres, et
      sans la case ordonnance quand elle est exigée. Un code faux affiche l'erreur du serveur et
      efface le code.
- [ ] Étant donné une livraison confirmée, alors D15 affiche le gain de la course et les totaux du
      jour. « Rester en ligne » revient à D09, « Faire une pause » passe hors ligne.
- [ ] Étant donné « Client injoignable » avant 10 minutes d'attente ou avant 2 appels, alors le
      message du serveur est affiché et rien ne change.
- [ ] Les onglets Missions, Gains et Profil affichent les données du serveur. Les gains sont
      calculés par jour de Lomé depuis l'historique. Les éléments « masqués » de la spec
      n'apparaissent pas.
- [ ] La barre du bas est claire, et l'onglet actif est bleu avec son libellé.
- [ ] Étant donné « Sonnerie des missions » activée, quand une proposition arrive, alors l'app
      sonne et vibre ; désactivée, elle reste silencieuse. Le choix est gardé sur le téléphone.
- [ ] Chaque écran tient sans débordement avec une police à 200 % sur un écran de 320 dp.
- [ ] Vérification visuelle sur le simulateur iPhone, écran par écran, face aux maquettes.

## Cas limites et erreurs

- **Réseau coupé** :
  - pendant une glissière : elle revient au départ, avec un message « Pas de connexion » ;
  - au lancement : écran hors connexion existant.
- **Proposition expirée ou prise par un autre livreur** pendant le glissement : message, retour à
  la recherche.
- **Mission annulée** (commande annulée) pendant le trajet : message, retour à l'accueil en ligne.
- **Course pharmacie non payée par le client** : le code est affiché, la pharmacie refuse la remise
  (ADR 0014) ; l'écran attend.
- **Ancienne course pharmacie sans code** (acceptée avant la 032) : la glissière « récupéré »
  reste proposée.
- **Code client faux plusieurs fois** : refus du serveur affiché ; « Code refusé » propose
  d'appeler le support.
- **Localisation refusée** : l'accueil en ligne montre la position inconnue et invite à
  l'autoriser (réglages).
- **Dossier refusé ou suspendu** : écrans existants restylés (D07 pour le style).
- **Historique vide** : Missions et Gains affichent un état vide (« Aucune mission pour
  l'instant »), avec des totaux à 0 F.
- **Texte agrandi** : les montants et les libellés passent à la ligne, sans débordement.

## Hors périmètre

- Activité taxi VTC (serveur de Gedeon déjà prêt, écrans dans une autre spec).
- Tout ce qui est « masqué » ci-dessus, en attendant le serveur (liste pour Gedeon).
- Guidage tour par tour dans l'app.
- Remboursement au livreur des avances aux pharmacies (règlement des livreurs, ADR 0014).
- Changement des identifiants techniques de l'app (paquet Android, bundle iOS) : seul le nom
  affiché change, pour ne pas casser les mises à jour.

## Questions ouvertes

<!-- Vide = prêt pour le plan. -->
Aucune.

Décision (2026-11-08) : la liste des zones de travail (id, nom) est ajoutée dans
`GET /v1/driver/options` par cette spec, sans migration ; Gedeon relit (module `delivery`).
