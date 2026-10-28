# Piano di sviluppo — Prima release

> Obiettivo: pubblicare la prima release negli store il **26 dicembre 2026**.
> Riferimento: [specifiche-progetto.md](specifiche-progetto.md), in particolare la sezione 15 con le differenze tra specifiche e codice.
> Redatto il 2026-10-16. Aggiornato il 2026-10-28 con l'utente in attesa e la frase del giorno.

## In sintesi
- Mancano **10 settimane** al rilascio.
- Il backend esistente è piccolo e ben impostato, ma va esteso parecchio: i **gruppi** toccano quasi tutte le funzionalità.
- Il **pannello web** va costruito da zero.
- L'**utente in attesa** sostituisce la lista d'attesa e toglie l'invio di email dalla prima release. Il lavoro nuovo è la **frase del giorno**: due elenchi di frasi, import da CSV e un job giornaliero.
- L'**app mobile** e il backend usano già lo stesso accesso, con email e password tramite Firebase. Nell'app resta da eliminare il vecchio codice di Socket.IO.
- Il vincolo più rigido è esterno: gli **store**. Per stare tranquilli l'app va inviata in revisione entro **venerdì 11 dicembre**, prima del rallentamento natalizio delle revisioni Apple.

## Calendario

| Settimana | Date | Backend | App mobile | Pannello web | Gruppo di progetto |
|---|---|---|---|---|---|
| 1 | 19–25 ott | Modello dati con gruppi | Accesso con Firebase | — | Apre gli account store e sceglie l'hosting |
| 2 | 26 ott–1 nov | Cicli con data di inizio, utente in attesa, richieste di partecipazione | Registrazione e schermata "In attesa" | — | Crea la casella admin@, inizia a raccogliere le frasi in CSV |
| 3 | 2–8 nov | Sequenza dei post, conferme, frasi e job della frase del giorno | Canale Principale del gruppo, frase del giorno | Accesso e struttura | Pubblica la pagina privacy sul sito |
| 4 | 9–15 nov | Cerchio programmato, fine del gruppo | Cerchio e conferme | Utenti, gruppi e utenti in attesa | Prepara i primi post della sequenza |
| 5 | 16–22 nov | Testi in italiano, cancellazione account | Profilo con interruttore della frase, messaggi di blocco, cancellazione account. **Test chiuso Android con 12 tester entro il 20 nov** | Sequenza dei post, conferme, frasi con import CSV | Carica le frasi nel pannello |
| 6 | 23–29 nov | Rifiniture e test automatici | Rifiniture | Cerchio, cicli, ruoli, testi | Prepara testi e immagini per gli store |
| 7 | 30 nov–6 dic | Correzioni | Prima versione ai tester iOS | Prima versione agli admin | I tester iOS provano l'app, il test chiuso Android prosegue |
| 8 | 7–13 dic | Correzioni | **Invio agli store entro l'11 dic** | Correzioni | Gli admin provano il pannello |
| 9 | 14–20 dic | Messa in produzione | Eventuali correzioni chieste dagli store | Messa in produzione | Prepara il primo ciclo di registrazione |
| 10 | 21–26 dic | Margine di sicurezza | **Pubblicazione il 26 dic** | — | Apre il primo ciclo |

## Fasi di lavoro

### Fase 0 — Prerequisiti esterni (da subito)
Sono a carico del gruppo di progetto, che è informale e non un ente. Non dipendono dallo sviluppo e sono il rischio più grande per la data.

- **Mail di progetto** tech@laviadellatrasformazione.it, usata per registrare tutti gli account, compreso il progetto Firebase.
- **Referente del progetto**, che intesta gli account store e fa da titolare del trattamento dei dati.
- **Account Apple Developer** personale del referente. Non serve il numero D-U-N-S.
- **Account Google Play** personale del referente, con verifica dell'identità. Prima della pubblicazione richiede un test chiuso con 12 tester per 14 giorni.
- **Hosting** per backend, database e pannello web.
- Casella **admin@laviadellatrasformazione.it**. Non serve un servizio di invio email.
- **Frasi di Thich Nhat Hanh** in due file CSV, frasi dell'anno e frasi del percorso, con la verifica dei diritti d'uso.
- **Progetto Firebase** con accesso tramite email e password attivo. I modelli delle email di verifica e di reimpostazione della password vanno tradotti in italiano.
- **Pagina dell'informativa privacy** sul sito laviadellatrasformazione.it.
- **Indirizzo email del progetto** per l'account del Super Admin.

### Fase 1 — Fondamenta (settimane 1–2)
Va fatta per prima, perché tutto il resto dipende da qui.

- **Riallineare l'accesso.** Fatto: l'app accede con email e password tramite Firebase e invia il token al backend. Resta da eliminare il vecchio codice di Socket.IO dall'app.
- **Cicli.** Il Super Admin imposta data di chiusura delle richieste, data di inizio e durata del percorso. Il ciclo si chiude da solo e le date si possono spostare fino all'inizio.
- **Utente in attesa.** La registrazione è sempre aperta e crea un utente senza gruppo. Mentre il ciclo è aperto l'utente chiede di partecipare o annulla la richiesta. Gli utenti in attesa vedono quanti sono i richiedenti.
- **Gruppi.** Il gruppo nasce alla data di inizio con tutti i richiedenti, e finisce dopo la durata impostata riportando i membri in attesa.
- **Blocco temporaneo.** Si elimina: chi è rimosso o cancella l'account può registrarsi di nuovo subito. Resta solo il ban.
- **Registrazione.** Si aggiunge l'accettazione dell'informativa privacy. L'email c'è già, perché è anche il dato di accesso.

