# Community App — Specifiche di progetto

> Stato: **completa per la prima release**. Le questioni ancora da chiarire sono raccolte nella sezione 14, Punti aperti.
> Ultimo aggiornamento: 2026-11-05

## 1. Visione e obiettivi
- L'app supporta un percorso di pratica della community **"La via della trasformazione"**. Il nome del percorso potrebbe cambiare.
- Dimensione prevista: circa **100 partecipanti** e **3-4 admin**.
- Non sono previsti obiettivi misurabili.

## 2. Attori e ruoli
| Ruolo | Descrizione |
|---|---|
| Utente | Membro registrato della community |
| Admin | Modera utenti, pubblica nel Canale Principale, gestisce il Canale di Condivisione |
| Super Admin | Come Admin, in più gestisce i cicli di registrazione e promuove/declassa gli Admin |

- Ogni utente, qualunque sia il ruolo, è **in attesa** oppure **partecipa a un percorso** (sezione 5). Non è un ruolo in più.
- Admin e Super Admin usano anche l'app mobile come partecipanti: leggono il Canale Principale ed entrano nel cerchio.
- Tutti accedono con **email e password**, sia all'app sia al pannello web. Il pannello è riservato agli utenti con ruolo admin o Super Admin.
- Un utente diventa admin quando il Super Admin lo promuove. Non servono account separati.
- Esiste **un solo Super Admin**, creato a mano durante l'installazione. L'account è legato a un **indirizzo email del progetto**. Chi conosce la password di quell'account accede come Super Admin. L'account può essere condiviso dalle persone che lo gestiscono.

## 3. Architettura tecnica
- **App mobile:** Flutter
- **Backend:** Node.js + TypeScript, Fastify v4, Zod per la validazione
- **Database:** PostgreSQL tramite Prisma
- **Autenticazione:** email e password tramite Firebase Authentication. L'email deve essere verificata. Il backend verifica il token Firebase ed emette i propri JWT (access 15 min, refresh 30 giorni). Firebase invia anche le email di verifica e di reimpostazione della password
- **Notifiche push e tempo reale:** Firebase Cloud Messaging, più dispositivi per utente
- **Email:** nella prima release il backend non invia email. Le uniche email sono quelle di accesso, che invia Firebase
- **Pannello admin:** Flutter Web
- **Job pianificati:** node-cron

## 4. Registrazione e accesso
- Registrazione con nome, cognome, email, password e motivazione.
- Prima di entrare l'utente deve **confermare l'email** con il link che riceve.
- La motivazione è utile sia al partecipante, come riflessione personale, sia agli admin, per conoscerlo.
- La registrazione è **sempre aperta**. Chi si registra è un **utente in attesa** finché non partecipa a un percorso (sezione 5).
- L'utente è **attivo subito** e diventa utente in attesa, marcato come "non ancora revisionato". Per entrare in un percorso serve la **revisione** di un admin (sezione 5).
- Se il link di conferma scade, l'utente ne richiede uno nuovo. Il nostro backend non salva nulla finché la registrazione non è completa.
- Chi ha dimenticato la password la reimposta tramite un link ricevuto via email.
- Più dispositivi possono essere connessi contemporaneamente.

### Profilo utente
- L'utente può modificare da solo nome, cognome e motivazione.
- Nella prima release l'**email non si può cambiare**.

## 5. Utenti in attesa, cicli e percorsi

### Percorso e gruppo
- Un **percorso** è il cammino che un **gruppo** fa insieme, dalla data di inizio alla fine.
- Il **giorno del percorso** si conta dalla data di inizio del gruppo: il giorno di inizio è il giorno 1. Lo stesso conteggio regola i post del Canale Principale (sezione 8) e le frasi del percorso (sezione 10).

### Utente in attesa
- Un utente è **in attesa** quando non fa parte di un gruppo attivo: appena registrato, dopo la fine del suo percorso, oppure dopo aver chiesto di partecipare, finché il percorso non comincia.
- Non è un ruolo né uno stato dell'account: è un utente attivo senza gruppo. Anche un admin può essere in attesa; il pannello web resta comunque disponibile per intero.
- Nell'app l'utente in attesa vede **una sola schermata** con:
  - la frase del giorno, presa dalle frasi dell'anno (sezione 10);
  - quante persone hanno chiesto di partecipare al prossimo percorso;
  - il pulsante **"Chiedi di partecipare"**, oppure "Annulla la richiesta" se l'ha già fatta;
  - il profilo, compresa la cancellazione dell'account.
- Non ha accesso a Canale Principale, cerchio e round di conferma.

### Cicli
- Un **ciclo** è la finestra in cui gli utenti in attesa possono chiedere di partecipare a un **percorso preciso**.
- **Solo il Super Admin** apre i cicli. Può esserci un solo ciclo aperto alla volta.
- All'apertura il Super Admin imposta:
  - la **data di chiusura** delle richieste;
  - la **data di inizio** del percorso. La chiusura deve avvenire entro le 00:00 di questa data, quando nasce il gruppo;
  - la **durata** del percorso in giorni, 365 se non indicata.
