# Community App — Specifiche di progetto

> Stato: **completa per la prima release**. Le questioni ancora da chiarire sono raccolte nella sezione 14, Punti aperti.
> Ultimo aggiornamento: 2026-10-16

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

- Admin e Super Admin usano anche l'app mobile come partecipanti: leggono il Canale Principale ed entrano nel cerchio.
- Tutti accedono con il **codice SMS**, sia all'app sia al pannello web. Il pannello è riservato agli utenti con ruolo admin o Super Admin.
- Un utente diventa admin quando il Super Admin lo promuove. Non servono account separati.
- Esiste **un solo Super Admin**, creato a mano durante l'installazione. L'account è legato a un **numero di telefono del progetto**. Chi ha quel telefono riceve il codice SMS e può accedere come Super Admin.

## 3. Architettura tecnica
- **App mobile:** Flutter
- **Backend:** Node.js + TypeScript, Fastify v4, Zod per la validazione
- **Database:** PostgreSQL tramite Prisma
- **Autenticazione:** codice SMS tramite Firebase Phone Authentication. Il backend verifica il token Firebase ed emette i propri JWT (access 15 min, refresh 30 giorni)
- **Notifiche push e tempo reale:** Firebase Cloud Messaging, più dispositivi per utente
- **Email:** servizio di invio da scegliere, necessario per gli avvisi alla lista d'attesa
- **Pannello admin:** Flutter Web
- **Job pianificati:** node-cron

## 4. Registrazione e accesso
- Registrazione con nome, cognome, numero di telefono, email e motivazione.
- La motivazione è utile sia al partecipante, come riflessione personale, sia agli admin, per conoscerlo.
- La registrazione è possibile solo quando un **ciclo di registrazione** è aperto.
- L'utente è **attivo subito**; viene marcato come "non ancora revisionato" per gli admin. La revisione della motivazione è informativa, non un blocco.
- Se l'OTP scade durante la registrazione, l'utente ne richiede uno nuovo e ricomincia. Nessuno stato parziale viene salvato.
- Più dispositivi possono essere connessi contemporaneamente.

### Profilo utente
- L'utente può modificare da solo nome, cognome e motivazione.
- Nella prima release il **numero di telefono non si può cambiare**.

## 5. Cicli di registrazione e gruppi
- I cicli sono definiti dagli admin: si imposta una finestra temporale in cui l'app accetta nuove registrazioni.
- **Solo il Super Admin** apre i cicli di registrazione.
- All'apertura il Super Admin imposta la **data di chiusura**. Il ciclo si chiude automaticamente a quella data.
- All'apertura di un ciclo, i numeri bloccati temporaneamente vengono sbloccati.
- Fuori dal ciclo le nuove registrazioni sono rifiutate; gli utenti esistenti non subiscono effetti.
- Chi prova a registrarsi a ciclo chiuso vede un messaggio e può iscriversi alla lista d'attesa. Il Super Admin può modificare il testo del messaggio dal pannello web.

### Gruppi
- Un **gruppo** è l'insieme degli utenti registrati nello **stesso ciclo di registrazione**.
- Più gruppi possono essere attivi contemporaneamente.
- Ogni gruppo ha il **proprio Canale Principale** e il **proprio cerchio**. Un utente vede solo quelli del suo gruppo.
- Ogni gruppo ha i **propri round di conferma**.
- Gli admin gestiscono **tutti i gruppi**.
- Un gruppo ha una **fine**. Cosa succede ai membri alla fine del gruppo è ancora da decidere.

### Lista d'attesa
- Chi arriva quando il ciclo di registrazione è chiuso entra in una **lista d'attesa**.
- In lista d'attesa la persona compila già **tutti i dati della registrazione**, compresa un'**email**. Quando si apre il ciclo è tutto pronto.
- All'apertura del ciclo la persona entra nel nuovo gruppo e riceve un avviso **via app e via email**.
- Lo stesso vale per chi è stato rimosso o ha cancellato il proprio account: resta in lista d'attesa fino al ciclo successivo, e poi entra nel nuovo gruppo.

## 6. Stati dell'utente

### 6.1 Stati dell'account
| Stato | Come ci si arriva | Cosa può fare l'utente | Come se ne esce |
|---|---|---|---|
| **Attivo** | Registrazione durante un ciclo aperto, oppure riattivazione da parte di un admin | Usa l'app normalmente | Sospensione, ban, rimozione o cancellazione autonoma |
| **Sospeso** | Mancata conferma entro la scadenza di un round, oppure decisione di un admin | Non può usare l'app. Vede solo il messaggio di sospensione | Solo un admin può riattivarlo. Può anche essere bannato o rimosso |
| **Bannato** | Decisione di un admin | Non può usare l'app. Vede solo il messaggio di ban | Solo il Super Admin può revocare il ban, ad esempio in caso di errore |

