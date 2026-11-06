import 'dart:async';

import 'package:community_app/core/api/api_client.dart';
import 'package:community_app/core/locale.dart';
import 'package:community_app/panel/auth/panel_auth_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes.dart';
import 'pump_panel.dart';

final groups = [
  {'id': 'g2', 'startedAt': '2027-01-12T08:00:00.000Z', 'endedAt': null, 'memberCount': 14},
  {'id': 'g1', 'startedAt': '2026-03-02T08:00:00.000Z', 'endedAt': '2026-09-01T08:00:00.000Z', 'memberCount': 1},
];

/// Answers GET /api/users with the users of the requested group, or all of them.
FakeResponder usersOf(List<Map<String, dynamic>> users) => (_, query) {
      final groupId = query?['groupId'];
      return usersPageJson([for (final u in users) if (groupId == null || u['groupId'] == groupId) u]);
    };

FakeApiClient backendOf(ProviderContainer container) => container.read(panelApiClientProvider) as FakeApiClient;

Future<void> openUsersTab(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(Tab, 'Utenti'));
  await tester.pumpAndSettle();
}

/// Opens the card of the user called [name] from the users tab.
Future<void> openCard(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('Apri la scheda di $name'));
  await tester.pumpAndSettle();
}

Finder inCard(String text) => find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

/// Gives the focus to the button with this tooltip.
void focusOn(WidgetTester tester, Finder tooltip) =>
    Focus.of(tester.element(find.descendant(of: tooltip, matching: find.byType(Icon)))).requestFocus();

/// The tooltip of the button with the focus.
String? focusedTooltip() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Tooltip>()?.message;