- Il ciclo si chiude automaticamente alla data di chiusura. Il Super Admin può chiuderlo prima.
- Fino al giorno di inizio il Super Admin può modificare la data di chiusura, la data di inizio e la durata del percorso. Dopo l'inizio non si può modificare nulla.
- Una nuova data di chiusura riapre un ciclo già chiuso, purché non ce ne sia un altro aperto.
- Se cambia la data di inizio, chi ha chiesto di partecipare riceve una notifica.
- Nella prima release un ciclo non si può annullare. Per rinviare il percorso si sposta la data di inizio.
- All'apertura del ciclo tutti gli utenti in attesa ricevono una notifica, ad esempio "Sono aperte le richieste per il percorso che inizia il 12 gennaio".
- A ciclo chiuso il pulsante "Chiedi di partecipare" è disattivato e l'app mostra un messaggio. Il Super Admin può modificarne il testo dal pannello web.

### Richiesta di partecipazione
- Mentre il ciclo è aperto, l'utente in attesa può **chiedere di partecipare**.
- Per entrare nel gruppo serve la **revisione** di un admin: legge la motivazione e segna l'utente come revisionato. La revisione vale una volta sola: chi è già stato revisionato, ad esempio in un percorso precedente, non va revisionato di nuovo.
- Gli admin vedono l'elenco dei richiedenti con la loro motivazione, distinguendo chi è da revisionare. Chi non va accolto si rimuove o si banna, come sempre.
- Chi alla data di inizio non è ancora stato revisionato **non entra nel gruppo**: resta in attesa e la sua richiesta decade.
- Chi viene **rimosso** da un admin mentre ha una richiesta in corso **non può chiedere di nuovo** di partecipare nello stesso ciclo, anche se si registra di nuovo con la stessa email. Potrà farlo dal ciclo successivo.
- L'utente può **annullare** la richiesta fino alla data di inizio, e rifarla finché il ciclo è aperto.
- Gli utenti in attesa vedono in app **quante persone** hanno chiesto di partecipare al prossimo percorso. Il numero si aggiorna, ma non parte una notifica a ogni nuova richiesta.
- Si partecipa a **un percorso alla volta**: chi è in un gruppo attivo non può chiedere di partecipare al successivo. Chi ha già una richiesta in corso per un percorso non ancora iniziato deve annullarla prima di chiedere di partecipare a un altro.
- Il **ban** cancella la richiesta in corso. Chi è **sospeso** la conserva, ma non viene contato tra i richiedenti.

### Gruppi
- Un **gruppo** è l'insieme delle persone che hanno chiesto di partecipare nello **stesso ciclo**.
- Il gruppo nasce alle **00:00 (ora italiana) della data di inizio** con tutti i richiedenti revisionati, che partono insieme dal giorno 1. Chi entra nel gruppo vale come appena confermato.
- Se alla data di inizio non c'è nessun richiedente revisionato, il gruppo non viene creato.
- Più gruppi possono essere attivi contemporaneamente.
- Ogni gruppo ha il **proprio Canale Principale** e il **proprio cerchio**. Un utente vede solo quelli del suo gruppo.
- Ogni gruppo ha i **propri round di conferma**.
- Gli admin gestiscono **tutti i gruppi**.
- Il gruppo **finisce automaticamente** quando è trascorsa la durata impostata all'apertura del ciclo. I membri **tornano in attesa**: perdono l'accesso al Canale Principale e al cerchio del gruppo, che resta archiviato e visibile solo agli admin. Dal giorno dopo ricevono di nuovo le frasi dell'anno e possono chiedere di partecipare a un nuovo percorso.

### Passaggi tra attesa e percorso
```
registrazione ──► IN ATTESA ──(chiede di partecipare, ciclo aperto)──► IN ATTESA CON RICHIESTA
IN ATTESA CON RICHIESTA ──(annulla, prima dell'inizio)──► IN ATTESA
IN ATTESA CON RICHIESTA ──(data di inizio, se revisionato)──► PARTECIPANTE
IN ATTESA CON RICHIESTA ──(data di inizio, non revisionato)──► IN ATTESA
PARTECIPANTE ──(fine del percorso)──► IN ATTESA
```

## 6. Stati dell'utente

### 6.1 Stati dell'account
| Stato | Come ci si arriva | Cosa può fare l'utente | Come se ne esce |
|---|---|---|---|
| **Attivo** | Registrazione, oppure riattivazione da parte di un admin | Usa l'app normalmente, come utente in attesa o come partecipante | Sospensione, ban, rimozione o cancellazione autonoma |
| **Sospeso** | Mancata conferma entro la scadenza di un round, oppure decisione di un admin | Non può usare l'app. Vede solo il messaggio di sospensione | Solo un admin può riattivarlo. Può anche essere bannato o rimosso |
| **Bannato** | Decisione di un admin | Non può usare l'app. Vede solo il messaggio di ban | Solo il Super Admin può revocare il ban, ad esempio in caso di errore |

