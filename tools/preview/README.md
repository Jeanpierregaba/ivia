# Aperçu local (sans émulateur)

Toute la plateforme dans le navigateur. Pour la vue téléphone, utiliser le mode appareil de Chrome (ou `/iphone` pour un cadre).

1. Lancer Docker Desktop.
2. Construire les apps (une fois, puis après chaque changement), depuis `mobile/apps/<app>` :
   `flutter build web --profile --no-web-resources-cdn --dart-define=API_BASE_URL=http://localhost:<port> --dart-define=IVIA_DEV_OTP=true --dart-define=IVIA_DEV_PAYMENT=true`
3. Construire l'API (`go build -o bin/api.exe ./cmd/api` dans `backend/`) et le back-office (`pnpm build` dans `admin/`).
4. `powershell -File tools\preview\demarrer.ps1` (arrêt : `-Stop`).

| App | Adresse |
| --- | --- |
| ivia | http://localhost:3001 |
| Ivia Business | http://localhost:3002 |
| Livreur | http://localhost:3003 |
| Pharmacie | http://localhost:3004 |
| Back-office | http://localhost:3000 |

Local uniquement : codes de connexion remplis seuls, paiements validés par le faux prestataire,
pharmacies de démonstration (`manage seed-demo`) qui répondent aux alertes.

`<port>` est le port de l'app construite (tableau ci-dessus).