### Fase 2 — Funzionalità del backend (settimane 3–5)
- **Canale Principale.** Sequenza unica di post programmati per giorno dall'inizio del gruppo. Ogni gruppo vede la sequenza secondo la propria data di inizio.
- **Conferme.** Round per gruppo, avviato da un admin con data di inizio e durata. Due promemoria e sospensione automatica alla scadenza. Un round non si annulla.
- **Cerchio.** Un cerchio per gruppo, con programmazione settimanale comune e durata fissa. Apertura e chiusura automatiche, annuncio nel Canale Principale, solo testo. Al rientro si vedono solo i messaggi nuovi. Gli utenti vedono il numero di partecipanti. Si eliminano l'apertura e la chiusura manuali.
- **Stati dell'utente.** Revoca del ban da parte del Super Admin.
- **Frase del giorno.** Elenchi delle frasi dell'anno e del percorso, con import da CSV validato. Job alle 07:00 che invia a ciascuno la frase giusta. Interruttore "Frase del giorno" nel profilo.
- **Notifiche dei cicli.** Push agli utenti in attesa all'apertura del ciclo e ai richiedenti se cambia la data di inizio.
- **Cancellazione account.** L'utente cancella il proprio account dall'app. Viene eliminato anche il suo account di accesso in Firebase, come nella rimozione da parte di un admin.
- **Testi.** Tutti i messaggi in italiano. Il Super Admin può modificare i testi per sospesi, bannati e ciclo chiuso.

### Fase 3 — Pannello web (settimane 3–7)
Costruito in Flutter Web, riusando modelli e chiamate dell'app mobile.

1. Accesso con email e password, riservato ad admin e Super Admin.
2. Utenti e gruppi: elenco, revisione, sospensione, riattivazione, ban, revoca del ban, rimozione.
3. Sequenza dei post del Canale Principale.
4. Round di conferma per gruppo.
5. Programmazione del cerchio.
6. Utenti in attesa e richiedenti del prossimo percorso.
7. Frasi dell'anno e del percorso, con import da CSV.
8. Solo Super Admin: cicli con date e durata del percorso, ruoli, testi dei messaggi.

### Fase 4 — App mobile (settimane 1–7)
- Accesso e registrazione con email e password, email verificata e informativa privacy.
- Schermata "In attesa": frase del giorno, numero dei richiedenti, richiesta di partecipazione e suo annullamento.
- Canale Principale del proprio gruppo, in sola lettura, con la frase del giorno del percorso.
- Ingresso al cerchio dal post di annuncio, con il numero di partecipanti.
- Conferma di appartenenza.
- Schermate per utenti sospesi e bannati.
- Profilo con nome, cognome e motivazione modificabili, e interruttore "Frase del giorno".
- Cancellazione dell'account.
- Rimozione delle schermate admin, che nella prima release stanno solo nel pannello web.

### Fase 5 — Prova con i tester (settimane 5–8)
- Su Android almeno 12 tester entrano nel test chiuso di Google Play **entro il 20 novembre** e restano iscritti per 14 giorni consecutivi. Poi si chiede a Google l'accesso alla produzione, che richiede una revisione. La prima versione può essere incompleta: gli aggiornamenti arrivano ai tester durante il test.
- Su iOS almeno 3 tester ricevono l'app tramite TestFlight.
- Gli admin provano il pannello web su un gruppo di prova.
- Si correggono i problemi trovati.

### Fase 6 — Pubblicazione (settimane 8–10)
- Invio in revisione agli store **entro venerdì 11 dicembre**.
- Per la revisione Apple serve un **account di prova** con email e password, da indicare nella richiesta di revisione.
- Schede degli store: descrizione, schermate, link all'informativa privacy, dichiarazione dei dati raccolti.
- Messa in produzione di backend e pannello web.
- Pubblicazione il 26 dicembre, che è sabato e festivo. Gli store permettono di programmare la pubblicazione in anticipo.
- Apertura del primo ciclo.

## Rischi principali

| Rischio | Effetto | Contromisura |
|---|---|---|
| Account store in ritardo | Non si può inviare l'app in revisione | Scegliere subito il referente e aprire gli account personali |
| Test chiuso Android in ritardo o con meno di 12 tester | Google non concede la pubblicazione | Trovare i tester ora e avviare il test entro il 20 novembre, anche con una versione incompleta |
| Rifiuto in revisione | Una o due settimane perse | Inviare entro l'11 dicembre e preparare l'account di prova |
| Revisioni lente a Natale | Pubblicazione dopo il 26 dicembre | Inviare in anticipo e programmare la pubblicazione per il 26 |
| I gruppi toccano tutto | Ritardi a catena | Farli per primi, nella fase 1 |
| Pannello web costruito da zero | Ritardo sulle funzioni admin | Partire dalle funzioni indispensabili e lasciare in fondo quelle che possono slittare |
| Frasi non pronte o diritti non verificati | Notifica giornaliera vuota al lancio | Raccogliere le frasi da subito; senza frasi il job non invia nulla e il resto dell'app funziona |

## Cosa può slittare
Se i tempi stringono, si rimandano in quest'ordine:

1. Modifica dei testi per sospesi, bannati e ciclo chiuso. Restano testi fissi.
2. Revoca del ban dal pannello. Si fa a mano su richiesta.

La cancellazione dell'account **non può slittare**, perché gli store la richiedono.

## Prossimi passi
1. Il gruppo crea la mail di progetto, sceglie il referente, apre gli account store e sceglie l'hosting.
2. Si parte con la fase 1: modello dati dei gruppi ed eliminazione di Socket.IO dall'app.
