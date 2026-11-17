# Design dell'app — stile "Lanterna"

> Direzione visiva scelta il 2026-11-17 per l'app mobile dei partecipanti.
> Mockup di riferimento: canvas "La via della trasformazione — proposte di design" su claude.ai, riga C · Lanterna.
> Il tema Flutter corrispondente è in `mobile/lib/core/theme/lanterna_theme.dart`.

## Idea

Un'app scura e raccolta, pensata anche per la pratica serale. Fondo blu notte, testo color avorio, un solo accento ambra, come la luce di una lanterna. Molto spazio vuoto, poche cornici, nessuna ombra marcata. La frase del giorno è sempre l'elemento più importante della schermata.

Il pannello web di amministrazione **non** cambia stile per ora: resta Material chiaro.

## Colori

| Token | Valore | Uso |
|---|---|---|
| `background` | `#14182B` | Fondo di tutte le schermate |
| `surface` | `#1E2338` | Schede, barra di navigazione, riquadri |
| `line` | `#2C3250` | Linee sottili, binario dell'anello, linea del tempo |
| `outline` | `#3A4163` | Bordo dei campi di testo e dei pulsanti secondari |
| `text` | `#ECE9E2` | Testo principale |
| `muted` | `#A7ABBE` | Testo secondario: date, fonti, didascalie |
| `accent` | `#E8B66B` | Ambra: pulsante principale, elemento attivo, nomi nel cerchio, avanzamento |
| `accentHover` | `#F2CC8F` | Ambra più chiaro per link premuti |
| `onAccent` | `#14182B` | Testo e icone sopra l'ambra |

- Sull'ambra il testo è sempre `onAccent`, mai bianco.
- L'ambra si usa con parsimonia: al massimo un elemento ambra "pieno" per schermata (di solito il pulsante principale o l'ingresso al cerchio).
- Contrasti verificati: `text` e `muted` su `background` e su `surface` superano 4.5:1; `onAccent` su `accent` supera 4.5:1.
- Errori: usare `#F2A39A` su fondo scuro (contrasto sufficiente), non il rosso Material di default.

## Caratteri

- **Literata** (serif) per i titoli e per i testi "da leggere con calma": frase del giorno (corsivo), titoli di schermata, messaggi del cerchio.
- **Inter** (sans) per tutto il resto: interfaccia, post del Canale Principale, pulsanti, didascalie.
- Entrambi da Google Fonts, con licenza OFL. Meglio includerli come asset dell'app (`mobile/assets/fonts/`) invece di scaricarli a runtime: l'app funziona offline e non chiama Google.

| Stile | Carattere | Dimensione / interlinea | Uso |
|---|---|---|---|
| Frase del giorno (gruppo) | Literata corsivo 400 | 25 / 1.38 | Home del gruppo |
| Frase del giorno (attesa) | Literata corsivo 400 | 27 / 1.36 | Schermata "In attesa" |
| Titolo schermata | Literata 400 | 20–22 | "Il cerchio", "Giorno 47 di 365" |
| Titolo riquadro | Literata 400 | 19 | "Prossimo percorso" |
| Messaggio del cerchio | Literata 400 | 17 / 1.5 | Testo dei messaggi |
| Corpo | Inter 400 | 15 / 1.55 | Post del Canale Principale |
| Etichetta pulsante | Inter 600 | 16 | Pulsanti |
| Etichetta di sezione | Inter 600 maiuscolo, spaziatura 0.1em | 13 | "CANALE PRINCIPALE" |
| Didascalia | Inter 400 | 13 | Date, fonte della frase, stato del cerchio |

## Forme e misure

- Margini laterali delle schermate: 24 px.
- Raggi: riquadri 18–22 px; pulsanti e campi di testo a pillola (raggio pari a metà altezza).
- Pulsante principale: altezza 52, pieno ambra, testo `onAccent`.
- Pulsante secondario: altezza 52, trasparente, bordo 1 px `outline`, testo `text`.
- Campo di testo: altezza 52, fondo `surface`, bordo 1 px `outline`, a pillola.
- Aree toccabili mai sotto 44×44.
- Nessuna ombra. La profondità si dà con `surface` su `background`.
- Icone a tratto sottile (1.6–1.8), arrotondate. Material Symbols "Outlined" con peso leggero vanno bene.