- **Utente nuovo:** non è uno stato a sé. È un utente attivo non ancora revisionato da un admin. La revisione serve solo a far sapere agli admin chi è arrivato, e non blocca nulla.
- La sospensione ha effetto immediato, anche sui dispositivi già collegati.
- Un utente sospeso non entra nei nuovi round di conferma.
- Alla riattivazione, l'utente è considerato in regola con l'ultimo round di conferma senza fare altro.
- Alla revoca del ban, l'utente torna attivo e il suo numero esce dall'elenco dei numeri bloccati.

### 6.2 Uscita dalla community
| Caso | Chi lo decide | Account | Numero di telefono |
|---|---|---|---|
| **Ban** | Admin | Resta, in stato bannato | Bloccato finché il Super Admin non revoca il ban |
| **Rimozione** | Admin | Eliminato con tutti i dati | Bloccato fino all'apertura del ciclo successivo |
| **Cancellazione autonoma** | Utente | Eliminato con tutti i dati | Bloccato fino all'apertura del ciclo successivo |

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
- Un admin avvia una **richiesta di conferma** indicando una data di inizio e una durata, ad esempio "entro una settimana dal 1° novembre".
- Ogni richiesta è un **round** che coinvolge **tutti gli utenti attivi del gruppo** insieme. Non si inviano richieste a singole persone.
- Un round avviato **non si può annullare**.
- Ogni round riguarda **un gruppo**. Può esserci un round in corso per ogni gruppo attivo.
- L'utente riceve due **promemoria**: 3 giorni prima della scadenza e il giorno della scadenza. Il canale di invio verrà definito nella sezione Notifiche.
- Se non conferma entro la scadenza, l'account viene sospeso. Solo un admin può riattivarlo.
- I nuovi utenti entrano solo durante i cicli di registrazione.

## 8. Canale Principale
- Canale di comunicazione degli admin verso un gruppo. **Ogni gruppo ha il proprio** Canale Principale.
- Gli admin preparano una **sequenza unica di post programmati**, ad esempio il percorso di un anno. Ogni gruppo riceve la stessa sequenza a partire dalla propria data di inizio.
- Ogni post della sequenza si programma per **giorno dall'inizio del gruppo**, ad esempio "giorno 15".
- Nella prima release tutti i gruppi ricevono solo la sequenza. Non si pubblicano contenuti per un solo gruppo.
- I post possono essere bozze, pubblicati subito o programmati.
- Gli admin possono **modificare e cancellare** anche i post già pubblicati.
- Se un admin viene rimosso, i suoi post pubblicati restano senza autore. Quelli programmati tornano bozze finché un altro admin non li recupera.
- Gli utenti sono in **sola lettura**.
- Gli admin pubblicano testi che possono contenere link. Immagini e audio sono inseriti anch'essi come link esterni, senza caricamento di file nell'app.

**Release successive:** reazioni ai post con un set ristretto di emoticon scelte.

## 9. Canale di Condivisione
- Funziona come un **cerchio di condivisione**: i partecipanti inviano messaggi al gruppo.
- Ha un orario di apertura e uno di chiusura. I messaggi sono visibili solo mentre il canale è aperto.
- **Ogni gruppo ha il proprio cerchio.** Nella prima release tutti i cerchi seguono la **stessa programmazione**.
- Un admin imposta una **programmazione settimanale**, ad esempio ogni sabato mattina, con **durata fissa**. Il cerchio si apre e si chiude automaticamente.
- Non esistono cerchi straordinari fuori programma e non si possono saltare singole date.
- I messaggi sono **solo testo**. Una volta inviati non si possono modificare né cancellare da chi li ha scritti.
- Nella prima release la cadenza è **settimanale**. In una release successiva la cadenza sarà configurabile dagli admin, anche in modo diverso per ogni gruppo.
- Alla chiusura **i messaggi vengono cancellati** definitivamente.
- Si chiude automaticamente all'orario di chiusura. Un avviso di chiusura imminente parte 15 minuti prima, configurabile.
- **Non è possibile la chiusura anticipata:** il cerchio dura sempre quanto stabilito dalla programmazione.
- All'apertura compare un **post nel Canale Principale** che annuncia il round del cerchio. Chi tocca l'ingresso in quel post entra nel cerchio e può leggere e scrivere. Il tocco vale come consenso.
- Il post di annuncio resta nel Canale Principale anche dopo la chiusura. In una release successiva verrà rimosso automaticamente.
- Nella prima release non ci sono limiti di lunghezza, né per i messaggi del cerchio né per i post del Canale Principale.
- Tutti gli utenti attivi possono entrare.
- Si può uscire e rientrare. Al rientro non si vede lo storico, solo i messaggi da quel momento.
- Ogni messaggio mostra **nome e cognome** di chi scrive.
- I partecipanti vedono **quante persone** hanno partecipato al cerchio, non l'elenco dei nomi.
- Gli admin possono cancellare messaggi e vedere i membri.


