# Community App

App per i partecipanti di un percorso di pratica della community "La via della trasformazione". Comprende un'app mobile per iOS e Android, un pannello web di amministrazione, ancora in sviluppo, e un backend.

- Specifiche di progetto: [docs/specifiche-progetto.md](docs/specifiche-progetto.md)
- Piano di sviluppo: [docs/piano-sviluppo.md](docs/piano-sviluppo.md)
- Glossario dei termini del dominio: [docs/glossario.md](docs/glossario.md)
- Stile grafico dell'app mobile: [docs/design-lanterna.md](docs/design-lanterna.md)
- Lavoro in corso: [issue su GitHub](https://github.com/ValentinaTibs/praticare-un-anno-con-thich-nhat-hanh/issues), raggruppate per fase nelle milestone

> **Stato attuale.** Il progetto è in sviluppo e non è ancora utilizzabile dall'inizio alla fine. I problemi noti sono [su GitHub con l'etichetta bug](https://github.com/ValentinaTibs/praticare-un-anno-con-thich-nhat-hanh/issues?q=is%3Aissue+is%3Aopen+label%3Abug).

## Struttura del repository

| Cartella | Contenuto |
|---|---|
| `backend/` | Server Node.js e TypeScript con Fastify, Prisma e PostgreSQL |
| `mobile/` | App Flutter per i partecipanti e pannello web di amministrazione (`lib/panel/`) |
| `docs/` | Specifiche, piano di sviluppo, glossario e stile grafico |

## Requisiti

- **Node.js** 20.6 o successivo. Serve il supporto all'opzione `--env-file`.
- **PostgreSQL**: per lo sviluppo non serve installarlo, lo avvia `npm run db:start`. In alternativa PostgreSQL 14 o successivo, oppure **Docker**.
- **Flutter** con Dart 3.3 o successivo.
- L'accesso al **progetto Firebase** di prova, `la-via-trasformazione-prova`, con accesso tramite email e password e Cloud Messaging attivi. Chiavi e file di configurazione si chiedono a chi gestisce gli account del progetto, che li custodisce in Bitwarden.
- Per iOS: un Mac con Xcode.

## Backend

Tutti i comandi si lanciano dalla cartella `backend/`.

### 1. Installare le dipendenze

```bash
cd backend
npm install
```

### 2. Avviare PostgreSQL

Il modo più semplice è il database di sviluppo incluso nel progetto, che non richiede né un'installazione né Docker:

```bash
npm run db:start
```

Resta in esecuzione finché non premi Ctrl+C, quindi lancialo in un terminale a parte. I dati restano nella cartella `backend/.dev-db` anche dopo averlo fermato.

In alternativa, con PostgreSQL già installato crea un database chiamato `community_app`, oppure avvialo con Docker:

```bash
docker run -d --name community-db \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=community_app \
  -p 5432:5432 postgres:16
```

### 3. Configurare le variabili d'ambiente

```bash
cp .env.example .env
```

Poi modifica `.env`:

| Variabile | Cosa inserire |
|---|---|
| `DATABASE_URL` | Indirizzo del database. Con `npm run db:start` o con il container Docker va bene il valore di `.env.example` |
| `JWT_SECRET` | Una stringa casuale di almeno 32 caratteri, ad esempio generata con `openssl rand -hex 32` |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | La chiave di servizio Firebase su una sola riga. Obbligatoria solo in produzione. Vedi sotto |
| `ADMIN_CONTACT_EMAIL` | L'email di contatto mostrata agli utenti sospesi e bannati. Negli ambienti online è la mail di progetto, tech@laviadellatrasformazione.it |
| `SUPER_ADMIN_EMAIL`, `SUPER_ADMIN_NAME`, `SUPER_ADMIN_SURNAME` | Email, nome e cognome del Super Admin, usati da `npm run db:seed`. L'email deve essere una casella vera: serve per accedere |

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

Lo script crea il Super Admin con email, nome e cognome presi da `SUPER_ADMIN_EMAIL`, `SUPER_ADMIN_NAME` e `SUPER_ADMIN_SURNAME`. Se una di queste variabili manca, si ferma con un errore. Si può rilanciare senza problemi:
- se c'è già un Super Admin con un'email segnaposto, ad esempio `superadmin@example.com` dei dati di prova, gli dà email, nome e cognome indicati;
- se c'è già un Super Admin con un'altra email, non lo modifica e non ne crea un secondo;
- se l'email appartiene già a un altro utente, si ferma senza modificare niente.

Per accedere come Super Admin:

1. Imposta le tre variabili e lancia lo script.
2. Crea in Firebase un account con la stessa email e confermala. Il modo più semplice è dall'app: scegli *Crea un account* e apri il link che arriva via email. Gli account aggiunti a mano nella console Firebase, in *Authentication*, poi *Users*, nascono non verificati: al primo accesso dall'app si apre la schermata di conferma, tocca *Invia di nuovo* e apri il link.

**Su Railway.** Il database non è raggiungibile da fuori, quindi lo script si lancia dentro il container del backend, via SSH. La prima volta registra la tua chiave SSH pubblica sull'account Railway, ad esempio indicandone l'impronta letta con `ssh-keygen -lf ~/.ssh/id_rsa.pub`:

```bash
railway ssh keys add --key <impronta> --name <nome>
```

Poi, dalla cartella `backend`, con l'ambiente giusto al posto di `prova`:

```bash
railway ssh --service backend --environment prova -- \
  "cd /app && SUPER_ADMIN_EMAIL=... SUPER_ADMIN_NAME=... SUPER_ADMIN_SURNAME=... npx tsx prisma/seed.ts"
```

Le variabili valgono solo per quel comando, quindi non serve aggiungerle al servizio.

### Dati di prova (facoltativo)

```bash
npm run db:seed:mock
```

Lo script riempie il database locale con utenti inventati: un gruppo attivo e uno archiviato, sospesi e bannati, utenti in attesa, un ciclo aperto e 12 richieste di partecipazione. Aggiunge solo ciò che manca e non modifica ciò che esiste, quindi si può rilanciare. Se il ciclo aperto è scaduto ne crea uno nuovo. Una richiesta annullata di un utente di prova torna al lancio successivo.

Funziona solo su un database locale: con un altro `DATABASE_URL`, o con `NODE_ENV=production`, si ferma con un errore. Per entrare con questi utenti serve l'accesso di sviluppo.

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
| `npm run lint` | Controlla il codice con ESLint |
| `npm run build` | Controlla i tipi e compila per la produzione nella cartella `dist/` |

## Ambienti online

Backend e database stanno su **Railway**, nella regione EU West, nel progetto `la-via-della-trasformazione`. Ci sono due ambienti, ognuno con il proprio backend e il proprio database PostgreSQL:

| Ambiente | Indirizzo del backend | Aggiornamento | Progetto Firebase |
|---|---|---|---|
| `prova` | https://backend-prova.up.railway.app | Automatico a ogni push su `main` | `la-via-trasformazione-prova` |
| `production` | https://backend-production-e4888ae3.up.railway.app | Solo a mano, dalla console di Railway | `la-via-della-trasformazione` |

Prima di ogni rilascio Railway applica le migrazioni con `npx prisma migrate deploy`. Lo stato del servizio si controlla su `/health`.

Le variabili d'ambiente, segreti compresi, si impostano nella console di Railway o con la CLI, ad esempio:

```bash
railway variables --service backend --environment prova --set NOME=valore
```

Ogni modifica a una variabile fa ripartire il backend di quell'ambiente. Le credenziali di produzione le conoscono solo due persone del gruppo: chi sviluppa usa quelle di prova.

## App mobile

Tutti i comandi si lanciano dalla cartella `mobile/`.

L'app esce solo per Android e iOS. L'identificativo, uguale sulle due piattaforme, è `it.laviadellatrasformazione.app` e non si potrà cambiare dopo la pubblicazione negli store.

### 1. Configurazione Firebase

Firebase serve per l'accesso con email e password e per le notifiche push.

La configurazione si genera con `flutterfire configure`, oppure si chiede a chi gestisce gli account del progetto. I file che produce (`lib/firebase_options.dart`, `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`) contengono le chiavi Firebase: git li ignora e non vanno mai aggiunti al repository, che è pubblico. Senza `lib/firebase_options.dart` l'app non compila.

Se Firebase non riesce a partire, l'app si avvia lo stesso, ma senza accesso e senza notifiche push.

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

L'indirizzo dell'informativa privacy, mostrato nella registrazione, si passa con `PRIVACY_POLICY_URL`. Se manca, l'app usa `https://laviadellatrasformazione.it/privacy`, un valore provvisorio finché la pagina non è pubblicata.

## Pannello web di amministrazione

Il pannello è un'app Flutter Web che vive nel progetto `mobile/`, con un punto d'ingresso suo, `lib/main_panel.dart`. Riusa modelli e chiamate al backend dell'app (`lib/core/`), ma non le sue schermate. L'app mobile, a sua volta, non contiene il codice del pannello. Tutti i comandi si lanciano dalla cartella `mobile/`.

Si entra con l'email e la password dell'app. L'accesso è riservato agli utenti con ruolo admin o Super Admin, e le sezioni di cicli, ruoli e testi si vedono solo dal Super Admin.

### 1. Configurazione

La configurazione Firebase per il web e l'indirizzo del backend stanno in un file JSON per ambiente, in `mobile/config/`. Il file contiene le chiavi Firebase, quindi git lo ignora e non va mai aggiunto al repository. Si chiede a chi gestisce gli account del progetto, oppure si rigenera con la CLI di Firebase:

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

