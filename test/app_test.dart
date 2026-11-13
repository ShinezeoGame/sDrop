import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdrop/data/settings.dart';
import 'package:sdrop/models/transfer.dart';
import 'package:sdrop/ui/pages/home_page.dart';
import 'package:sdrop/ui/pages/settings_page.dart';
import 'package:sdrop/ui/widgets/controls.dart';

import 'support/app_harness.dart';
import 'support/harness.dart';

void main() {
  setUpAll(loadFonts);

  const sizes = {
    'fenêtre minimale 360×480': Size(360, 480),
    'fenêtre par défaut 420×760': Size(420, 760),
    'fenêtre agrandie 1100×700': Size(1100, 700),
  };

  /// Fait défiler la page jusqu'en bas : tout le contenu est construit et mesuré.
  Future<void> scrollThrough(WidgetTester tester) async {
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  /// Amène à l'écran un élément situé plus bas dans la page (la liste est construite à la demande).
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 120, scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Rend cliquable un élément, qu'il soit plus bas dans la page ou passé sous l'en-tête.
  Future<void> show(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) await reveal(tester, finder);
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 100));
  }

  for (final MapEntry(key: label, value: size) in sizes.entries) {
    group(label, () {
      for (final dark in [false, true]) {
        final theme = dark ? 'sombre' : 'clair';

        testWidgets('accueil dans tous ses états ($theme)', (tester) async {
          final controller = await pumpApp(
            tester,
            size,
            settings: Settings(
              deviceId: 'pc',
              deviceName: 'PC du bureau de Marie-Christine au premier étage',
              theme: dark ? AppThemeMode.dark : AppThemeMode.light,
            ),
          );
          expect(find.text('Aucun appareil pour l\'instant'), findsOneWidget);
          expect(find.textContaining('Visible sous le nom'), findsOneWidget);
          expect(tester.takeException(), isNull);

          controller.debugSetState(peers: [phonePeer, laptopPeer]);
          await tester.pump();
          expect(find.text('Galaxy S25'), findsOneWidget);
          expect(find.text('Portable du salon'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Un texte attend un destinataire : chaque appareil propose « Envoyer ici ».
          controller.stage(text: 'https://exemple.fr');
          await tester.pump();
          expect(find.text('Un texte à envoyer'), findsOneWidget);
          expect(find.text('Fichiers'), findsNothing);
          await tester.tap(find.byTooltip('Annuler l\'envoi'));
          await tester.pump();
          expect(find.text('Un texte à envoyer'), findsNothing);

          controller.debugSetState(
            pending: [
              request(),
              request(text: 'Un très long texte reçu du téléphone. ' * 12),
              request(files: 1),
            ],
            transfers: [
              transfer(TransferState.waiting, incoming: false),
              transfer(
                TransferState.running,
                incoming: false,
                files: ['Vacances.mp4'],
                total: 734003200,
                done: 287309824,
              ),
              transfer(TransferState.running, files: ['a.jpg', 'b.jpg', 'c.jpg'], total: 9000000, done: 4100000),
              transfer(TransferState.done),
              transfer(TransferState.done, text: 'https://exemple.fr/une-adresse-interminable/' * 6),
              transfer(TransferState.refused, incoming: false),
              transfer(TransferState.failed, incoming: false, error: 'La liaison a été coupée pendant l\'envoi.'),
            ],
          );
          await tester.pump();
          expect(find.text('3 fichiers · 12,9 Mo'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await scrollThrough(tester);
          await tearDownApp(tester, controller);
        });
      }

      testWidgets('une demande s\'accepte ou se refuse d\'un clic', (tester) async {
        final controller = await pumpApp(tester, size);
        final first = request();
        controller.debugSetState(pending: [first]);
        await tester.pump();
        await show(tester, find.text('Toujours accepter cet appareil'));
        await tester.tap(find.text('Toujours accepter cet appareil'));
        await tester.pump();
        expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
        await show(tester, find.widgetWithText(AppButton, 'Accepter'));
        await tester.tap(find.widgetWithText(AppButton, 'Accepter'));
        await tester.pump();
        expect(first.answer, (accepted: true, always: true));

        final second = request(files: 1);
        controller.debugSetState(pending: [second]);
        await tester.pump();
        await show(tester, find.widgetWithText(AppButton, 'Refuser'));
        await tester.tap(find.widgetWithText(AppButton, 'Refuser'));
        await tester.pump();
        expect(second.answer, (accepted: false, always: false));
        await tearDownApp(tester, controller);
      });

      testWidgets('saisie d\'un texte à envoyer : la boîte s\'ouvre et se referme', (tester) async {
        final controller = await pumpApp(tester, size);
        controller.debugSetState(peers: [phonePeer]);
        await tester.pump();
        await show(tester, find.text('Texte'));
        await tester.tap(find.text('Texte'));
        await tester.pumpAndSettle();
        expect(find.text('Texte pour Galaxy S25'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(AppButton, 'Annuler'));
        await tester.pumpAndSettle();
        expect(find.text('Texte pour Galaxy S25'), findsNothing);
        expect(controller.transfers, isEmpty);
        await tearDownApp(tester, controller);
      });

      testWidgets('page Réglages : nom, confiance, thème', (tester) async {
        final store = MemoryStore(
          const Settings(
            deviceId: 'pc',
            deviceName: 'PC du bureau',
            trusted: {'tel': TrustedDevice(name: 'Galaxy S25', token: 'jeton')},
          ),
        );
        final controller = await pumpApp(tester, size, settings: store.value);
        await tester.tap(find.byTooltip('Réglages'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(find.byWidgetPredicate((w) => w is SelectableText && w.data == '192.168.1.42'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.enterText(find.byType(TextField), 'PC de Shine');
        await tester.tap(find.widgetWithText(AppButton, 'Renommer'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.settings.deviceName, 'PC de Shine');

        await show(tester, find.byTooltip('Ne plus faire confiance à Galaxy S25'));
        await tester.tap(find.byTooltip('Ne plus faire confiance à Galaxy S25'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.settings.trusted, isEmpty);
        expect(find.text('Appareils de confiance'), findsNothing);

        await show(tester, find.text('Sombre'));
        await tester.tap(find.text('Sombre'));
        await tester.pumpAndSettle();
        expect(controller.settings.theme, AppThemeMode.dark);
        expect(Theme.of(tester.element(find.byType(SettingsPage))).brightness, Brightness.dark);
        await scrollThrough(tester);

        await tester.tap(find.byTooltip('Retour'));
        await tester.pumpAndSettle();
        expect(find.text('Visible sous le nom « PC de Shine »'), findsOneWidget);
        await tearDownApp(tester, controller);
      });
    });
  }

  test('résumé d\'une liste de fichiers', () {
    expect(describeFiles([]), '');
    expect(describeFiles(['a.jpg']), 'a.jpg');
    expect(describeFiles(['a.jpg', 'b.jpg']), 'a.jpg et 1 autre');
    expect(describeFiles(['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg']), 'a.jpg et 3 autres');
  });
}