## 10. Notifiche
> Sezione **da definire in una fase successiva**. Per ora le notifiche sono fuori dal perimetro di queste specifiche.

Eventi già emersi da considerare:
- apertura del ciclo per chi è in lista d'attesa, via app e via email;
- promemoria delle conferme di appartenenza;
- avviso di chiusura imminente del cerchio.

## 11. Privacy e dati personali
- Alla registrazione l'utente deve **accettare un'informativa privacy**.
- L'informativa è pubblicata su una **pagina web** del sito laviadellatrasformazione.it. L'app mostra il link durante la registrazione.
- Il testo è scritto e aggiornato dal **Super Admin direttamente sul sito**. Il pannello web non gestisce l'informativa.
- Il progetto è un **gruppo informale**, non un ente. Il **titolare del trattamento** è quindi una persona fisica del gruppo, indicata nell'informativa con i suoi contatti.
- L'utente può **cancellare autonomamente** il proprio account dall'app.
- Alla cancellazione **tutti i dati dell'utente vengono eliminati subito**.
- Dopo la cancellazione l'utente può registrarsi di nuovo al **ciclo successivo**, come avviene per la rimozione da parte di un admin. Per applicare questa regola il numero di telefono resta nell'elenco dei numeri bloccati fino all'apertura del ciclo successivo.

## 12. Requisiti non funzionali
- **Prima release (MVP):** **26 dicembre 2026**. Per l'MVP si sceglie sempre la soluzione più semplice.
- **Piattaforme:** app mobile per iOS e Android, usata dai partecipanti.
- **Pannello di amministrazione:** per ora **tutta l'amministrazione avviene da web**, con **Flutter Web**. In una release successiva sarà disponibile anche dall'app.

### Funzioni del pannello web
- Gestione utenti: revisione, sospensione, riattivazione, ban, revoca del ban, rimozione.
- Sequenza dei post del Canale Principale: bozze, pubblicazione, programmazione relativa all'inizio del gruppo.
- Programmazione del cerchio.
- Round di conferma di appartenenza, per gruppo.
- Gruppi: elenco dei gruppi e dei loro membri.
- Lista d'attesa: elenco delle persone in attesa del prossimo ciclo.
- Cicli di apertura dell'app alle registrazioni, solo per il Super Admin.
- Gestione dei ruoli, solo per il Super Admin.
- Testi dei messaggi per sospesi, bannati e registrazione a ciclo chiuso, ed email di contatto, solo per il Super Admin.

### Altri requisiti
- **Lingua:** solo italiano, in tutta l'app e nelle notifiche.
- **Carico:** circa 100 utenti, 3-4 admin.
- **Hosting e budget:** non ancora scelti. La scelta spetta al team.
- **Pubblicazione negli store:** il progetto è un gruppo informale, quindi gli account sviluppatore per App Store e Google Play sono **account personali di un referente**, registrati con la **mail di progetto**. Su App Store come venditore compare il nome e cognome del referente. Gli account non esistono ancora. Se in futuro nascerà un ente, Apple e Google permettono di trasferire l'app.
- **Test prima del rilascio:** su iOS l'app viene provata da almeno **3 tester** tramite TestFlight. Su Android Google impone agli account personali nuovi un **test chiuso con almeno 12 tester iscritti per 14 giorni consecutivi** prima di poter pubblicare.

## 13. Release successive
Funzionalità escluse dalla prima release e già decise per il futuro.

| Area | Funzionalità | Riferimento |
|---|---|---|
| Canale Principale | Reazioni ai post con un set ristretto di emoticon | Sezione 8 |
| Canale Principale | Contenuti extra fuori sequenza, inviati a un solo gruppo | Sezione 8 |
| Canale di Condivisione | Cadenza del cerchio configurabile dagli admin, oltre a quella settimanale | Sezione 9 |
| Canale di Condivisione | Programmazione del cerchio diversa per ogni gruppo | Sezione 9 |
| Canale di Condivisione | Rimozione automatica del post di annuncio dopo la chiusura del cerchio | Sezione 9 |
| Amministrazione | Funzioni admin anche nell'app mobile | Sezione 12 |
| Profilo | Cambio del numero di telefono | Sezione 4 |
| Notifiche | Definizione completa degli eventi e dei canali di notifica | Sezione 10 |