- **Utente nuovo:** non è uno stato a sé. È un utente attivo non ancora revisionato da un admin. Finché non è revisionato resta in attesa e non può entrare in un percorso.
- La sospensione ha effetto immediato, anche sui dispositivi già collegati.
- Un utente sospeso non entra nei nuovi round di conferma.
- Alla riattivazione, l'utente è considerato in regola con l'ultimo round di conferma senza fare altro.
- Alla revoca del ban, l'utente torna attivo e la sua email esce dall'elenco delle email bloccate.

**Chi può intervenire su chi**
- Sospensione, ban e rimozione si fanno solo su chi ha un **ruolo più basso**. Un admin interviene sugli utenti, il Super Admin anche sugli admin. La revoca del ban resta riservata al Super Admin, sugli utenti e sugli admin. Nessuno interviene su sé stesso né sul Super Admin.
- La **riattivazione** la può fare qualunque admin su chiunque, anche su un altro admin o sul Super Admin sospeso, ma non su sé stesso.
- Nessuno può segnare come revisionato il **proprio account**.
- Nella prima release non c'è un registro delle azioni degli admin.

### 6.2 Uscita dalla community
| Caso | Chi lo decide | Account | Email |
|---|---|---|---|
| **Ban** | Admin | Resta, in stato bannato | Bloccata finché il Super Admin non revoca il ban |
| **Rimozione** | Admin | Eliminato con tutti i dati | Non bloccata per la registrazione. Se aveva una richiesta in corso, non può chiedere di nuovo di partecipare nello stesso ciclo |
| **Cancellazione autonoma** | Utente | Eliminato con tutti i dati | Non bloccata |

- Rimozione e cancellazione autonoma eliminano anche l'**account di accesso in Firebase** (email e password).
- Chi è stato rimosso o ha cancellato l'account può **registrarsi di nuovo subito**. Torna utente in attesa e può chiedere di partecipare a un percorso successivo. Rimozione = fuori dal percorso, si può tornare; ban = fuori per sempre.
- Il ban vale per il **singolo indirizzo email**. Chi usa un altro indirizzo, anche un alias della stessa casella come nome+altro@gmail.com, può registrarsi di nuovo.

### 6.3 Messaggi mostrati agli utenti bloccati
- L'utente sospeso e l'utente bannato vedono un messaggio dedicato con l'**email di contatto** degli admin, ad esempio admin@laviadellatrasformazione.it.
- Il **Super Admin** può modificare dal pannello web il testo di questi messaggi e l'email di contatto.

### 6.4 Passaggi di stato
```
registrazione ──► ATTIVO ──(mancata conferma / admin)──► SOSPESO
                    ▲                                       │
                    └──────────(riattivazione admin)────────┘
ATTIVO o SOSPESO ──(ban admin)──► BANNATO ──(revoca Super Admin)──► ATTIVO
ATTIVO o SOSPESO ──(rimozione admin / cancellazione utente)──► account eliminato
```

## 7. Conferma periodica di appartenenza
- Un admin avvia una **richiesta di conferma** scegliendo il gruppo, la **data di inizio** e la **durata** in giorni.
- La data di inizio è oggi o una data futura, mai passata.
- La **scadenza** è alle **23:59 ora italiana dell'ultimo giorno**. Ad esempio "7 giorni dal 1° novembre" scade il 7 novembre alle 23:59.
- Ogni richiesta è un **round** che coinvolge **tutti gli utenti attivi del gruppo** insieme. Non si inviano richieste a singole persone.
- Un round si può **modificare o annullare finché non è iniziato**. Una volta iniziato non si può più cambiare né annullare.
- Ogni round riguarda **un gruppo**. Può esserci un round in corso per ogni gruppo attivo.
- **Admin e Super Admin** sono esclusi dai round: non li ricevono e non possono essere sospesi per mancata conferma.
- Gli **utenti in attesa** non ricevono round di conferma e non possono essere sospesi per mancata conferma.
- Alla data di inizio l'utente riceve la richiesta con una notifica push. Poi riceve due **promemoria**: 3 giorni prima della scadenza e il giorno della scadenza.
- Se non conferma entro la scadenza, l'account viene sospeso. Solo un admin può riattivarlo. Alla riattivazione l'utente è in regola con il round (sezione 6.1).
- Nel pannello lo **stato del round** mostra la scadenza, chi ha confermato con la data e chi non ancora. È solo consultazione: nessuno può segnare a mano una conferma.
- I nuovi partecipanti entrano in un gruppo solo alla data di inizio di un percorso.

