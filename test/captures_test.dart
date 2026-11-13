// Captures d'écran de la documentation (`docs/captures`). Elles ne sont produites que sur
// demande, pour ne pas réécrire des images à chaque exécution des tests :
//
//     SDROP_CAPTURES=1 flutter test test/captures_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdrop/data/settings.dart';
import 'package:sdrop/models/transfer.dart';

import 'support/app_harness.dart';

const _window = Size(420, 760);

Future<void> capture(WidgetTester tester, String name) async {
  // Le logo de l'en-tête se charge en différé : on l'attend avant de capturer.
  final element = tester.element(find.byKey(captureKey));
  await tester.runAsync(() => precacheImage(const AssetImage('assets/branding/logo.png'), element));
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/captures/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  final enabled = Platform.environment.containsKey('SDROP_CAPTURES');
  setUpAll(loadFonts);

  testWidgets('accueil : appareils et transferts', skip: !enabled, (tester) async {
    final controller = await pumpApp(tester, _window);
    controller.debugSetState(
      peers: [phonePeer, laptopPeer],
      transfers: [
        transfer(TransferState.running, incoming: false, files: ['Vacances.mp4'], total: 734003200, done: 287309824),
        transfer(TransferState.done, files: ['IMG_1.jpg', 'IMG_2.jpg', 'IMG_3.jpg'], total: 12900000),
      ],
    );
    await tester.pump(const Duration(milliseconds: 300));
    await capture(tester, 'accueil');
    await tearDownApp(tester, controller);
  });

  testWidgets('accueil sombre : demande reçue', skip: !enabled, (tester) async {
    final controller = await pumpApp(
      tester,
      _window,
      settings: const Settings(deviceId: 'pc', deviceName: 'PC du bureau', theme: AppThemeMode.dark),
    );
    controller.debugSetState(
      peers: [phonePeer],
      pending: [request()],
      transfers: [transfer(TransferState.done, text: 'https://exemple.fr/recette-de-la-tarte-aux-pommes')],
    );
    await tester.pump(const Duration(milliseconds: 300));
    await capture(tester, 'demande');
    await tearDownApp(tester, controller);
  });

  testWidgets('accueil : aucun appareil', skip: !enabled, (tester) async {
    final controller = await pumpApp(tester, _window);
    await capture(tester, 'accueil-vide');
    await tearDownApp(tester, controller);
  });

  testWidgets('page Réglages', skip: !enabled, (tester) async {
    final controller = await pumpApp(
      tester,
      _window,
      settings: const Settings(
        deviceId: 'pc',
        deviceName: 'PC du bureau',
        trusted: {'tel': TrustedDevice(name: 'Galaxy S25', token: 'jeton')},
      ),
    );
    await tester.tap(find.byTooltip('Réglages'));
    await tester.pumpAndSettle();
    await capture(tester, 'reglages');
    await tearDownApp(tester, controller);
  });
}
