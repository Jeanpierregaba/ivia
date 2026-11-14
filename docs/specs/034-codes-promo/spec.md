# 034 — Codes promo et coupons

<!-- Le QUOI, pas le COMMENT. Lisible par quelqu'un qui ne code pas. -->

## Objectif
Donner aux marchands et à ivia un moyen d'attirer et de fidéliser les acheteurs avec des
réductions, sans jamais fausser ce que touche chacun :
- **le marchand** crée des codes pour sa boutique, dans Ivia Business ; la réduction est prise sur
  ce qu'il reçoit ;
- **ivia** crée depuis le back-office les codes de ses propres produits (boutique officielle IVI,
  gérée au back-office) et offre un coupon de bienvenue à chaque nouveau compte ; ces réductions
  sont à la charge d'ivia, et un marchand reçoit autant que sans code.

## Comportement attendu

### Acheteur (app ivia)
1. À l'écran Commande, avant de payer, un champ « Code promo » : il saisit un code et touche
   « Appliquer ». Le récapitulatif montre la ligne « Réduction (CODE) − X F » et le nouveau total.
   Un code refusé affiche la raison en clair (expiré, minimum non atteint, déjà utilisé…).
2. « Retirer » enlève le code avant le paiement.
3. Profil › « Mes coupons » : les codes que l'acheteur peut utiliser (codes publics en cours et
   coupons qui lui sont réservés), avec la réduction, la boutique concernée, le minimum d'achat et la
   date de fin. « Utiliser » ouvre la boutique (ou l'accueil pour un code ivia) ; le code est
   proposé tout seul à la prochaine commande qui y a droit.
4. Le reçu de la commande affiche la réduction.

### Marchand (Ivia Business)
1. « Codes promo » dans la gestion de sa boutique : liste (actifs, programmés, terminés) avec le
   nombre d'utilisations et le montant total offert.
2. « Créer un code » : le code (ou un code généré), le type (pourcentage ou montant fixe), la
   valeur, le plafond de réduction (pour un pourcentage), le minimum d'achat, les dates de début
   et de fin, le nombre total d'utilisations, le nombre par client, « public » (visible dans « Mes
   coupons ») ou « privé » (à partager soi-même).
3. Il peut suspendre ou terminer un code ; il ne peut plus en modifier la valeur une fois utilisé.

### ivia (back-office)
1. « Codes promo » : mêmes champs que pour un marchand, pour les produits IVI (boutique officielle).
2. Coupon de bienvenue : un code réservé à chaque nouveau compte, valable pour sa première commande
   (réglage : montant, minimum, durée de validité ; désactivable).
3. Liste de tous les codes (ivia et marchands) avec les utilisations ; suspension de n'importe quel
   code (journalisée, motif obligatoire pour un code de marchand).

## Critères d'acceptation
- [ ] Étant donné un code de boutique valide, quand l'acheteur l'applique à une commande de cette
  boutique, alors la réduction est calculée par le serveur, affichée, et le total payé est réduit.
- [ ] Étant donné un code de boutique, quand l'acheteur l'applique à une commande d'une autre
  boutique, alors il est refusé (`promo_not_applicable`).
- [ ] Un code expiré, pas encore commencé, suspendu, épuisé, déjà utilisé le nombre de fois permis
  par ce client, ou sous le minimum d'achat est refusé avec un code d'erreur distinct et un message
  en français.
- [ ] La réduction porte sur les produits, ne dépasse jamais le plafond ni le montant des
  produits, et laisse au moins 100 F à payer.
- [ ] Un seul code par commande.
- [ ] Code d'un marchand : le relevé du marchand compte la réduction en moins de ce qu'il reçoit ;
  la commission d'ivia est calculée sur le montant des produits après réduction.
- [ ] Coupon de bienvenue (payé par ivia) : le marchand reçoit exactement ce qu'il aurait reçu
  sans coupon ; la réduction est à la charge d'ivia et apparaît dans les indicateurs du
  back-office. Un code de la boutique IVI suit la règle d'un code de boutique.
- [ ] Un code de marchand est utilisable dès sa création, sans validation ; un admin peut le
  suspendre.
- [ ] Deux commandes simultanées ne peuvent pas dépasser le nombre total d'utilisations d'un code
  (garanti par la base).
- [ ] Une utilisation n'est comptée qu'au paiement réussi ; une commande non payée, expirée ou
  annulée avant paiement libère le code. Une commande remboursée après paiement ne rend pas
  l'utilisation (le client a profité de la réduction).
- [ ] Un marchand ne voit et ne modifie que les codes de ses boutiques (ceux d'un autre : 404).
- [ ] « Mes coupons » liste les codes publics en cours et les coupons réservés au client, jamais
  les codes privés des autres.
- [ ] Le coupon de bienvenue n'est utilisable qu'une fois, par le compte qui l'a reçu, sur sa
  première commande payée.
- [ ] Toute création, modification et suspension par un admin est journalisée.

## Cas limites et erreurs
- Code en minuscules ou avec des espaces : accepté (comparaison sans casse, espaces retirés).
- Code déjà existant : refusé à la création (`promo_code_taken`), unicité sur toute la plateforme.
- Panier modifié après application du code : la réduction est recalculée ; si le code ne
  s'applique plus (minimum non atteint), il est retiré avec un message.
- Code suspendu entre l'application et le paiement : refusé au paiement, la commande reste à payer
  sans réduction après confirmation de l'acheteur.
- Essais répétés de codes au hasard : limités (10 essais ratés par heure et par compte).
- Commande 100 % offerte par un code : refusée (total minimum de 100 F à payer), pour ne pas créer
  de paiement Mobile Money à 0 F.
- Marchand suspendu ou boutique fermée : ses codes ne s'appliquent plus.
- Réseau coupé pendant l'application : le code n'est pas affiché comme appliqué.

## Hors périmètre
- Cumul de plusieurs codes sur une commande.
- Codes sur l'alerte médicament et les courses pharmacie (à traiter à part, flux de paiement
  différent).
- Parrainage (code personnel et récompense après la première commande du filleul) : lot suivant.
- Cartes cadeaux et porte-monnaie ivia.
- Réductions automatiques sans code (« -10 % sur la catégorie ») : déjà couvert par les promotions
  de produits existantes.

## Décisions (2026-11-12)
- Chaque boutique crée ses codes depuis son compte marchand ; ivia gère depuis le back-office les
  codes de ses produits IVI et le coupon de bienvenue.
- Codes de marchand actifs dès leur création, sans validation ; suspension possible par un admin.
- Coupon de bienvenue dans ce lot, réglable au back-office (désactivé tant qu'il n'est pas réglé).
- Commission d'ivia calculée sur le montant des produits après la réduction d'un code de boutique.

## Questions ouvertes
Aucune.
