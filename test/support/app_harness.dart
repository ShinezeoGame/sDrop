import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdrop/app.dart';
import 'package:sdrop/data/net/protocol.dart';
import 'package:sdrop/data/settings.dart';
import 'package:sdrop/models/peer.dart';
import 'package:sdrop/models/transfer.dart';
import 'package:sdrop/state/drop_controller.dart';

import 'harness.dart';

/// Charge les vraies polices pour que les mesures de texte correspondent à l'application.
Future<void> loadFonts() async {
  final outfit = FontLoader('Outfit');
  for (final weight in ['300Light', '400Regular', '500Medium', '600SemiBold']) {
    final bytes = File('assets/fonts/Outfit_$weight.ttf').readAsBytesSync();
    outfit.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await outfit.load();

  // Les icônes Material viennent du SDK Flutter ; sans elles, des carrés les remplacent.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!icons.existsSync()) return;
  final material = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
  await material.load();
}

/// Clé de la zone capturée pour la documentation.
const captureKey = ValueKey('capture');

final phonePeer = Peer(
  info: const DeviceInfo(id: 'tel', name: 'Galaxy S25', kind: DeviceKind.phone, port: sdropPort),
  address: InternetAddress('192.168.1.20'),
  lastSeen: DateTime.now(),
);

final laptopPeer = Peer(
  info: const DeviceInfo(id: 'portable', name: 'Portable du salon', kind: DeviceKind.computer, port: sdropPort),
  address: InternetAddress('192.168.1.37'),
  lastSeen: DateTime.now(),
  manual: true,
);

/// Une demande reçue du téléphone : des fichiers, ou un texte si [text] est donné.
PendingRequest request({String? text, int files = 3}) => PendingRequest(
  'session-${text ?? files}',
  Offer(
    from: phonePeer.info,
    items: text != null
        ? const []
        : [for (var i = 0; i < files; i++) OfferItem(name: 'IMG_2026111${i}_184502.jpg', size: 4200000 + i * 310000)],
    text: text,
  ),
  phonePeer.address,
);

Transfer transfer(
  TransferState state, {
  bool incoming = true,
  String? text,
  List<String> files = const ['Facture novembre.pdf'],
  int total = 2400000,
  int done = 0,
  String? error,
}) =>
    Transfer(
        id: '$state-$incoming-${text ?? files.length}',
        direction: incoming ? TransferDirection.incoming : TransferDirection.outgoing,
        peerName: 'Galaxy S25',
        fileNames: text == null ? files : const [],
        totalBytes: text == null ? total : 0,
        text: text,
        state: state,
      )
      ..bytesDone = done
      ..error = error;

/// Affiche l'application dans une fenêtre de la taille donnée, sans réseau : l'état est
/// imposé avec `debugSetState`.
Future<DropController> pumpApp(WidgetTester tester, Size size, {Settings? settings}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = DropController(
    store: MemoryStore(settings ?? const Settings(deviceId: 'pc', deviceName: 'PC du bureau')),
    downloadDirectory: () => Directory(r'C:\Users\shine\Downloads\sDrop'),
  );
  await controller.loadSettings();
  controller.debugSetState(ready: true, addresses: const ['192.168.1.42']);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: SDropApp(controller: controller),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return controller;
}

Future<void> tearDownApp(WidgetTester tester, DropController controller) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}
