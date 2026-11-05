# Mise en service de WhatsApp (codes de connexion)

Le code est prêt (ADR 0012). Il reste 3 valeurs à mettre en configuration, jamais dans le code.

## Numéro expéditeur

**+228 99 30 99 45** (compte WhatsApp Business « docteur_godway »).

> Le nom d'utilisateur `@docteur_godway` ne suffit pas à l'API. Elle demande l'**identifiant
> du numéro** (phone number ID), un nombre d'environ 15 chiffres.

## Ce qu'il faut récupérer (15 minutes, dans Meta)

1. **Créer l'app** : sur https://developers.facebook.com, menu « Mes apps », puis « Créer une app ».
   Choisir le type « Business » et ajouter le produit **WhatsApp**.
2. **Ajouter le numéro** : dans « WhatsApp › Configuration de l'API », ajouter le numéro
   +228 99 30 99 45.
   - Meta envoie un code de vérification à ce numéro.
   - Le numéro ne doit plus être utilisé dans l'application WhatsApp Business du téléphone : il
     passe sur l'API.
3. **Phone number ID** : il s'affiche sous le numéro. Le mettre dans `WHATSAPP_PHONE_NUMBER_ID`.
4. **Jeton système** : c'est une clé permanente qui autorise le serveur ivia à envoyer des messages
   au nom du compte. Pour l'obtenir :
   - aller dans Business Manager › Paramètres › Utilisateurs › **Utilisateurs système** ;
   - choisir « Ajouter », rôle Admin ;
   - choisir « Générer un jeton » : sélectionner l'app, cocher `whatsapp_business_messaging` et
     `whatsapp_business_management`, et choisir une expiration « Jamais ».
   - Le jeton est un secret : le mettre dans `infra/secrets/whatsapp_access_token` (lancer
     `sudo ./init-secrets.sh`), jamais dans Git ni dans un message.
5. **Moyen de paiement** : l'ajouter dans « WhatsApp › Paramètres de paiement ». Les messages
   d'authentification sont facturés environ 0,02 € pièce.

## Modèle de message (créé par nous)

Les codes passent obligatoirement par un modèle de catégorie **AUTHENTICATION**. Pour cette
catégorie, Meta fixe lui-même le texte : « *123456* est votre code de vérification. Pour votre
sécurité, ne le communiquez pas. Ce code expire dans 5 minutes. », avec un bouton « Copier le
code ». Le modèle se crée une fois, avec le jeton et l'identifiant du compte WhatsApp Business
(WABA ID, affiché dans « Configuration de l'API ») :

```sh
curl -X POST "https://graph.facebook.com/v21.0/$WABA_ID/message_templates" \
  -H "Authorization: Bearer $(cat infra/secrets/whatsapp_access_token)" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ivia_code",
    "language": "fr",
    "category": "AUTHENTICATION",
    "components": [
      { "type": "BODY", "add_security_recommendation": true },
      { "type": "FOOTER", "code_expiration_minutes": 5 },
      { "type": "BUTTONS", "buttons": [ { "type": "OTP", "otp_type": "COPY_CODE", "text": "Copier le code" } ] }
    ]
  }'
```

L'approbation prend en général quelques minutes. On peut la suivre dans « WhatsApp › Modèles de
message ».

## Configuration de production (`infra/.env`)

```
PHONE_OTP_SENDER=whatsapp
WHATSAPP_PHONE_NUMBER_ID=<phone number ID>
WHATSAPP_TEMPLATE=ivia_code
WHATSAPP_TEMPLATE_LANG=fr
SMS_SENDER=none        # fournisseur SMS à brancher plus tard
```

**SMS en attendant le fournisseur** : le bouton « Recevoir par SMS » reste affiché. Tant que le
fournisseur n'est pas branché, l'envoi par SMS échoue et le code part par WhatsApp.