## Elementi ricorrenti

- **Anello del giorno.** Cerchio di 56 px: binario `line` spesso 4, arco ambra proporzionale a giorno/durata, numero del giorno al centro (Inter 600, 15). Accanto: "La via della trasformazione" (didascalia) e "Giorno N di D" (Literata 20).
- **Lanterna.** Piccola icona a tratto ambra con un punto pieno al centro, sopra la frase del giorno. È il simbolo dell'app.
- **Ingresso al cerchio.** Quando il cerchio è aperto, nella home compare un riquadro ambra pieno, alto almeno 64: icona del cerchio, "Il cerchio è aperto", sotto "Entra · fino alle HH:MM", freccia a destra. Corrisponde al post di annuncio previsto dalle specifiche (sezione 9): toccarlo vale come consenso ed entra nel cerchio.
- **Linea del tempo del Canale Principale.** I post stanno su una linea verticale `line` a sinistra. Il post più recente ha un pallino ambra pieno, gli altri un pallino vuoto con bordo `muted`. Sopra il testo: "Oggi, 8:00 · giorno 47". Nessun autore (le specifiche dicono che i partecipanti non lo vedono). I link sono ambra.

## Schermate

### Home del gruppo (`main_channel_screen.dart`)
Dall'alto:
1. Anello del giorno con nome del percorso e "Giorno N di D".
2. Frase del giorno, centrata: lanterna, frase in Literata corsivo, sotto "Thich Nhat Hanh · fonte" in `muted`. Se oggi non c'è frase, la sezione non compare.
3. Ingresso al cerchio, solo mentre il cerchio è aperto.
4. Etichetta "CANALE PRINCIPALE" e linea del tempo dei post, con scorrimento infinito come oggi.

Al posto della `AppBar` attuale c'è l'intestazione con l'anello.

### Cerchio (`sharing_channel_screen.dart`)
1. Freccia indietro (esce dal cerchio) e titolo "Il cerchio" in Literata.
2. Riquadro di stato su `surface`: a sinistra un piccolo cerchio di pallini (ambra per chi c'è), a destra "N persone sono nel cerchio" e sotto "Si chiude alle HH:MM · i messaggi poi si cancellano".
3. Messaggi senza bolle: nome e cognome in ambra (13, Inter), testo in Literata 17. I propri messaggi hanno "Tu" in `muted` e un filetto ambra a sinistra.
4. In basso campo "Scrivi al cerchio…" e pulsante tondo ambra con freccia.

### In attesa (`waiting_screen.dart`)
1. In alto a sinistra il nome del percorso, a destra l'icona del profilo.
2. Al centro, con molto spazio: lanterna, data di oggi ("Martedì 17 novembre"), frase dell'anno in Literata corsivo 27, fonte.
3. In basso un riquadro `surface` "Prossimo percorso" con la data di inizio in ambra, "N persone hanno chiesto di partecipare. Richieste aperte fino al GG mese." e il pulsante:
   - senza richiesta: "Chiedi di partecipare", principale ambra;
   - con richiesta: frase "La tua richiesta è arrivata. Un admin la leggerà." e pulsante secondario "Annulla la richiesta";
   - a ciclo chiuso: pulsante disattivato e il messaggio impostato dal Super Admin.

### Barra di navigazione
Fondo `surface`, senza indicatore a pillola: la voce attiva è ambra (icona e testo), le altre `muted`. Voci per chi partecipa: Home, Cerchio, Profilo (più Admin per gli admin, come oggi). Rinominare l'etichetta "Condivisione" in "Cerchio".

### Altre schermate
Accesso, registrazione, verifica email, profilo e admin non hanno ancora un mockup: si applica il tema (colori, caratteri, pulsanti, campi) senza cambiare la struttura. L'interruttore "Frase del giorno" nel profilo usa l'ambra quando è attivo.

## Cosa non fare
- Niente sfumature di colore sullo sfondo, niente ombre, niente emoji.
- Non inventare frasi di Thich Nhat Hanh nei dati di prova: usare testi chiaramente segnaposto.
- Non cambiare il pannello web (`lib/panel/`).