void main() {
  setUpAll(initItalianLocale);

  group('scheda Gruppi', () {
    testWidgets('separa gruppi attivi e archiviati e conta i membri', (tester) async {
      await pumpPanel(tester, role: 'admin', responses: {'/api/groups': groups});

      expect(find.text('Gruppi attivi'), findsOneWidget);
      expect(find.text('Gruppo iniziato il 12 gennaio 2027'), findsOneWidget);
      expect(find.text('14 membri'), findsOneWidget);
      expect(find.text('Gruppi archiviati'), findsOneWidget);
      expect(find.text('Gruppo iniziato il 2 marzo 2026'), findsOneWidget);
      expect(find.text('1 membro · archiviato il 1 settembre 2026'), findsOneWidget);
    });

    testWidgets('senza gruppi lo dice per entrambi gli elenchi', (tester) async {
      await pumpPanel(tester, role: 'admin');

      expect(find.text('Nessun gruppo attivo'), findsOneWidget);
      expect(find.text('Nessun gruppo archiviato'), findsOneWidget);
    });

    testWidgets('aprire un gruppo mostra i suoi membri nella scheda Utenti', (tester) async {
      final container = await pumpPanel(tester, role: 'admin', responses: {
        '/api/groups': groups,
        '/api/users': usersOf([
          listedUserJson('u1', name: 'Anna', groupId: 'g2'),
          listedUserJson('u2', name: 'Marco', groupId: 'g1'),
        ]),
      });

      await tester.tap(find.text('Gruppo iniziato il 12 gennaio 2027'));
      await tester.pumpAndSettle();

      expect(backendOf(container).calls.last, 'GET /api/users?page=1&limit=50&groupId=g2');
      expect(find.textContaining('Membri del gruppo iniziato il 12 gennaio 2027'), findsOneWidget);
      expect(find.text('Anna Bianchi'), findsOneWidget);
      expect(find.text('Marco Bianchi'), findsNothing);
    });
  });

  group('scheda Utenti', () {
    testWidgets('mostra gruppo, stato e revisione di ogni utente', (tester) async {
      await pumpPanel(tester, role: 'admin', responses: {
        '/api/groups': groups,
        '/api/users': usersPageJson([
          listedUserJson('u1', name: 'Anna', groupId: 'g2', reviewed: false),
          listedUserJson('u2', name: 'Marco', status: 'suspended'),
          listedUserJson('u3', name: 'Luca', groupId: 'g1'),
        ]),
      });
      await openUsersTab(tester);

      Finder inTable(String text) => find.descendant(of: find.byType(DataTable), matching: find.text(text));
      expect(find.text('3 utenti'), findsOneWidget);
      expect(inTable('12 gennaio 2027'), findsOneWidget);
      expect(inTable('In attesa'), findsOneWidget);
      expect(inTable('2 marzo 2026 (archiviato)'), findsOneWidget);
      expect(find.text('Sospeso'), findsOneWidget);
      expect(find.text('Da revisionare'), findsOneWidget);
      expect(find.text('Revisionato'), findsNWidgets(2));
    });

    testWidgets('il filtro «Solo da revisionare» rifà la richiesta', (tester) async {
      final container = await pumpPanel(tester, role: 'admin');
      await openUsersTab(tester);

      await tester.tap(find.text('Solo da revisionare'));
      await tester.pumpAndSettle();

      expect(backendOf(container).calls.last, 'GET /api/users?page=1&limit=50&reviewed=false');
    });

    testWidgets('la ricerca parte mentre si scrive', (tester) async {
      final container = await pumpPanel(tester, role: 'admin');
      await openUsersTab(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Cerca per nome, cognome o email'), 'anna');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(backendOf(container).calls.last, 'GET /api/users?page=1&limit=50&q=anna');
    });

    testWidgets('filtri e pulsanti della tabella sono leggibili dai lettori di schermo', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPanel(tester, role: 'admin', responses: {
        '/api/users': usersPageJson([listedUserJson('u1', name: 'Anna')]),
      });
      await openUsersTab(tester);

      expect(
        tester.getSemantics(find.byTooltip('Apri la scheda di Anna Bianchi')),
        isSemantics(tooltip: 'Apri la scheda di Anna Bianchi', isButton: true, hasTapAction: true),
      );
      expect(find.bySemanticsLabel(RegExp('Cerca per nome, cognome o email')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Solo da revisionare')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a 1280 px nomi ed email lunghi non spingono fuori le altre colonne', (tester) async {
      await pumpPanel(tester, role: 'admin', responses: {
        '/api/groups': groups,
        '/api/users': usersPageJson([
          listedUserJson(
            'maria.addolorata.benedetta.lunghissima.t',
            name: 'Maria Addolorata Benedetta',
            surname: 'Lo Giudice-Santamaria',
            groupId: 'g1',
            reviewed: false,
          ),
        ]),
      });
      tester.view.physicalSize = const Size(1280, 800);
      await openUsersTab(tester);

      for (final text in ['Revisione', 'Da revisionare', 'Stato', 'Attivo', 'Ruolo', 'Utente']) {
        final inTable = find.descendant(of: find.byType(DataTable), matching: find.text(text));
        expect(tester.getTopRight(inTable).dx, lessThan(1280), reason: text);
      }
      expect(tester.takeException(), isNull);
      final sideways = tester.widget<Scrollbar>(find.byType(Scrollbar).first).controller!;
      expect(sideways.position.maxScrollExtent, 0, reason: 'la tabella sta nello schermo');
    });

    testWidgets('in una finestra stretta la barra orizzontale è visibile sopra il fondo dell\'area', (tester) async {
      await pumpPanel(tester, role: 'admin', responses: {
        '/api/users': usersPageJson([for (var i = 0; i < 50; i++) listedUserJson('u$i')]),
      });
      tester.view.physicalSize = const Size(1000, 700);
      await openUsersTab(tester);

      final bar = tester.widget<Scrollbar>(find.byType(Scrollbar).first);
      expect(bar.thumbVisibility, isTrue);
      expect(bar.controller!.position.maxScrollExtent, greaterThan(0));
      expect(tester.getBottomLeft(find.byType(Scrollbar).first).dy, lessThanOrEqualTo(700));
    });

    testWidgets('Tab passa da una scheda all\'altra senza fermarsi sulle celle', (tester) async {
      await pumpPanel(tester, role: 'admin', responses: {
        '/api/users': usersPageJson([listedUserJson('u1', name: 'Anna'), listedUserJson('u2', name: 'Marco')]),
      });
      await openUsersTab(tester);

      focusOn(tester, find.byTooltip('Apri la scheda di Anna Bianchi'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(focusedTooltip(), 'Apri la scheda di Marco Bianchi');
    });

    testWidgets('«Da revisionare» non è una casella di controllo', (tester) async {
      await pumpPanel(tester, role: 'admin', responses: {
        '/api/users': usersPageJson([listedUserJson('u1', reviewed: false)]),
      });
      await openUsersTab(tester);

      expect(find.text('Da revisionare'), findsOneWidget);
      expect(find.byType(Chip), findsNothing);
    });

    testWidgets('«Cancella la ricerca» riporta il focus nel campo', (tester) async {
      await pumpPanel(tester, role: 'admin');
      await openUsersTab(tester);
      final field = find.widgetWithText(TextField, 'Cerca per nome, cognome o email');

      await tester.enterText(field, 'anna');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancella la ricerca'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(find.byTooltip('Cancella la ricerca'), findsNothing);
    });

    testWidgets('il campo di ricerca si ferma al massimo accettato dal backend', (tester) async {
      final container = await pumpPanel(tester, role: 'admin');
      await openUsersTab(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Cerca per nome, cognome o email'), 'a' * 150);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(backendOf(container).calls.last, 'GET /api/users?page=1&limit=50&q=${'a' * 100}');
    });

    testWidgets('il menu dei gruppi usa etichette brevi, senza tagliare «archiviato»', (tester) async {
      await pumpPanel(tester, role: 'admin', responses: {'/api/groups': groups});
      await openUsersTab(tester);

      await tester.tap(find.text('Tutti i gruppi'));
      await tester.pumpAndSettle();

      expect(find.text('12 gennaio 2027'), findsWidgets);
      expect(find.text('2 marzo 2026 (archiviato)'), findsWidgets);
    });

    group('paginazione da tastiera', () {
      /// Three pages; the answer to the page in [slowPage] waits for [slow].
      Map<String, Object> threePages({int? slowPage, Completer<void>? slow}) => {
            '/api/users': (String _, Map<String, dynamic>? q) async {
              final page = int.parse(q!['page'] as String);
              if (page == slowPage) await slow!.future;
              return usersPageJson([listedUserJson('u$page')], total: 120, page: page);
            },
          };

      Future<void> pressEnter(WidgetTester tester) async {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
      }

      testWidgets('il pulsante tiene il focus mentre la pagina si carica', (tester) async {
        final slow = Completer<void>();
        await pumpPanel(tester, role: 'admin', responses: threePages(slowPage: 2, slow: slow));
        await openUsersTab(tester);
        focusOn(tester, find.byTooltip('Pagina successiva'));
        await tester.pump();

        await pressEnter(tester);
        expect(focusedTooltip(), 'Pagina successiva', reason: 'durante il caricamento');

        slow.complete();
        await tester.pumpAndSettle();
        expect(find.text('Pagina 2 di 3'), findsOneWidget);
        expect(focusedTooltip(), 'Pagina successiva');
      });

      testWidgets('ai limiti il focus passa all\'altro pulsante', (tester) async {
        await pumpPanel(tester, role: 'admin', responses: threePages());
        await openUsersTab(tester);
        focusOn(tester, find.byTooltip('Pagina successiva'));
        await tester.pump();

        await pressEnter(tester);
        await tester.pumpAndSettle();
        await pressEnter(tester);
        await tester.pumpAndSettle();
        expect(find.text('Pagina 3 di 3'), findsOneWidget);
        expect(focusedTooltip(), 'Pagina precedente');

        await pressEnter(tester);
        await tester.pumpAndSettle();
        await pressEnter(tester);
        await tester.pumpAndSettle();
        expect(find.text('Pagina 1 di 3'), findsOneWidget);
        expect(focusedTooltip(), 'Pagina successiva');
      });

      testWidgets('il cambio di pagina è annunciato', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpPanel(tester, role: 'admin', responses: threePages());
        await openUsersTab(tester);

        expect(tester.getSemantics(find.text('Pagina 1 di 3')), isSemantics(isLiveRegion: true));
        semantics.dispose();
      });
    });

    testWidgets('senza risultati lo dice', (tester) async {
      await pumpPanel(tester, role: 'admin');
      await openUsersTab(tester);

      expect(find.text('Nessun utente trovato'), findsOneWidget);
    });

    testWidgets('un errore mostra il messaggio e «Riprova» ricarica', (tester) async {
      final container = await pumpPanel(tester, role: 'admin', responses: {
        '/api/users': ApiException(statusCode: 500, message: 'Errore interno del server'),
      });
      await openUsersTab(tester);
      expect(find.text('Errore interno del server'), findsOneWidget);

      backendOf(container).responses['/api/users'] = usersPageJson([listedUserJson('u1', name: 'Anna')]);
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();

      expect(find.text('Anna Bianchi'), findsOneWidget);
    });
  });

  group('scheda dell\'utente', () {
    Future<ProviderContainer> pumpWithUser(WidgetTester tester, Map<String, dynamic> user, {String role = 'admin'}) async {
      final container = await pumpPanel(tester, role: role, responses: {
        '/api/users': usersPageJson([user]),
        '/api/users/${user['id']}': user,
        '/api/admin/${user['id']}/suspend': {'id': user['id'], 'status': 'suspended'},
        '/api/admin/${user['id']}/review': {'id': user['id'], 'reviewedByAdmin': true},
        '/api/admin/${user['id']}': '',
      });
      await openUsersTab(tester);
      await openCard(tester, '${user['name']} ${user['surname']}');
      return container;
    }

    testWidgets('mostra la motivazione completa', (tester) async {
      await pumpWithUser(tester, listedUserJson('u1', motivation: 'Cerco un gruppo con cui praticare ogni giorno.'));

      expect(inCard('Motivazione'), findsOneWidget);
      expect(inCard('Cerco un gruppo con cui praticare ogni giorno.'), findsOneWidget);
      expect(inCard('In attesa'), findsOneWidget);
    });

    testWidgets('un utente attivo si può sospendere, bannare o rimuovere', (tester) async {
      await pumpWithUser(tester, listedUserJson('u1', reviewed: false));

      for (final label in ['Segna come revisionato', 'Sospendi', 'Banna', 'Rimuovi']) {
        expect(inCard(label), findsOneWidget, reason: label);
      }
      expect(inCard('Riattiva'), findsNothing);
      expect(inCard('Revoca il ban'), findsNothing);
    });

    testWidgets('un utente sospeso si può riattivare', (tester) async {
      await pumpWithUser(tester, listedUserJson('u1', status: 'suspended'));

      expect(inCard('Riattiva'), findsOneWidget);
      expect(inCard('Sospendi'), findsNothing);
      expect(inCard('Banna'), findsOneWidget);
      expect(inCard('Rimuovi'), findsOneWidget);
    });

    testWidgets('un admin non può revocare il ban', (tester) async {
      await pumpWithUser(tester, listedUserJson('u1', status: 'banned'));

      for (final label in ['Revoca il ban', 'Riattiva', 'Sospendi', 'Banna', 'Rimuovi']) {
        expect(inCard(label), findsNothing, reason: label);
      }
    });

    testWidgets('il Super Admin può revocare il ban', (tester) async {
      await pumpWithUser(tester, listedUserJson('u1', status: 'banned'), role: 'super_admin');

      expect(inCard('Revoca il ban'), findsOneWidget);
      expect(inCard('Rimuovi'), findsNothing);
    });

    testWidgets('un admin non ha azioni sul proprio account', (tester) async {
      await pumpWithUser(tester, listedUserJson('u-admin', name: 'Giulia', surname: 'Rossi', role: 'admin'));

      expect(inCard('Non puoi intervenire sul tuo account.'), findsOneWidget);
      expect(inCard('Sospendi'), findsNothing);
    });

    testWidgets('un admin non ha azioni su un altro admin', (tester) async {
      await pumpWithUser(tester, listedUserJson('a2', role: 'admin'));

      expect(inCard('Solo il Super Admin può sospendere, bannare o rimuovere un admin.'), findsOneWidget);
      expect(inCard('Sospendi'), findsNothing);
    });

    testWidgets('un admin riattiva un altro admin sospeso', (tester) async {
      await pumpWithUser(tester, listedUserJson('a2', role: 'admin', status: 'suspended'));

      expect(inCard('Riattiva'), findsOneWidget);
      expect(inCard('Banna'), findsNothing);
    });

    testWidgets('nessuno ha azioni sul Super Admin', (tester) async {
      await pumpWithUser(tester, listedUserJson('s2', role: 'super_admin'));

      expect(inCard('Nessuno può sospendere, bannare o rimuovere il Super Admin.'), findsOneWidget);
      expect(inCard('Banna'), findsNothing);
      expect(inCard('Rimuovi'), findsNothing);
    });

    testWidgets('«Chiudi» chiude la scheda senza chiamare il backend', (tester) async {
      final container = await pumpWithUser(tester, listedUserJson('u1'));
      final before = backendOf(container).calls.length;

      await tester.tap(inCard('Chiudi'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(backendOf(container).calls.length, before);
    });

    testWidgets('sospendere chiede conferma, chiama il backend e aggiorna la scheda', (tester) async {
      final container = await pumpWithUser(tester, listedUserJson('u1'));

      await tester.tap(inCard('Sospendi'));
      await tester.pumpAndSettle();
      expect(find.text('Sospendere Anna Bianchi?'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(FilledButton), matching: find.text('Sospendi')));
      await tester.pumpAndSettle();

      expect(backendOf(container).calls, containsAllInOrder(['PATCH /api/admin/u1/suspend', 'GET /api/users?page=1&limit=50']));
      expect(find.text('Utente sospeso'), findsOneWidget);
      expect(inCard('Sospeso'), findsOneWidget, reason: 'la scheda resta aperta con il nuovo stato');
      expect(inCard('Riattiva'), findsOneWidget);
      expect(inCard('Sospendi'), findsNothing);
    });

    testWidgets('«Annulla» sulla rimozione non chiama il backend', (tester) async {
      final container = await pumpWithUser(tester, listedUserJson('u1'));

      await tester.tap(inCard('Rimuovi'));
      await tester.pumpAndSettle();
      expect(find.text('Rimuovere Anna Bianchi?'), findsOneWidget);
      expect(find.textContaining('non si può annullare'), findsOneWidget);

      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(backendOf(container).calls.where((c) => c.startsWith('DELETE')), isEmpty);
      expect(inCard('Anna Bianchi'), findsOneWidget, reason: 'la scheda resta aperta');
    });

    testWidgets('rimuovere dopo la conferma elimina l\'utente', (tester) async {
      final container = await pumpWithUser(tester, listedUserJson('u1'));

      await tester.tap(inCard('Rimuovi'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FilledButton), matching: find.text('Rimuovi')).last);
      await tester.pumpAndSettle();

      expect(backendOf(container).calls, contains('DELETE /api/admin/u1'));
      expect(find.text('Utente rimosso'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('un rifiuto del backend mostra il suo messaggio nella scheda', (tester) async {
      final container = await pumpWithUser(tester, listedUserJson('u1'));
      backendOf(container).responses['/api/admin/u1/suspend'] =
          ApiException(statusCode: 409, message: 'Solo un utente attivo può essere sospeso');

      await tester.tap(inCard('Sospendi'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FilledButton), matching: find.text('Sospendi')));
      await tester.pumpAndSettle();

      expect(inCard('Solo un utente attivo può essere sospeso'), findsOneWidget);
    });

    testWidgets('dopo un rifiuto la scheda mostra lo stato attuale dell\'utente, anche se è uscito dall\'elenco', (tester) async {
      final container = await pumpWithUser(tester, listedUserJson('u1'));
      // Another admin suspended the user in the meantime, and the list only shows active users.
      backendOf(container).responses
        ..['/api/admin/u1/suspend'] = ApiException(statusCode: 409, message: 'Solo un utente attivo può essere sospeso')
        ..['/api/users/u1'] = listedUserJson('u1', status: 'suspended')
        ..['/api/users'] = usersPageJson([]);

      await tester.tap(inCard('Sospendi'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FilledButton), matching: find.text('Sospendi')));
      await tester.pumpAndSettle();

      expect(inCard('Sospeso'), findsOneWidget);
      expect(inCard('Riattiva'), findsOneWidget);
      expect(inCard('Sospendi'), findsNothing);
    });

    testWidgets('se l\'utente non esiste più la scheda non offre azioni', (tester) async {
      final container = await pumpWithUser(tester, listedUserJson('u1'));
      backendOf(container).responses
        ..['/api/admin/u1/suspend'] = ApiException(statusCode: 404, message: 'Elemento non trovato')
        ..['/api/users'] = usersPageJson([]);

      await tester.tap(inCard('Sospendi'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FilledButton), matching: find.text('Sospendi')));
      await tester.pumpAndSettle();

      expect(inCard('Questo utente non esiste più: forse un altro admin l\'ha rimosso.'), findsOneWidget);
      for (final label in ['Sospendi', 'Banna', 'Rimuovi']) {
        expect(inCard(label), findsNothing, reason: label);
      }
      expect(inCard('Chiudi'), findsOneWidget);
    });

    testWidgets('se dopo un rifiuto l\'utente risulta rimosso la scheda non offre azioni', (tester) async {
      final container = await pumpWithUser(tester, listedUserJson('u1'));
      backendOf(container).responses
        ..['/api/admin/u1/suspend'] = ApiException(statusCode: 409, message: 'Solo un utente attivo può essere sospeso')
        ..['/api/users/u1'] = ApiException(statusCode: 404, message: 'Elemento non trovato');

      await tester.tap(inCard('Sospendi'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FilledButton), matching: find.text('Sospendi')));
      await tester.pumpAndSettle();

      expect(inCard('Questo utente non esiste più: forse un altro admin l\'ha rimosso.'), findsOneWidget);
      expect(inCard('Sospendi'), findsNothing);
    });

    testWidgets('se la rilettura fallisce la scheda resta com\'era e mostra il rifiuto', (tester) async {
      final container = await pumpWithUser(tester, listedUserJson('u1'));
      backendOf(container).responses
        ..['/api/admin/u1/suspend'] = ApiException(statusCode: 409, message: 'Solo un utente attivo può essere sospeso')
        ..['/api/users/u1'] = ApiException(statusCode: 0, message: 'Impossibile contattare il server.');

      await tester.tap(inCard('Sospendi'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FilledButton), matching: find.text('Sospendi')));
      await tester.pumpAndSettle();

      expect(inCard('Solo un utente attivo può essere sospeso'), findsOneWidget);
      expect(inCard('Attivo'), findsOneWidget);
    });

    testWidgets('i valori sono selezionabili e leggibili dai lettori di schermo', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpWithUser(tester, listedUserJson('u1', motivation: 'Cerco un gruppo.'));

      expect(find.byType(SelectableText), findsNothing);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(SelectionArea)), findsOneWidget);
      expect(find.semantics.byLabel(RegExp('u1@prova.local')), findsOne);
      expect(find.semantics.byLabel(RegExp('Cerco un gruppo.')), findsOne);
      semantics.dispose();
    });

    testWidgets('Tab dalla scheda va ai pulsanti, senza fermarsi sull\'area di selezione', (tester) async {
      await pumpWithUser(tester, listedUserJson('u1'));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<OutlinedButton>(), isNotNull);
    });

    testWidgets('scheda e conferme si presentano ai lettori di schermo con nome e domanda', (tester) async {
      await pumpWithUser(tester, listedUserJson('u1'));
      expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).semanticLabel, 'Anna Bianchi');

      await tester.tap(inCard('Sospendi'));
      await tester.pumpAndSettle();
      expect(tester.widget<AlertDialog>(find.byType(AlertDialog).last).semanticLabel, 'Sospendere Anna Bianchi?');
    });

    testWidgets('l\'esito di un\'azione è annunciato nella scheda', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpWithUser(tester, listedUserJson('u1'));

      await tester.tap(inCard('Sospendi'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FilledButton), matching: find.text('Sospendi')));
      await tester.pumpAndSettle();

      expect(tester.getSemantics(inCard('Utente sospeso')), isSemantics(isLiveRegion: true));
      expect(find.byType(SnackBar), findsNothing, reason: 'starebbe sotto la scheda');
      semantics.dispose();
    });

    testWidgets('la revisione chiede conferma perché non si può annullare', (tester) async {
      final container = await pumpWithUser(tester, listedUserJson('u1', reviewed: false));

      await tester.tap(inCard('Segna come revisionato'));
      await tester.pumpAndSettle();
      expect(find.text('Segnare Anna Bianchi come revisionato?'), findsOneWidget);
      expect(find.textContaining('non si può annullare'), findsOneWidget);
      expect(backendOf(container).calls.where((c) => c.startsWith('PATCH')), isEmpty);

      await tester.tap(find.descendant(of: find.byType(FilledButton), matching: find.text('Segna come revisionato')));
      await tester.pumpAndSettle();

      expect(backendOf(container).calls, contains('PATCH /api/admin/u1/review'));
      expect(inCard('Revisionato'), findsOneWidget);
      expect(inCard('Segna come revisionato'), findsNothing);
    });

    testWidgets('le conferme dicono la differenza tra rimozione e ban', (tester) async {
      await pumpWithUser(tester, listedUserJson('u1'));

      await tester.tap(inCard('Rimuovi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('registrarsi di nuovo con la stessa email'), findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      await tester.tap(inCard('Banna'));
      await tester.pumpAndSettle();
      expect(find.textContaining('né registrarsi di nuovo con questa email'), findsOneWidget);
    });

    testWidgets('l\'ultima conferma si vede solo per chi partecipa ai round', (tester) async {
      await pumpWithUser(tester, listedUserJson('u1', groupId: 'g2'));
      expect(inCard('Ultima conferma il'), findsOneWidget);
      await tester.tap(inCard('Chiudi'));
      await tester.pumpAndSettle();
    });

    testWidgets('niente ultima conferma per chi è in attesa', (tester) async {
      await pumpWithUser(tester, listedUserJson('u1'));
      expect(inCard('Ultima conferma il'), findsNothing);
    });

    testWidgets('niente ultima conferma per un admin in un gruppo', (tester) async {
      await pumpWithUser(tester, listedUserJson('a2', role: 'admin', groupId: 'g2'));
      expect(inCard('Ultima conferma il'), findsNothing);
    });

    testWidgets('il ruolo del Super Admin è scritto come nelle specifiche', (tester) async {
      await pumpWithUser(tester, listedUserJson('s2', role: 'super_admin'));
      expect(inCard('Super Admin'), findsOneWidget);
    });

    testWidgets('un errore arrivato dopo la chiusura della scheda compare in un avviso', (tester) async {
      final container = await pumpWithUser(tester, listedUserJson('u1'));
      final answer = Completer<Object?>();
      Object? pending(String method, Map<String, dynamic>? query) => answer.future;
      backendOf(container).responses['/api/admin/u1/suspend'] = pending;

      await tester.tap(inCard('Sospendi'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FilledButton), matching: find.text('Sospendi')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      answer.completeError(ApiException(statusCode: 409, message: 'Solo un utente attivo può essere sospeso'));
      await tester.pumpAndSettle();

      expect(find.text('Solo un utente attivo può essere sospeso'), findsOneWidget);
    });
  });
}