### Possono slittare se i tempi stringono
Fanno parte della prima release, ma possono essere rimandate per rispettare la data del 26 dicembre.

- **Modifica dei testi per sospesi, bannati e registrazione a ciclo chiuso.** Se slitta, i testi restano fissi.
- **Revoca del ban dal pannello.** Se slitta, la revoca si fa a mano sul database su richiesta del Super Admin.

La **cancellazione autonoma dell'account non può slittare**. Apple chiede che le app con registrazione permettano di cancellare l'account dall'interno dell'app, e Google Play ha un requisito simile. Senza questa funzione l'app rischia di essere rifiutata dagli store.

## 14. Punti aperti
- Poteri speciali del Super Admin oltre alla gestione di cicli e ruoli: rimandato.
- Hosting e budget.
- **Referente del progetto:** la persona che intesta gli account store e fa da titolare del trattamento dei dati. Da scegliere.
- Creazione degli account sviluppatore negli store. Con account personali non serve il numero D-U-N-S, ma su Android il test chiuso di 14 giorni deve partire entro il 20 novembre.
- **Fine di un gruppo.** Quando finisce un gruppo e cosa succede ai suoi membri: decisione rimandata.
- **Nome del percorso.** Il nome potrebbe cambiare, quindi il documento non lo fissa.

## 15. Differenze tra specifiche e codice attuale
- **Scadenze delle conferme:** nel codice sono fisse da configurazione server, 30 giorni di intervallo e 3 di tolleranza. Le specifiche chiedono che un admin imposti data di inizio e durata.
- **Promemoria delle conferme:** il codice invia una sola notifica alla creazione della richiesta. Mancano i due promemoria.
- **Chiusura automatica dei cicli:** il codice non prevede una data di chiusura. Il ciclo si chiude solo a mano.
- **Programmazione ricorrente del cerchio:** il codice prevede solo l'apertura manuale da parte di un admin.
- **Già allineato:** la cancellazione dei messaggi alla chiusura del cerchio è già implementata.
- **Lingua delle notifiche:** i testi delle notifiche nel codice sono in inglese.
- **Contenuti del cerchio:** il codice accetta anche un link a media nei messaggi. Le specifiche chiedono solo testo.
- **Apertura manuale del cerchio:** il codice permette a un admin di aprire il cerchio quando vuole. Le specifiche escludono i cerchi fuori programma.
- **Storico al rientro nel cerchio:** il codice restituisce tutti i messaggi a chi rientra. Le specifiche chiedono solo quelli successivi al rientro.
- **Numero di partecipanti:** il codice mostra l'elenco membri solo agli admin e non espone il conteggio agli utenti.
- **Cancellazione account:** non esiste una funzione per cancellare il proprio account.
- **Informativa privacy:** la registrazione non chiede di accettarla.
- **Chiusura anticipata del cerchio:** il codice permette a un admin di chiudere il cerchio in anticipo. Le specifiche lo escludono.
- **Annuncio del cerchio nel Canale Principale:** il codice non crea un post di annuncio all'apertura del cerchio.
- **Modifica del profilo:** il codice permette di cambiare solo nome e cognome. Manca la motivazione.
- **Pannello web di amministrazione:** non esiste. Le schermate admin attuali sono solo nell'app mobile.
- **Accesso al pannello web:** l'accesso con codice SMS esiste già. Va costruito il pannello e il controllo del ruolo all'ingresso.
- **Messaggio per i sospesi:** il codice mostra un testo fisso in inglese senza email di contatto. Il messaggio per i bannati è anch'esso fisso.
- **Revoca del ban:** il codice non prevede di revocare un ban.
- **Messaggio per registrazione a ciclo chiuso:** il codice restituisce un testo fisso.
- **App mobile e backend disallineati:** l'app usa ancora il vecchio flusso SMS e Socket.IO. Il backend si aspetta il token di Firebase Phone Authentication e usa solo Firebase Cloud Messaging. Oggi l'accesso dall'app non può funzionare.
- **Gruppi:** il codice non lega gli utenti al ciclo in cui si sono registrati. Round di conferma, Canale Principale e cerchio sono unici per tutti.
- **Lista d'attesa:** non esiste. A ciclo chiuso il codice rifiuta semplicemente la registrazione.
- **Sequenza unica dei post:** il codice programma ogni post a una data fissa. Le specifiche chiedono un giorno relativo all'inizio del gruppo.
- **Email:** il modello utente non ha un campo email e il backend non invia email.
- **Messaggi modificabili:** non esiste un modo per far modificare al Super Admin i testi per sospesi e bannati.