## 8. Canale Principale
- Canale di comunicazione degli admin verso un gruppo. **Ogni gruppo ha il proprio** Canale Principale.
- Gli utenti sono in **sola lettura**.

### Sequenza e modelli
- Gli admin preparano una **sequenza unica di modelli** di post, ad esempio il percorso di un anno. La stessa sequenza vale per tutti i gruppi, ognuno a partire dalla propria data di inizio.
- Ogni modello ha un **giorno del percorso**, ad esempio "giorno 15", e un'**ora** in ora italiana. L'ora è preimpostata alle 08:00 e si può cambiare per ogni modello.
- Un modello ha due soli stati: **bozza** oppure **in sequenza al giorno N**. Le bozze non vengono pubblicate.
- Nella prima release non c'è la pubblicazione immediata e non si scrivono post per un solo gruppo: tutto passa dalla sequenza. Fa eccezione l'annuncio del cerchio (sezione 9).

### Pubblicazione
- Quando un gruppo raggiunge il giorno N all'ora del modello, il modello viene **copiato** nel Canale Principale del gruppo e pubblicato.
- La copia nasce solo al momento della pubblicazione. Nei gruppi non esistono copie in attesa.
- Alla pubblicazione tutti i membri attivi del gruppo ricevono una **notifica push** con titolo «Canale Principale» e, come testo, l'inizio del post (circa 100 caratteri). Questa notifica non si può disattivare.
- Un modello aggiunto o modificato vale solo per i gruppi che non hanno ancora raggiunto quel giorno. Chi l'ha già superato non riceve nulla.
- Se il server è spento all'ora prevista, alla ripartenza pubblica i post arretrati. La notifica parte solo se è ancora lo stesso giorno.

### Post pubblicati
- Le copie pubblicate vivono per conto loro. Gli admin le **modificano o cancellano** solo nel loro gruppo.
- Modificare una copia già pubblicata non manda notifiche.
- Modificare o cancellare un modello non tocca le copie già pubblicate.

### Formato e autore
- I post sono **testo semplice**, senza formattazione. I link vengono riconosciuti e sono cliccabili nell'app.
- Immagini e audio si inseriscono come link esterni nel testo, senza caricamento di file nell'app.
- Il pannello mostra un'**anteprima** del post come apparirà nell'app.
- I partecipanti **non vedono l'autore** dei post. L'autore si vede solo nel pannello.
- Se un admin viene rimosso, i suoi modelli e le sue copie restano dove sono, senza autore. Le bozze restano bozze.

**Release successive:** reazioni ai post con un set ristretto di emoticon scelte; pubblicazione immediata nei gruppi scelti e programmazione a una data e ora precise.

## 9. Canale di Condivisione
- Funziona come un **cerchio di condivisione**: i partecipanti inviano messaggi al gruppo.
- Ha un orario di apertura e uno di chiusura. I messaggi sono visibili solo mentre il canale è aperto.
- **Ogni gruppo ha il proprio cerchio.** Nella prima release tutti i cerchi seguono la **stessa programmazione**.
- Un admin imposta **un solo appuntamento settimanale**: giorno della settimana, ora di inizio e durata, in ora italiana. Ad esempio ogni sabato alle 9:00 per un'ora. Il cerchio si apre e si chiude automaticamente.
- Se la programmazione cambia mentre un cerchio è aperto, quel cerchio finisce all'orario previsto. La modifica vale dal cerchio successivo.
- Non esistono cerchi straordinari fuori programma e non si possono saltare singole date.
- I messaggi sono **solo testo**. Una volta inviati non si possono modificare né cancellare da chi li ha scritti.
- Nella prima release la cadenza è **settimanale**. In una release successiva la cadenza sarà configurabile dagli admin, anche in modo diverso per ogni gruppo.
- Alla chiusura **i messaggi vengono cancellati** definitivamente.
- Si chiude automaticamente all'orario di chiusura. Un avviso di chiusura imminente parte 15 minuti prima. I minuti si impostano nella configurazione del server, non nel pannello.
- **Non è possibile la chiusura anticipata:** il cerchio dura sempre quanto stabilito dalla programmazione.
- All'apertura compare un **post nel Canale Principale** del gruppo che annuncia il cerchio. È un post del solo gruppo, senza modello nella sequenza (sezione 8).
- All'apertura i membri attivi del gruppo ricevono la notifica push «Il cerchio è aperto».
- Chi tocca l'ingresso nel post di annuncio entra nel cerchio e può leggere e scrivere. Il tocco vale come consenso.
- Il post di annuncio resta nel Canale Principale anche dopo la chiusura. In una release successiva verrà rimosso automaticamente.
- Nella prima release non ci sono limiti di lunghezza, né per i messaggi del cerchio né per i post del Canale Principale.
- Tutti gli utenti attivi possono entrare.
- Si può uscire e rientrare. Al rientro non si vede lo storico, solo i messaggi da quel momento.
- Ogni messaggio mostra **nome e cognome** di chi scrive.
- I partecipanti vedono **quante persone** hanno partecipato al cerchio, non l'elenco dei nomi.
- Gli admin **moderano dal pannello**:
  - vedono l'elenco dei cerchi aperti;
  - per ogni cerchio vedono membri e messaggi, aggiornati ogni 10 secondi e con un pulsante «Aggiorna»;
  - cancellano un messaggio con il pulsante «Cancella».
