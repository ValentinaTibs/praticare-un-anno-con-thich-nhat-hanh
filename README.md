# Community App

App per i partecipanti di un percorso di pratica della community "La via della trasformazione". Comprende un'app mobile per iOS e Android, un pannello web di amministrazione, ancora in sviluppo, e un backend.

- Specifiche di progetto: [docs/specifiche-progetto.md](docs/specifiche-progetto.md)
- Piano di sviluppo: [docs/piano-sviluppo.md](docs/piano-sviluppo.md)
- Lavoro in corso: [issue su GitHub](https://github.com/ValentinaTibs/praticare-un-anno-con-thich-nhat-hanh/issues), raggruppate per fase nelle milestone

> **Stato attuale.** Il progetto è in sviluppo e non è ancora utilizzabile dall'inizio alla fine. I problemi noti sono [su GitHub con l'etichetta bug](https://github.com/ValentinaTibs/praticare-un-anno-con-thich-nhat-hanh/issues?q=is%3Aissue+is%3Aopen+label%3Abug).

## Struttura del repository

| Cartella | Contenuto |
|---|---|
| `backend/` | Server Node.js e TypeScript con Fastify, Prisma e PostgreSQL |
| `mobile/` | App Flutter per i partecipanti e pannello web di amministrazione (`lib/panel/`) |
| `docs/` | Specifiche e piano di sviluppo |

## Requisiti

- **Node.js** 20.6 o successivo. Serve il supporto all'opzione `--env-file`.
- **PostgreSQL** 14 o successivo. In alternativa, **Docker** per avviarlo in un container.
- **Flutter** con Dart 3.3 o successivo.
- Un **progetto Firebase** con accesso tramite email e password e Cloud Messaging attivi. Va chiesto al referente del progetto.
- Per iOS: un Mac con Xcode.

## Backend

Tutti i comandi si lanciano dalla cartella `backend/`.

### 1. Installare le dipendenze

```bash
cd backend
npm install
```

### 2. Avviare PostgreSQL

Se PostgreSQL è già installato, crea un database chiamato `community_app`. Altrimenti avvialo con Docker:

```bash
docker run -d --name community-db \
  -e POSTGRES_USER=community -e POSTGRES_PASSWORD=community -e POSTGRES_DB=community_app \
  -p 5432:5432 postgres:16
```

### 3. Configurare le variabili d'ambiente

```bash
cp .env.example .env
```

Poi modifica `.env`:

| Variabile | Cosa inserire |
|---|---|
| `DATABASE_URL` | Indirizzo del database. Con il container Docker: `postgresql://community:community@localhost:5432/community_app` |
| `JWT_SECRET` | Una stringa casuale di almeno 32 caratteri, ad esempio generata con `openssl rand -hex 32` |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | La chiave di servizio Firebase su una sola riga. Obbligatoria solo in produzione. Vedi sotto |
| `ADMIN_CONTACT_EMAIL` | L'email di contatto mostrata agli utenti bloccati |

Le altre variabili hanno già valori adatti allo sviluppo.

**Chiave di servizio Firebase.** In produzione il server non parte senza una chiave valida. In sviluppo parte anche senza, e lo segnala con un avviso nel log:
- l'accesso con Firebase risponde `503` con il codice `firebase_not_configured`; per entrare si usa `POST /api/auth/dev-login`, attivo solo con `NODE_ENV=development`;
- le notifiche push non partono, ma le operazioni che le inviano vanno a buon fine.

Per ottenere la chiave:

1. Nella console Firebase apri *Impostazioni progetto*, poi *Account di servizio*.
2. Scegli *Genera nuova chiave privata* e scarica il file JSON.
3. Riduci il file a una sola riga e incollalo come valore della variabile:

```bash
jq -c . chiave-firebase.json
```

Non caricare mai la chiave né il file `.env` nel repository.

### 4. Creare le tabelle del database

Applica le migrazioni presenti in `prisma/migrations`:

```bash
npm run db:migrate
```

Lo stesso comando crea una nuova migrazione quando cambia `prisma/schema.prisma`.

### 5. Creare il Super Admin

```bash
npm run db:seed
```

Lo script crea un Super Admin con l'email segnaposto `superadmin@example.com`. Per accedere davvero:

1. Cambia l'email in `prisma/seed.ts` prima di lanciarlo.
2. Crea in Firebase un account con la stessa email e confermala. Il modo più semplice è dall'app: scegli *Crea un account* e apri il link che arriva via email. Gli account aggiunti a mano nella console Firebase, in *Authentication*, poi *Users*, nascono non verificati: al primo accesso dall'app si apre la schermata di conferma, tocca *Invia di nuovo* e apri il link.

### 6. Avviare il server

```bash
npm run dev
```

Il server legge le variabili dal file `.env`, risponde su `http://localhost:3000` e si riavvia a ogni modifica del codice.

### Altri comandi utili

| Comando | A cosa serve |
|---|---|
| `npm run db:studio` | Apre Prisma Studio per consultare il database dal browser |
| `npm test` | Esegue i test su un database PostgreSQL temporaneo, senza bisogno del file `.env` |
| `npm run typecheck` | Controlla i tipi di codice, test, script di installazione e configurazione dei test |
| `npm run build` | Controlla i tipi e compila per la produzione nella cartella `dist/` |

## App mobile

Tutti i comandi si lanciano dalla cartella `mobile/`.

L'app esce solo per Android e iOS. L'identificativo, uguale sulle due piattaforme, è `it.laviadellatrasformazione.app` e non si potrà cambiare dopo la pubblicazione negli store.

### 1. Configurazione Firebase

Firebase serve per l'accesso con email e password e per le notifiche push. Finché il progetto Firebase non esiste, l'app si avvia lo stesso, ma senza accesso e senza notifiche push.

La configurazione si genera con `flutterfire configure`. I file che produce (`lib/firebase_options.dart`, `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`) contengono le chiavi Firebase: git li ignora e non vanno mai aggiunti al repository, che è pubblico.

### 2. Installare le dipendenze

```bash
flutter pub get
```

### 3. Avviare l'app

L'indirizzo del backend si passa con `API_URL`. Il valore dipende da dove gira l'app:

```bash
# Emulatore Android: 10.0.2.2 indica il computer che ospita l'emulatore
flutter run --dart-define=API_URL=http://10.0.2.2:3000

# Simulatore iOS
flutter run --dart-define=API_URL=http://localhost:3000

# Telefono reale sulla stessa rete Wi-Fi: usa l'indirizzo IP del computer
flutter run --dart-define=API_URL=http://192.168.1.10:3000
```

## Pannello web di amministrazione

Il pannello è un'app Flutter Web che vive nel progetto `mobile/`, con un punto d'ingresso suo, `lib/main_panel.dart`. Riusa modelli e chiamate al backend dell'app (`lib/core/`), ma non le sue schermate. L'app mobile, a sua volta, non contiene il codice del pannello. Tutti i comandi si lanciano dalla cartella `mobile/`.

Si entra con l'email e la password dell'app. L'accesso è riservato agli utenti con ruolo admin o Super Admin, e le sezioni di cicli, ruoli e testi si vedono solo dal Super Admin.

### 1. Configurazione

La configurazione Firebase per il web e l'indirizzo del backend stanno in un file JSON per ambiente, in `mobile/config/`. Il file contiene le chiavi Firebase, quindi git lo ignora e non va mai aggiunto al repository. Si chiede al referente del progetto, oppure si rigenera con la CLI di Firebase:

```bash
firebase apps:sdkconfig WEB <id-app-web> --project la-via-trasformazione-prova
```

Il file `config/panel-prova.json` ha questa forma:

```json
{
  "FIREBASE_API_KEY": "...",
  "FIREBASE_APP_ID": "...",
  "FIREBASE_MESSAGING_SENDER_ID": "...",
  "FIREBASE_PROJECT_ID": "la-via-trasformazione-prova",
  "FIREBASE_AUTH_DOMAIN": "la-via-trasformazione-prova.firebaseapp.com",
  "FIREBASE_STORAGE_BUCKET": "...",
  "API_URL": "http://localhost:3000"
}
```

L'app web «Pannello admin» esiste per ora solo nel progetto Firebase di prova. Quella di produzione si crea quando il pannello va pubblicato.

### 2. Avviare il pannello

```bash
flutter run -d chrome -t lib/main_panel.dart --dart-define-from-file=config/panel-prova.json
```

Con Chromium installato come snap, prima va indicato il programma: `export CHROME_EXECUTABLE=/snap/bin/chromium`.

**Accesso di sviluppo.** Con il backend in sviluppo (`NODE_ENV=development`) si può entrare senza Firebase. Aggiungi `--dart-define=DEV_LOGIN=true`: nella pagina di accesso compare un pulsante che usa `POST /api/auth/dev-login` con l'email scritta nel campo. Il pulsante esiste solo nelle build di debug.

### 3. Test

```bash
flutter test
```

