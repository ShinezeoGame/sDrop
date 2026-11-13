import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';

import '../models/transfer.dart';

/// Vrai sur un ordinateur : glisser-déposer et ouverture du dossier y sont proposés.
bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Fait choisir des fichiers à l'utilisateur ([media] : photos et vidéos seulement).
/// Liste vide s'il annule.
Future<List<OutgoingItem>> pickItems({bool media = false}) async {
  final picked = await FilePicker.pickFiles(
    dialogTitle: 'Fichiers à envoyer',
    type: media ? FileType.media : FileType.any,
  );
  return [
    for (final file in picked)
      OutgoingItem(name: file.name, size: await file.xFile.length(), open: file.xFile.openRead),
  ];
}

/// Fichiers déposés dans la fenêtre. Les dossiers sont ignorés.
Future<List<OutgoingItem>> droppedItems(List<DropItem> dropped) async {
  final items = <OutgoingItem>[];
  for (final entry in dropped) {
    if (FileSystemEntity.isDirectorySync(entry.path)) continue;
    try {
      items.add(await OutgoingItem.fromFile(File(entry.path)));
    } on Object {
      // Fichier illisible (supprimé entre-temps, accès refusé) : ignoré.
    }
  }
  return items;
}

/// Fait choisir un dossier de réception ; `null` si l'utilisateur annule.
Future<String?> pickDirectory() => FilePicker.getDirectoryPath(dialogTitle: 'Dossier de réception');

/// Ouvre un dossier dans l'explorateur de fichiers de l'ordinateur.
Future<void> openFolder(String path) async {
  final program = Platform.isWindows ? 'explorer.exe' : (Platform.isMacOS ? 'open' : 'xdg-open');
  try {
    await Process.start(program, [path], mode: ProcessStartMode.detached);
  } on Object {
    // Pas d'explorateur disponible : sans gravité.
  }
}
