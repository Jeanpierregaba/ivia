# Mise en service des alertes push (app pharmacie)

Le code est prêt. Sans cette configuration, l'app reste utilisable : elle relit ses alertes à l'écran, mais ne sonne pas app fermée.

## 1. Projet Firebase

1. Créer un projet sur console.firebase.google.com.
2. Ajouter l'app Android `tg.ivia.ivia_pharmacy` et poser `google-services.json` dans `mobile/apps/pharmacy/android/app/`. Le plugin Gradle s'active tout seul quand ce fichier est présent.
3. Ajouter l'app iOS et poser `GoogleService-Info.plist` dans `mobile/apps/pharmacy/ios/Runner/`.
4. iOS : dans Firebase, déposer une clé APNs. Dans Xcode, activer « Push Notifications » et « Background Modes > Remote notifications ».

## 2. Serveur

Compte de service Firebase (secret : jamais dans le dépôt), sur le serveur :

```
PUSH_SENDER=fcm
FCM_CREDENTIALS_FILE=/chemin/secret/compte-de-service.json
```

## 3. À vérifier sur de vrais téléphones

- Android écran verrouillé, app fermée : l'alerte sonne en son de réveil et s'affiche en plein écran.
- Le son continue jusqu'à l'ouverture, 10 minutes au plus.
- Déconnexion : le téléphone ne reçoit plus d'alertes.
- Après une validation : le push arrive aussi à un dossier en attente.

## 4. Limites connues

- **Google Play** réserve `USE_FULL_SCREEN_INTENT` aux apps d'appel et de réveil : une déclaration est à remplir à la publication, et Google peut la refuser. Sans elle, l'alerte sonne quand même, en notification ordinaire.
- **iOS** n'autorise pas le plein écran. L'alerte est une notification « sensible au temps » avec son. Le mode « alerte critique », qui passe outre le mode silencieux, demande un accord d'Apple.
- **Fabricants Android** (Tecno, Infinix, Itel, Xiaomi…) : leurs économiseurs de batterie peuvent couper l'app. L'écran d'autorisations demande de l'exempter, c'est à tester sur les modèles courants au Togo.