- La moderazione non è in tempo reale.


## 10. Frase del giorno e notifiche

### 10.1 Frase del giorno
- Ogni giorno ogni utente riceve una **frase di Thich Nhat Hanh**.
- Le frasi stanno in **due elenchi separati**:
  - **Frasi dell'anno**, per gli utenti in attesa. Ogni frase è legata a un **giorno di calendario** (giorno e mese, 366 giorni compreso il 29 febbraio) e si ripete ogni anno. Tutti gli utenti in attesa ricevono la stessa frase lo stesso giorno.
  - **Frasi del percorso**, per chi partecipa. Ogni frase è legata a un **giorno del percorso** (1, 2, … N). Un unico elenco vale per tutti i gruppi, ognuno a partire dalla propria data di inizio. Nella prima release non ci sono frasi diverse per gruppo.
- Chi partecipa riceve **solo** le frasi del percorso, non quelle dell'anno. Chi ha chiesto di partecipare riceve le frasi dell'anno fino al giorno 1.
- Nei giorni senza frase non parte nessuna notifica. Dopo l'ultima frase del percorso non arriva più nulla.
- La notifica parte alle **07:00 ora italiana**, uguale per tutti. L'orario si imposta nella configurazione del server.
- Il giorno 1 la notifica annuncia anche l'inizio, ad esempio "Oggi inizia il tuo percorso — giorno 1". Non c'è una notifica separata per l'inizio.
- La frase di oggi si legge anche nell'app, con la sua fonte: nella schermata "In attesa" o nella home del gruppo. Nella prima release non c'è un archivio delle frasi passate.
- L'utente può disattivare dal profilo la notifica della frase, con l'interruttore **"Frase del giorno"**, attivo di default. Le altre notifiche restano attive.

### 10.2 Gestione delle frasi
- **Tutti gli admin** gestiscono le frasi dal pannello web, in due elenchi: Frasi dell'anno e Frasi del percorso.
- Ogni frase si può vedere, modificare e cancellare.
- Le frasi si caricano con un **file CSV**: codifica UTF-8, riga di intestazione, separatore `;`, colonne `giorno;frase;fonte`.
  - Frasi dell'anno: `giorno` nel formato `GG-MM`, ad esempio `05-03` per il 5 marzo.
  - Frasi del percorso: `giorno` è un numero, ad esempio `15`.
  - `fonte` è facoltativa: il libro, ed eventualmente la pagina, da cui viene la frase.
- L'import **aggiorna o inserisce** riga per riga in base al giorno. Le frasi assenti dal file restano come sono.
- Prima di salvare, il pannello mostra un'**anteprima** con gli errori: giorni duplicati, date o numeri non validi, frasi vuote. Se c'è anche un solo errore non si salva nulla.
- Ogni elenco ha anche un pulsante **«Scarica CSV»**, che esporta le frasi nello stesso formato dell'import.

Esempio per le frasi dell'anno:
```
giorno;frase;fonte
01-01;Testo della frase del 1° gennaio;Titolo del libro, p. 12
02-01;Testo della frase del 2 gennaio;
```

- **Diritti d'autore:** i testi di Thich Nhat Hanh sono protetti (Plum Village, Parallax Press). La responsabilità del loro uso è del gruppo di progetto. Per questo ogni frase cita la sua fonte quando è disponibile.

### 10.3 Notifiche
- Nella prima release le notifiche sono **solo push**, tramite Firebase Cloud Messaging. Non si inviano email.

| Evento | Chi la riceve | Quando |
|---|---|---|
| Frase del giorno | Utenti attivi con l'interruttore "Frase del giorno" attivo | Ogni giorno alle 07:00 |
| Apertura di un ciclo | Tutti gli utenti in attesa | All'apertura |
| Cambio della data di inizio | Chi ha chiesto di partecipare | Alla modifica |
| Nuovo post nel Canale Principale | Membri attivi del gruppo | Alla pubblicazione, con titolo «Canale Principale» e l'inizio del post. I post arretrati la mandano solo se è ancora lo stesso giorno |
| Richiesta di conferma | Membri attivi del gruppo, esclusi admin e Super Admin | Alla data di inizio del round |
| Promemoria della conferma | Membri del gruppo che non hanno ancora confermato | 3 giorni prima della scadenza e il giorno della scadenza |
| Apertura del cerchio | Membri attivi del gruppo | All'apertura, con il testo «Il cerchio è aperto» |
| Chiusura imminente del cerchio | Chi è nel cerchio | 15 minuti prima della chiusura, configurabile nel server |

