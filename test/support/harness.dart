import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sdrop/data/settings.dart';
import 'package:sdrop/models/peer.dart';
import 'package:sdrop/state/drop_controller.dart';

/// Réglages gardés en mémoire : chaque appareil simulé a les siens.
class MemoryStore extends SettingsStore {
  MemoryStore(this.value);

  Settings value;

  @override
  Future<Settings> load() async => value;

  @override
  Future<void> save(Settings s) async => value = s;
}

/// Attend qu'une condition devienne vraie (les échanges réseau sont asynchrones).
Future<void> until(bool Function() condition, {String? reason, Duration timeout = const Duration(seconds: 8)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition jamais remplie${reason == null ? '' : ' : $reason'}');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Un port libre sur cette machine.
Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Un appareil sDrop simulé : son contrôleur, son dossier de réception, ses réglages.
class TestDevice {
  TestDevice(this.controller, this.directory, this.store);

  final DropController controller;
  final Directory directory;
  final MemoryStore store;

  /// Démarre un appareil à l'écoute sur [port], qui s'annonce aux ports [announceTo].
  static Future<TestDevice> start(
    String name, {
    required int port,
    List<int> announceTo = const [],
    DeviceKind kind = DeviceKind.computer,
    Duration decisionTimeout = const Duration(seconds: 5),
  }) async {
    final directory = Directory.systemTemp.createTempSync('sdrop_$name');
    final store = MemoryStore(Settings(deviceId: 'id-$name', deviceName: name));
    final controller = DropController(
      store: store,
      port: port,
      kind: kind,
      discoveryTargets: [for (final target in announceTo) (InternetAddress.loopbackIPv4, target)],
      announceInterval: const Duration(milliseconds: 150),
      peerTimeout: const Duration(seconds: 3),
      decisionTimeout: decisionTimeout,
      downloadDirectory: () => directory,
    );
    await controller.loadSettings();
    await controller.start();
    return TestDevice(controller, directory, store);
  }

  Peer peer(String name) => controller.peers.firstWhere((p) => p.name == name);

  Future<void> stop() async {
    await controller.shutdown();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
