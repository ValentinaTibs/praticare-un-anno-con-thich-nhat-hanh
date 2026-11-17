import 'package:community_app/features/auth/auth_notifier.dart';
import 'package:community_app/features/auth/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../panel/fakes.dart';
import 'app_fakes.dart';

const _privacyError = 'Per registrarti devi accettare l\'informativa privacy.';

/// Records the registrations instead of sending them: the real one needs a Firebase user.
class RecordingAuthNotifier extends AuthNotifier {
  final List<String> registered = [];

  RecordingAuthNotifier(Ref ref)
      : super(ref.watch(apiClientProvider), ref.watch(tokenStorageProvider), ref.watch(pushServiceProvider));

  @override
  Future<AuthStep> register({required String name, required String surname, required String motivation}) async {
    registered.add('$name $surname');
    return AuthStep.loggedIn;
  }
}

Future<RecordingAuthNotifier> openRegister(WidgetTester tester) async {
  late RecordingAuthNotifier notifier;
  final container = ProviderContainer(overrides: [
    httpAdapterProvider.overrideWithValue(FakeHttp({})),
    tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
    pushServiceProvider.overrideWithValue(FakePush()),
    authProvider.overrideWith((ref) => notifier = RecordingAuthNotifier(ref)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: RegisterScreen()),
  ));
  await tester.pumpAndSettle();

  await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Anna');
  await tester.enterText(find.widgetWithText(TextFormField, 'Cognome'), 'Rossi');
  await tester.enterText(find.widgetWithText(TextFormField, 'Perché vuoi entrare nella comunità?'), 'Crescere');
  return notifier;
}

Future<void> submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Entra'));
  await tester.tap(find.text('Entra'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra il link all\'informativa privacy', (tester) async {
    await openRegister(tester);

    expect(find.text('Leggi l\'informativa privacy'), findsOneWidget);
  });

  testWidgets('senza accettare l\'informativa la registrazione non parte', (tester) async {
    final notifier = await openRegister(tester);

    await submit(tester);

    expect(find.text(_privacyError), findsOneWidget);
    expect(notifier.registered, isEmpty);
  });

  testWidgets('accettata l\'informativa la registrazione parte', (tester) async {
    final notifier = await openRegister(tester);

    await tester.ensureVisible(find.text('Ho letto e accetto l\'informativa privacy'));
    await tester.tap(find.text('Ho letto e accetto l\'informativa privacy'));
    await submit(tester);

    expect(find.text(_privacyError), findsNothing);
    expect(notifier.registered, ['Anna Rossi']);
  });
}