- Altri eventi, l'invio di email e l'orario della frase scelto da ogni utente sono rimandati alle release successive.

## 11. Privacy e dati personali
- Alla registrazione l'utente deve **accettare un'informativa privacy**.
- L'informativa è pubblicata su una **pagina web** del sito laviadellatrasformazione.it. L'app mostra il link durante la registrazione.
- Il testo è scritto e aggiornato dal **Super Admin direttamente sul sito**. Il pannello web non gestisce l'informativa.
- Il progetto è un **gruppo informale**, non un ente. Il **titolare del trattamento** è quindi una persona fisica del gruppo, indicata nell'informativa con i suoi contatti.
- L'utente può **cancellare autonomamente** il proprio account dall'app.
- Alla cancellazione **tutti i dati dell'utente vengono eliminati subito**, compreso l'account di accesso in Firebase con email e password.
- Dopo la cancellazione l'utente può registrarsi di nuovo subito, come utente in attesa. L'email non resta bloccata.

## 12. Requisiti non funzionali
- **Prima release (MVP):** **26 dicembre 2026**. Per l'MVP si sceglie sempre la soluzione più semplice.
- **Piattaforme:** app mobile per iOS e Android, usata dai partecipanti.
- **Pannello di amministrazione:** per ora **tutta l'amministrazione avviene da web**, con **Flutter Web**. In una release successiva sarà disponibile anche dall'app.

### Funzioni del pannello web
- Gestione utenti: revisione, sospensione, riattivazione, ban, revoca del ban, rimozione, con le regole tra admin della sezione 6.1.
- Canale Principale, in due viste:
  - **«Sequenza»**: i modelli ordinati per giorno e ora, comprese le bozze, con creazione, modifica e cancellazione;
  - **«Post dei gruppi»**: scelto un gruppo, attivo o archiviato, i suoi post pubblicati, che si modificano e cancellano solo qui.
  - In entrambe le viste l'anteprima mostra il post come apparirà nell'app.
- Cerchio: programmazione settimanale con giorno, ora di inizio e durata; moderazione dei cerchi aperti (sezione 9).
- Round di conferma di appartenenza, per gruppo: creazione, modifica e annullamento finché il round non è iniziato; stato del round in sola consultazione.
- Gruppi: elenco dei gruppi, attivi e archiviati, e dei loro membri.
- Utenti in attesa: elenco degli utenti in attesa e dei richiedenti del prossimo percorso, con la motivazione.
- Frasi dell'anno e frasi del percorso, con import da CSV ed export nello stesso formato.
- Cicli, solo per il Super Admin: apertura con data di chiusura, data di inizio e durata del percorso; modifica di date e durata fino all'inizio; chiusura anticipata.
- Gestione dei ruoli, solo per il Super Admin.
- Testi dei messaggi per sospesi, bannati e richieste a ciclo chiuso, ed email di contatto, solo per il Super Admin.

### Altri requisiti
- **Lingua:** solo italiano, in tutta l'app e nelle notifiche.
- **Carico:** circa 100 utenti, 3-4 admin.
- **Hosting di backend e database:** **Railway**, regione EU West (Amsterdam). Un progetto con due ambienti, **prova** e **produzione**, ognuno con il proprio backend, il proprio database PostgreSQL e i propri secret. La prova si aggiorna a ogni push su `main`; la produzione solo con un deploy esplicito. Entrambi gli ambienti usano `NODE_ENV=production`.
- **Hosting del pannello web:** **Firebase Hosting**, con un sito in ciascuno dei due progetti Firebase, prova e produzione. Il dominio personalizzato, ad esempio admin.laviadellatrasformazione.it, si collega più avanti.
- **Firebase:** due progetti, `la-via-trasformazione-prova` per lo sviluppo e la prova, `la-via-della-trasformazione` per la produzione. Le chiavi di produzione stanno solo nel gestore di credenziali e nelle variabili di Railway.
- **Budget:** circa 7–12 $ al mese per i due ambienti, con un tetto fisso di 20 $ su Railway. Il primo mese è coperto dal credito di prova. Per il pannello su Firebase Hosting si stima che il traffico resti nella quota gratuita; da verificare.
- **Backup:** giornalieri e settimanali del database di produzione, gestiti da Railway. Prima del lancio si prova un ripristino.
- **Pubblicazione negli store:** il progetto è un gruppo informale, quindi gli account sviluppatore per App Store e Google Play sono **account personali di un referente**, registrati con la **mail di progetto** tech@laviadellatrasformazione.it. Su App Store come venditore compare il nome e cognome del referente. Gli account non esistono ancora. Se in futuro nascerà un ente, Apple e Google permettono di trasferire l'app.
- **Test prima del rilascio:** su iOS l'app viene provata da almeno **3 tester** tramite TestFlight. Su Android Google impone agli account personali nuovi un **test chiuso con almeno 12 tester iscritti per 14 giorni consecutivi** prima di poter pubblicare.

