# Glossario

Termini del dominio dell'app che accompagna il percorso di pratica della community "La via della trasformazione". Le definizioni seguono le [specifiche di progetto](specifiche-progetto.md). Il codice usa nomi inglesi, indicati in _Nel codice_.

## Persone e ruoli

**Utente**:
Persona registrata nell'app, qualunque sia il suo ruolo.
_Evita_: iscritto, account, membro (se non si parla di un gruppo)
_Nel codice_: `User`

**Admin**:
Utente promosso dal Super Admin che modera gli utenti e gestisce Canale Principale, cerchio, round di conferma e frasi.
_Evita_: moderatore, amministratore
_Nel codice_: `Role.admin`

**Super Admin**:
L'unico account che, oltre ai poteri di un admin, gestisce cicli, ruoli e testi dei messaggi per gli utenti bloccati. È legato all'email del progetto e può essere condiviso da più persone.
_Nel codice_: `Role.super_admin`

**Ruolo**:
Il livello di permessi di un utente: utente, admin o Super Admin. Essere in attesa o partecipante non è un ruolo.
_Nel codice_: `Role`

**Referente del progetto**:
La persona fisica del gruppo di progetto che intesta gli account degli store ed è titolare del trattamento dei dati.

**Gruppo di progetto**:
Il gruppo informale di persone che realizza e gestisce l'app. Non è un ente.
_Evita_: associazione

**Tester**:
Persona che prova l'app prima del rilascio, tramite TestFlight su iOS o il test chiuso su Android.

## Registrazione e profilo

**Registrazione**:
La creazione dell'account con nome, cognome, email, password e motivazione. È sempre aperta.
_Evita_: iscrizione

**Motivazione**:
Il testo in cui l'utente spiega perché vuole partecipare. Serve a lui come riflessione e agli admin per conoscerlo.

**Revisione**:
La lettura della motivazione da parte di un admin, che segna l'utente come revisionato. Vale una volta sola ed è necessaria per entrare in un percorso.
_Evita_: approvazione, verifica
_Nel codice_: `reviewedByAdmin`

**Utente nuovo**:
Utente attivo non ancora revisionato. Non è uno stato dell'account.
_Evita_: utente in revisione, utente da approvare

**Informativa privacy**:
Il testo sul trattamento dei dati, pubblicato sul sito del progetto, che l'utente accetta alla registrazione.

## Attesa, cicli e percorsi

**Percorso**:
Il cammino che un gruppo fa insieme, dalla data di inizio alla fine della durata.
_Evita_: corso, programma

**Giorno del percorso**:
Il numero del giorno contato dalla data di inizio del gruppo, dove il giorno di inizio è il giorno 1.
_Evita_: giorno relativo, offset

**Utente in attesa**:
Utente attivo che non fa parte di un gruppo attivo: appena registrato, a percorso finito o in attesa che il percorso richiesto cominci. Non è un ruolo né uno stato dell'account.
_Evita_: lista d'attesa, sala d'attesa

**Partecipante**:
Utente che fa parte di un gruppo attivo.
_Evita_: iscritto, utente del percorso

**Ciclo**:
La finestra di tempo in cui gli utenti in attesa possono chiedere di partecipare a un percorso preciso. Ha una data di chiusura, una data di inizio del percorso e una durata.
_Evita_: ciclo di registrazione, iscrizioni, apertura dell'app
_Nel codice_: `RegistrationCycle`

**Data di chiusura**:
Il giorno in cui il ciclo smette di accettare richieste di partecipazione.

**Data di inizio**:
Il giorno in cui nasce il gruppo e comincia il percorso. È uguale o successiva alla data di chiusura.

**Durata**:
Il numero di giorni del percorso, fissato all'apertura del ciclo. Vale 365 se non indicato.

**Richiesta di partecipazione**:
La domanda con cui un utente in attesa chiede di entrare nel percorso del ciclo aperto. Si può annullare fino alla data di inizio.
_Evita_: candidatura, iscrizione

**Richiedente**:
Utente in attesa che ha una richiesta di partecipazione in corso.

**Gruppo**:
L'insieme delle persone revisionate che hanno chiesto di partecipare nello stesso ciclo e iniziano insieme il percorso. Ha il proprio Canale Principale, il proprio cerchio e i propri round di conferma.
_Evita_: classe, coorte
_Nel codice_: `Group`

**Gruppo attivo**:
Gruppo il cui percorso è iniziato e non è ancora finito.

**Gruppo archiviato**:
Gruppo il cui percorso è finito. Il suo Canale Principale e il suo cerchio restano visibili solo agli admin.

## Stati dell'account e uscite

**Stato dell'account**:
La condizione che decide se un utente può usare l'app: attivo, sospeso o bannato.
_Nel codice_: `UserStatus`

**Attivo**:
Stato in cui l'utente usa l'app normalmente, come utente in attesa o come partecipante.
_Nel codice_: `UserStatus.active`

**Sospeso**:
Stato reversibile in cui l'utente non può usare l'app, per mancata conferma o per decisione di un admin.
_Nel codice_: `UserStatus.suspended`

