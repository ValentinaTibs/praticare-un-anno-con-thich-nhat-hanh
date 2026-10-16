# Community App

App per i partecipanti di un percorso di pratica della community "La via della trasformazione". Comprende un'app mobile per iOS e Android e un backend. Il pannello web di amministrazione è in fase di sviluppo.

- Specifiche di progetto: [docs/specifiche-progetto.md](docs/specifiche-progetto.md)
- Piano di sviluppo: [docs/piano-sviluppo.md](docs/piano-sviluppo.md)
- Lavoro in corso: [issue su GitHub](https://github.com/ValentinaTibs/praticare-un-anno-con-thich-nhat-hanh/issues), raggruppate per fase nelle milestone

> **Stato attuale.** Il progetto è in sviluppo e non è ancora utilizzabile dall'inizio alla fine. I problemi noti sono [su GitHub con l'etichetta bug](https://github.com/ValentinaTibs/praticare-un-anno-con-thich-nhat-hanh/issues?q=is%3Aissue+is%3Aopen+label%3Abug).

## Struttura del repository

| Cartella | Contenuto |
|---|---|
| `backend/` | Server Node.js e TypeScript con Fastify, Prisma e PostgreSQL |
| `mobile/` | App Flutter per i partecipanti |
| `docs/` | Specifiche e piano di sviluppo |

## Requisiti

- **Node.js** 20.6 o successivo. Serve il supporto all'opzione `--env-file`.
- **PostgreSQL** 14 o successivo. In alternativa, **Docker** per avviarlo in un container.
- **Flutter** con Dart 3.3 o successivo.
- Un **progetto Firebase** con accesso tramite telefono e Cloud Messaging attivi. Va chiesto al referente del progetto.
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
| `FIREBASE_SERVICE_ACCOUNT_JSON` | La chiave di servizio Firebase su una sola riga. Vedi sotto |
| `ADMIN_CONTACT_EMAIL` | L'email di contatto mostrata agli utenti bloccati |

Le altre variabili hanno già valori adatti allo sviluppo.

**Chiave di servizio Firebase.** Il server non parte senza una chiave valida, nemmeno in sviluppo. Per ottenerla:

1. Nella console Firebase apri *Impostazioni progetto*, poi *Account di servizio*.
2. Scegli *Genera nuova chiave privata* e scarica il file JSON.
3. Riduci il file a una sola riga e incollalo come valore della variabile:

```bash
jq -c . chiave-firebase.json
```

Non caricare mai la chiave né il file `.env` nel repository.

### 4. Creare le tabelle del database

La cartella delle migrazioni è ancora vuota. Il primo avvio crea la migrazione iniziale:

```bash
npx prisma migrate dev --name init
```

Nelle esecuzioni successive basta `npm run db:migrate`.

### 5. Creare il Super Admin

```bash
npm run db:seed
```

Lo script crea un Super Admin con un numero di telefono segnaposto. Per accedere davvero, cambia il numero in `prisma/seed.ts` prima di lanciarlo. In alternativa, configura in Firebase un numero di telefono di prova con un codice fisso.

### 6. Avviare il server

```bash
npx tsx watch --env-file=.env src/server.ts
```

Il server risponde su `http://localhost:3000` e si riavvia a ogni modifica del codice. Lo script `npm run dev` non legge il file `.env`, quindi per ora va usato il comando qui sopra.

### Altri comandi utili

| Comando | A cosa serve |
|---|---|
| `npm run db:studio` | Apre Prisma Studio per consultare il database dal browser |
| `npm test` | Esegue i test su un database PostgreSQL temporaneo, senza bisogno del file `.env` |
| `npm run typecheck` | Controlla i tipi di codice, test, script di installazione e configurazione dei test |
| `npm run build` | Controlla i tipi e compila per la produzione nella cartella `dist/` |

## App mobile

Tutti i comandi si lanciano dalla cartella `mobile/`.

### 1. Generare le cartelle delle piattaforme

Il repository contiene solo il codice Dart. Le cartelle `android/`, `ios/` e `web/` vanno generate la prima volta:

```bash
cd mobile
flutter create --platforms=android,ios,web --org it.laviadellatrasformazione .
```

L'identificativo dell'app non è ancora definitivo.

### 2. Aggiungere la configurazione Firebase

Su Android e iOS l'app si collega a Firebase all'avvio. Dalla console Firebase scarica i file di configurazione delle app registrate e copiali qui:

| Piattaforma | File | Destinazione |
|---|---|---|
| Android | `google-services.json` | `mobile/android/app/` |
| iOS | `GoogleService-Info.plist` | `mobile/ios/Runner/` |

Su web l'app non usa Firebase, quindi questo passaggio non serve.

### 3. Installare le dipendenze

```bash
flutter pub get
```

### 4. Avviare l'app

L'indirizzo del backend si passa con `API_URL`. Il valore dipende da dove gira l'app:

```bash
# Emulatore Android: 10.0.2.2 indica il computer che ospita l'emulatore
flutter run --dart-define=API_URL=http://10.0.2.2:3000

# Simulatore iOS o browser
flutter run --dart-define=API_URL=http://localhost:3000
flutter run -d chrome --dart-define=API_URL=http://localhost:3000

# Telefono reale sulla stessa rete Wi-Fi: usa l'indirizzo IP del computer
flutter run --dart-define=API_URL=http://192.168.1.10:3000
```