## 13. Release successive
Funzionalità escluse dalla prima release e già decise per il futuro.

| Area | Funzionalità | Riferimento |
|---|---|---|
| Canale Principale | Reazioni ai post con un set ristretto di emoticon | Sezione 8 |
| Canale Principale | Pubblicazione immediata di un post fuori sequenza nei gruppi scelti, anche a un solo gruppo | Sezione 8 |
| Canale Principale | Programmazione di un post fuori sequenza a una data e ora precise | Sezione 8 |
| Canale di Condivisione | Cadenza del cerchio configurabile dagli admin, oltre a quella settimanale | Sezione 9 |
| Canale di Condivisione | Programmazione del cerchio diversa per ogni gruppo | Sezione 9 |
| Canale di Condivisione | Rimozione automatica del post di annuncio dopo la chiusura del cerchio | Sezione 9 |
| Amministrazione | Funzioni admin anche nell'app mobile | Sezione 12 |
| Profilo | Cambio dell'email | Sezione 4 |
| Notifiche | Altri eventi e altri canali di notifica, compresa l'email | Sezione 10 |
| Cicli | Promemoria agli utenti in attesa prima della chiusura delle richieste | Sezione 5 |
| Cicli | Annullamento di un ciclo: le richieste decadono e il gruppo non nasce | Sezione 5 |
| Frase del giorno | Orario della notifica scelto da ogni utente | Sezione 10 |
| Frase del giorno | Archivio delle frasi passate | Sezione 10 |
| Frase del giorno | Frasi del percorso diverse per gruppo | Sezione 10 |

### Possono slittare se i tempi stringono
Fanno parte della prima release, ma possono essere rimandate per rispettare la data del 26 dicembre.

- **Modifica dei testi per sospesi, bannati e richieste a ciclo chiuso.** Se slitta, i testi restano fissi.

La **cancellazione autonoma dell'account non può slittare**. Apple chiede che le app con registrazione permettano di cancellare l'account dall'interno dell'app, e Google Play ha un requisito simile. Senza questa funzione l'app rischia di essere rifiutata dagli store.

