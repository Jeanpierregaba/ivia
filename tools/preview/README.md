# Aperçu local (sans émulateur)

## Lancer tout en une commande

```powershell
powershell -ExecutionPolicy Bypass -File tools\lancer.ps1            # démarre tout
powershell -ExecutionPolicy Bypass -File tools\lancer.ps1 -Ouvrir    # … et ouvre le navigateur
powershell -ExecutionPolicy Bypass -File tools\lancer.ps1 -Arreter   # arrête tout
powershell -ExecutionPolicy Bypass -File tools\lancer.ps1 -Reconstruire   # reconstruit tout
powershell -ExecutionPolicy Bypass -File tools\lancer.ps1 -ReparerDocker  # Docker bloqué
```

`lancer.ps1` :
1. démarre Docker Desktop s'il le faut ;
2. reconstruit ce qui a changé depuis la dernière construction (API, back-office, apps web) ;
3. lance l'aperçu (`demarrer.ps1`) ;
4. vérifie que chaque adresse répond.

Sur le poste de Gedeon, des raccourcis à double-cliquer sont sur le bureau : « Lancer ivia »,
« Arreter ivia », « Reconstruire ivia », « Reparer Docker ivia ».

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
