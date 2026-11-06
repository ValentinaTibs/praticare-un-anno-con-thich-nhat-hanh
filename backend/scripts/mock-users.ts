// Fictional users for the local database, covering the cases the panel and the app must
// handle: every status, both kinds of group, requesters, long names and motivations.
export type MockUser = {
  email: string;
  name: string;
  surname: string;
  motivation: string;
  role?: 'admin' | 'user';
  status?: 'suspended' | 'banned';
  reviewed?: boolean;
  group?: 'active' | 'archived';
  requested?: boolean;
};

export const mockUsers: MockUser[] = [
  { email: 'alessandro.ricci.t@prova.local', name: 'Alessandro', surname: 'Ricci', motivation: 'Vorrei partecipare alle attività del gruppo.', status: 'suspended', reviewed: true, group: 'active' },
  { email: 'alice.mancini.t@prova.local', name: 'Alice', surname: 'Mancini', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'andrea.fontana.t@prova.local', name: 'Andrea', surname: 'Fontana', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'anna@prova.local', name: 'Anna', surname: 'Rossi', motivation: 'Coltivare la presenza mentale', reviewed: true, group: 'active' },
  { email: 'asia.desantis.t@prova.local', name: 'Asia', surname: 'De Santis', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, requested: true },
  { email: 'aurora.lombardi.t@prova.local', name: 'Aurora', surname: 'Lombardi', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'beatrice.giordano.t@prova.local', name: 'Beatrice', surname: 'Giordano', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'camilla.gentile.t@prova.local', name: 'Camilla', surname: 'Gentile', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, requested: true },
  { email: 'chiara.damico.t@prova.local', name: 'Chiara', surname: "D'Amico", motivation: "Ho scoperto il gruppo grazie a un'amica che ne fa parte da un anno e mi ha raccontato quanto le abbia cambiato le giornate.\nLavoro come infermiera turnista in un reparto di medicina interna e spesso mi sento isolata: i miei orari non coincidono mai con quelli degli altri e faccio fatica a mantenere le amicizie.\n\nVorrei far parte di una comunità in cui condividere piccoli obiettivi quotidiani, leggere i pensieri degli altri e, quando posso, dare una mano. Non cerco consigli medici né soluzioni miracolose: mi basta sapere che dall'altra parte c'è qualcuno che capisce cosa vuol dire tornare a casa alle sette di mattina dopo una notte difficile.\n\nMi impegno a rispettare le regole, a confermare la mia presenza quando richiesto e a usare il canale di condivisione con rispetto. Grazie per l'attenzione e per il lavoro che fate. Un'ultima cosa: se serve qualcuno per aiutare con l'organizzazione degli incontri, sono disponibile nei weekend liberi (circa due al mese).", reviewed: true, group: 'active' },
  { email: 'cristian.dangelo.t@prova.local', name: 'Cristian', surname: "D'Angelo", motivation: 'Vorrei partecipare alle attività del gruppo.', requested: true },
  { email: 'daniele.grasso.t@prova.local', name: 'Daniele', surname: 'Grasso', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'archived' },
  { email: 'davide.gallo.t@prova.local', name: 'Davide', surname: 'Gallo', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'edoardo.caruso.t@prova.local', name: 'Edoardo', surname: 'Caruso', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'elena.romano.t@prova.local', name: 'Elena', surname: 'Romano', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'emanuele.coppola.t@prova.local', name: 'Emanuele', surname: 'Coppola', motivation: 'Vorrei partecipare alle attività del gruppo.', requested: true },
  { email: 'fabio.ferrari.t@prova.local', name: 'Fabio', surname: 'Ferrari', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'archived' },
  { email: 'federico.deluca.t@prova.local', name: 'Federico', surname: 'De Luca', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'francesca.colombo.t@prova.local', name: 'Francesca', surname: 'Colombo', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'gabriele.moretti.t@prova.local', name: 'Gabriele', surname: 'Moretti', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'giada.vitale.t@prova.local', name: 'Giada', surname: 'Vitale', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, requested: true },
  { email: 'gianluca.dellorto.t@prova.local', name: 'Gianluca', surname: "Dell'Orto", motivation: 'Vorrei partecipare alle attività del gruppo.', status: 'banned', reviewed: true, group: 'active' },
  { email: 'ginevra.santoro.t@prova.local', name: 'Ginevra', surname: 'Santoro', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'giorgia.bruno.t@prova.local', name: 'Giorgia', surname: 'Bruno', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'giosue.corsi.t@prova.local', name: 'Giosuè', surname: 'Còrsi', motivation: 'Ok', group: 'active' },
  { email: 'giulia@prova.local', name: 'Giulia', surname: 'Bianchi', motivation: 'Accompagnare il gruppo', role: 'admin', reviewed: true, group: 'active' },
  { email: 'ilaria.leone.t@prova.local', name: 'Ilaria', surname: 'Leone', motivation: 'x', requested: true },
  { email: 'laura.fabbri.t@prova.local', name: 'Laura', surname: 'Fabbri', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'archived' },
  { email: 'leonardo.martinelli.t@prova.local', name: 'Leonardo', surname: 'Martinelli', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, requested: true },
  { email: 'lorenzo.greco.t@prova.local', name: 'Lorenzo', surname: 'Greco', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'lucia.ferri.t@prova.local', name: 'Lucia', surname: 'Ferri', motivation: 'Admin sospesa di prova.', role: 'admin', reviewed: true, group: 'active' },
  { email: 'marco.lombardo.t@prova.local', name: 'Marco', surname: 'Lombardo', motivation: 'Vorrei partecipare alle attività del gruppo.', requested: true },
  { email: 'marco@prova.local', name: 'Marco', surname: 'Verdi', motivation: 'Imparare a respirare con calma', reviewed: true, group: 'active' },
  { email: 'mariaaddolorata.logiudicesantamaria.lunghissima.t@prova.local', name: 'Maria Addolorata Benedetta', surname: 'Lo Giudice-Santamaria', motivation: 'Mi piacerebbe confrontarmi con persone che hanno vissuto esperienze simili alla mia, dopo il trasferimento a Torino per lavoro.', reviewed: true, group: 'active' },
  { email: 'martina.marino.t@prova.local', name: 'Martina', surname: 'Marino', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'massimo.bianco.t@prova.local', name: 'Massimo', surname: 'Bianco', motivation: 'Vorrei partecipare alle attività del gruppo.', status: 'suspended', reviewed: true, group: 'archived' },
  { email: 'matteo.esposito.t@prova.local', name: 'Matteo', surname: 'Esposito', motivation: 'Vorrei partecipare alle attività del gruppo.', status: 'banned', reviewed: true, group: 'active' },
  { email: 'michele.dallacqua.t@prova.local', name: 'Michele', surname: "Dall'Acqua", motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'archived' },
  { email: 'niccolo.pellegrini.t@prova.local', name: 'Niccolò', surname: 'Pellegrini', motivation: 'Per conoscere gente nuova.', requested: true },
  { email: 'nicolo.bianchi.t@prova.local', name: 'Nicolò', surname: 'Bianchi', motivation: 'Curiosità.', status: 'suspended', reviewed: true, group: 'active' },
  { email: 'noemi.barbieri.t@prova.local', name: 'Noemi', surname: 'Barbieri', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'paolo.ferraris.t@prova.local', name: 'Paolo', surname: 'Ferraris', motivation: 'Admin di prova.', role: 'admin', reviewed: true, group: 'active' },
  { email: 'pietro.mariani.t@prova.local', name: 'Pietro', surname: 'Mariani', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'rebecca.marchetti.t@prova.local', name: 'Rebecca', surname: 'Marchetti', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, requested: true },
  { email: 'riccardo.costa.t@prova.local', name: 'Riccardo', surname: 'Costa', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'roberta.conte.t@prova.local', name: 'Roberta', surname: 'Conte', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'archived' },
  { email: 'sara.conti.t@prova.local', name: 'Sara', surname: 'Conti', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'silvia.marini.t@prova.local', name: 'Silvia', surname: 'Marini', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'archived' },
  { email: 'simone.longo.t@prova.local', name: 'Simone', surname: 'Longo', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, requested: true },
  { email: 'sofia.russo.t@prova.local', name: 'Sofia', surname: 'Russo', motivation: 'Vorrei partecipare alle attività del gruppo.', status: 'suspended', reviewed: true, group: 'active' },
  { email: 'teresa.messina.t@prova.local', name: 'Teresa', surname: 'Messina', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'archived' },
  { email: 'tommaso.rizzo.t@prova.local', name: 'Tommaso', surname: 'Rizzo', motivation: 'Vorrei partecipare alle attività del gruppo.', status: 'banned', reviewed: true, group: 'active' },
  { email: 'valentina.valentini.t@prova.local', name: 'Valentina', surname: 'Valentini', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'archived' },
  { email: 'valerio.villa.t@prova.local', name: 'Valerio', surname: 'Villa', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, requested: true },
  { email: 'vittoria.rinaldi.t@prova.local', name: 'Vittoria', surname: 'Rinaldi', motivation: 'Vorrei partecipare alle attività del gruppo.', reviewed: true, group: 'active' },
  { email: 'zoe.santelia.t@prova.local', name: 'Zoè', surname: "Sant'Elia", motivation: "Ho scoperto il gruppo grazie a un'amica che ne fa parte da un anno e mi ha raccontato quanto le abbia cambiato le giornate.\nLavoro come infermiera turnista in un reparto di medicina interna e spesso mi sento isolata: i miei orari non coincidono mai con quelli degli altri e faccio fatica a mantenere le amicizie.\n\nVorrei far parte di una comunità in cui condividere piccoli obiettivi quotidiani, leggere i pensieri degli altri e, quando posso, dare una mano. Non cerco consigli medici né soluzioni miracolose: mi basta sapere che dall'altra parte c'è qualcuno che capisce cosa vuol dire tornare a casa alle sette di mattina dopo una notte difficile.\n\nMi impegno a rispettare le regole, a confermare la mia presenza quando richiesto e a usare il canale di condivisione con rispetto. Grazie per l'attenzione e per il lavoro che fate. Un'ultima cosa: se serve qualcuno per aiutare con l'organizzazione degli incontri, sono disponibile nei weekend liberi (circa due al mese)." },
];