## 14. Punti aperti
- Poteri speciali del Super Admin oltre alla gestione di cicli e ruoli: rimandato.
- **Referente del progetto:** la persona che intesta gli account store e fa da titolare del trattamento dei dati. Da scegliere.
- Creazione degli account sviluppatore negli store. Con account personali non serve il numero D-U-N-S, ma su Android il test chiuso di 14 giorni deve partire entro il 20 novembre.
- **Nome del percorso.** Il nome potrebbe cambiare, quindi il documento non lo fissa.
- **Diritti sulle frasi di Thich Nhat Hanh.** Il gruppo di progetto deve verificare che l'invio quotidiano delle frasi sia consentito.
## 15. Differenze tra specifiche e codice attuale
- **Scadenze delle conferme:** nel codice sono fisse da configurazione server, 30 giorni di intervallo e 3 di tolleranza. Le specifiche chiedono che un admin imposti per ogni gruppo data di inizio e durata, con scadenza alle 23:59 dell'ultimo giorno, e che possa modificare o annullare il round finché non è iniziato.
- **Promemoria delle conferme:** il codice invia una sola notifica alla creazione della richiesta. Mancano i due promemoria.
- **Già allineato:** i round di conferma escludono già admin e Super Admin.
- **Nascita del gruppo:** il codice gestisce date e durata del ciclo e la loro modifica fino all'inizio, e il gruppo non nasce più all'apertura. Manca ancora la nascita del gruppo alla data di inizio (#92): finché non c'è, un nuovo ciclo non crea nessun gruppo.
- **Già allineato:** il backend apre e chiude da solo il cerchio di ogni gruppo attivo secondo l'unico appuntamento settimanale, in ora italiana. Una modifica della programmazione vale dal primo appuntamento che inizia dopo la modifica, e un cerchio aperto finisce all'orario previsto. Non esistono più l'apertura manuale né la chiusura anticipata.
- **Già allineato:** l'avviso di chiusura imminente arriva solo a chi è nel cerchio, una volta sola, e la cancellazione dei messaggi alla chiusura è già implementata.
- **Già allineato:** nella sezione Cerchio del pannello gli admin impostano la programmazione e moderano i cerchi aperti di tutti i gruppi: membri e messaggi aggiornati ogni 10 secondi o con «Aggiorna», e «Cancella» su ogni messaggio. La scheda del cerchio nell'app mobile mostra solo lo stato.
- **Lingua delle notifiche:** i testi delle notifiche nel codice sono in inglese.
- **Contenuti del cerchio:** il codice accetta anche un link a media nei messaggi. Le specifiche chiedono solo testo.
- **Storico al rientro nel cerchio:** il codice restituisce tutti i messaggi a chi rientra. Le specifiche chiedono solo quelli successivi al rientro.
- **Numero di partecipanti:** il codice mostra l'elenco membri solo agli admin e non espone il conteggio agli utenti.
- **Cancellazione account:** non esiste una funzione per cancellare il proprio account.
- **Account Firebase alla rimozione:** la rimozione da parte di un admin elimina l'utente dal database ma lascia il suo account di accesso in Firebase.
- **Informativa privacy:** la registrazione non chiede di accettarla.
- **Annuncio del cerchio nel Canale Principale:** il codice non crea un post di annuncio all'apertura del cerchio (#16). La push «Il cerchio è aperto» parte già.
- **Modifica del profilo:** il codice permette di cambiare solo nome e cognome. Manca la motivazione.
- **Pannello web di amministrazione:** esistono la struttura, l'accesso e le sezioni Utenti e gruppi, In attesa, Cicli e Cerchio. Utenti e gruppi ha gruppi e membri, ricerca, filtro dei non revisionati, motivazione, revisione, sospensione, riattivazione, ban, revoca del ban e rimozione. Le altre sezioni sono ancora vuote. Le schermate admin attuali sono ancora nell'app mobile (#27).
- **Già allineato:** le regole su chi può intervenire su chi (sezione 6.1) sono già implementate nel backend e nel pannello.
- **Già allineato:** l'accesso usa email e password tramite Firebase, con email verificata obbligatoria, sia nel backend sia nell'app. Il modello utente ha il campo email e non ha più il numero di telefono.
- **Già allineato:** l'accesso al pannello web usa email e password tramite Firebase ed è riservato ad admin e Super Admin. Le voci del Super Admin si vedono solo con quel ruolo.
- **Messaggio per i sospesi:** il codice mostra un testo fisso in inglese senza email di contatto. Il messaggio per i bannati è anch'esso fisso.
- **Messaggio per registrazione a ciclo chiuso:** il codice restituisce un testo fisso.
- **Socket.IO nell'app mobile:** l'accesso è allineato, perché app e backend usano Firebase con email e password. L'app contiene però ancora il vecchio codice di Socket.IO, mentre il backend usa solo Firebase Cloud Messaging.
- **Gruppi:** il codice lega già utenti e cerchio al gruppo, ma round di conferma e Canale Principale sono ancora unici per tutti. Alla registrazione l'utente non entra più in un gruppo, ma il gruppo non nasce ancora alla data di inizio: per ora nessun nuovo utente entra in un gruppo (#92).
- **Utente in attesa:** la registrazione è sempre aperta e crea un utente in attesa, senza gruppo e non revisionato. App e pannello gestiscono richieste di partecipazione, annullamento, conteggio ed elenco dei richiedenti. Nella schermata "In attesa" manca la frase del giorno (#83), e a ciclo chiuso il messaggio è ancora un testo fisso (#34).
- **Revisione come approvazione:** il codice ha il campo `reviewedByAdmin`, ma non lo usa per decidere chi entra nel gruppo.
- **Fine del gruppo:** il modello ha la data di fine, ma nessun job chiude il gruppo né riporta i membri in attesa. Per questo il pannello non mostra ancora gruppi archiviati.
- **Frase del giorno:** non esistono gli elenchi delle frasi, l'import e l'export in CSV, il job delle 07:00 né l'interruttore nel profilo.
- **Notifiche dei cicli:** il codice non avvisa gli utenti all'apertura di un ciclo né al cambio della data di inizio.
- **Sequenza dei post:** il codice ha un solo elenco di post, comune a tutti, programmati a una data fissa oppure pubblicati subito. Le specifiche chiedono modelli con giorno del percorso e ora, copiati nel Canale Principale di ogni gruppo al momento della pubblicazione, e niente pubblicazione immediata.
- **Notifica dei post:** il codice manda la push «Nuovo post» a tutti gli utenti. Le specifiche chiedono il titolo «Canale Principale», solo ai membri attivi del gruppo, e per i post arretrati solo se è ancora lo stesso giorno.
- **Link a media nei post:** il modello dei post ha il campo `mediaUrl`. Le specifiche lo eliminano: immagini e audio sono link nel testo.
- **Autore dei post:** l'app mostra nome e cognome dell'autore di ogni post del Canale Principale. Le specifiche lo mostrano solo nel pannello.
- **Post di un admin rimosso:** alla rimozione il codice riporta a bozza i post programmati dell'admin. Le specifiche lasciano modelli e copie come sono, senza autore.
- **Messaggi modificabili:** non esiste un modo per far modificare al Super Admin i testi per sospesi e bannati.
- **Cambio di ruolo:** la rotta del backend accetta anche il ruolo Super Admin e non controlla il bersaglio, quindi il Super Admin può declassare sé stesso o nominarne un secondo. Le specifiche prevedono un solo Super Admin (#34).