**Bannato**:
Stato in cui l'utente non può usare l'app e la sua email è bloccata, finché il Super Admin non revoca il ban.
_Nel codice_: `UserStatus.banned`

**Riattivazione**:
Il ritorno allo stato attivo di un utente sospeso, deciso da un admin. Vale come conferma dell'ultimo round.

**Ban**:
L'esclusione di un utente decisa da un admin: l'account resta, in stato bannato, e la sua email non può registrarsi di nuovo.
_Evita_: blocco, espulsione

**Revoca del ban**:
L'annullamento di un ban da parte del Super Admin, che riporta l'utente allo stato attivo.

**Email bloccata**:
Indirizzo email di un utente bannato, che non può essere usato per registrarsi.
_Nel codice_: `BannedEmail`

**Rimozione**:
L'eliminazione dell'account di un utente, con tutti i suoi dati, decisa da un admin. La persona può registrarsi di nuovo subito.
_Evita_: cancellazione, espulsione

**Cancellazione autonoma**:
L'eliminazione del proprio account, con tutti i dati, fatta dall'utente dall'app.
_Evita_: rimozione, disiscrizione

**Messaggio per gli utenti bloccati**:
Il testo che vede un utente sospeso o bannato, con l'email di contatto degli admin.

**Email di contatto**:
L'indirizzo degli admin mostrato agli utenti sospesi e bannati.

## Conferma di appartenenza

**Round di conferma**:
La richiesta, avviata da un admin, con cui tutti i partecipanti attivi di un gruppo devono confermare di voler restare entro una scadenza. Non si può annullare.
_Evita_: richiesta di conferma individuale, verifica
_Nel codice_: `ConfirmationRequest`

**Conferma**:
La risposta con cui un partecipante dichiara di voler restare nel gruppo durante un round.
_Nel codice_: `ConfirmationStatus.confirmed`

**Mancata conferma**:
La conferma non data entro la scadenza del round, che porta alla sospensione.
_Nel codice_: `ConfirmationStatus.missed`

**Scadenza**:
L'ultimo giorno utile per confermare, ricavato dalla data di inizio e dalla durata del round.

**Promemoria**:
La notifica che ricorda di confermare, 3 giorni prima della scadenza e il giorno della scadenza.

## Canale Principale

**Canale Principale**:
Il canale in sola lettura con cui gli admin comunicano con un gruppo.
_Evita_: bacheca, feed, canale admin
_Nel codice_: `MainChannelPost`

**Post**:
Un contenuto di testo, eventualmente con link, pubblicato dagli admin nel Canale Principale.
_Evita_: messaggio (riservato al cerchio)

**Sequenza dei post**:
L'unico elenco di post programmati che ogni gruppo riceve a partire dalla propria data di inizio.

**Post programmato**:
Post della sequenza legato a un giorno del percorso, ad esempio "giorno 15".

**Bozza**:
Post non ancora pubblicato né programmato, visibile solo agli admin.

**Post di annuncio del cerchio**:
Il post che compare nel Canale Principale all'apertura del cerchio e permette di entrarvi.

## Cerchio

**Cerchio**:
Lo spazio in cui i partecipanti di un gruppo si scambiano messaggi di testo, aperto solo negli orari previsti. I messaggi si cancellano alla chiusura. Nelle specifiche si chiama anche Canale di Condivisione.
_Evita_: chat, stanza, round del cerchio
_Nel codice_: `SharingChannel`

**Programmazione del cerchio**:
Il giorno della settimana, l'orario e la durata fissa con cui il cerchio si apre e si chiude da solo.

**Messaggio**:
Il testo scritto da un partecipante nel cerchio, con nome e cognome di chi scrive.
_Evita_: post (riservato al Canale Principale)
_Nel codice_: `SharingChannelPost`

**Ingresso nel cerchio**:
Il tocco sul post di annuncio con cui un partecipante entra nel cerchio aperto. Vale come consenso.

**Avviso di chiusura imminente**:
La notifica che parte poco prima della chiusura del cerchio, di default 15 minuti.

## Frase del giorno

**Frase del giorno**:
Il testo di Thich Nhat Hanh che ogni utente riceve ogni mattina, con la sua fonte.

**Frasi dell'anno**:
L'elenco delle frasi per gli utenti in attesa, una per ogni giorno di calendario, che si ripete ogni anno.

**Frasi del percorso**:
L'elenco delle frasi per i partecipanti, una per ogni giorno del percorso, uguale per tutti i gruppi.

**Fonte**:
Il libro, ed eventualmente la pagina, da cui viene una frase.

## Ambienti e pubblicazione

**Prova**:
L'ambiente usato per provare l'app prima della produzione, con backend, database e progetto Firebase propri.
_Evita_: staging, test

**Produzione**:
L'ambiente usato dalla community reale.

**Pannello web**:
L'applicazione web, riservata ad admin e Super Admin, da cui si svolge tutta l'amministrazione.
_Evita_: dashboard, backoffice, pannello admin

**App mobile**:
L'app per iOS e Android usata da tutti come partecipanti o utenti in attesa.
