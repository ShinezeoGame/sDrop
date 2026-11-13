import 'package:flutter/material.dart';

import 'app.dart';
import 'state/drop_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = DropController();
  // Les réglages sont lus avant le premier affichage : le thème choisi s'applique d'emblée.
  await controller.loadSettings();
  runApp(SDropApp(controller: controller));
  // L'appareil se met à l'écoute du réseau une fois l'interface affichée.
  await controller.start();
}
