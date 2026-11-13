import 'dart:io';

import 'package:path/path.dart' as p;

/// Un fichier à envoyer : son nom, sa taille, et de quoi le lire.
class OutgoingItem {
  const OutgoingItem({required this.name, required this.size, required this.open});

  final String name;
  final int size;

  /// Ouvre le contenu en lecture (appelé une fois, au moment de l'envoi).
  final Stream<List<int>> Function() open;

  static Future<OutgoingItem> fromFile(File file) async {
    return OutgoingItem(name: p.basename(file.path), size: await file.length(), open: file.openRead);
  }
}

enum TransferDirection { incoming, outgoing }

enum TransferState {
  /// En attente de la réponse du destinataire.
  waiting,
  running,
  done,
  refused,
  failed,
}

/// Un envoi ou une réception, tel qu'il est affiché dans la liste des transferts.
class Transfer {
  Transfer({
    required this.id,
    required this.direction,
    required this.peerName,
    this.fileNames = const [],
    this.totalBytes = 0,
    this.text,
    this.state = TransferState.waiting,
  });

  final String id;
  final TransferDirection direction;

  /// Nom de l'autre appareil.
  final String peerName;
  final List<String> fileNames;
  final int totalBytes;

  /// Texte échangé, pour un envoi de texte.
  final String? text;

  TransferState state;
  int bytesDone = 0;

  /// Raison de l'échec, à afficher.
  String? error;

  /// Fichiers enregistrés sur cet appareil (réception).
  final List<File> files = [];

  bool get incoming => direction == TransferDirection.incoming;

  bool get isText => text != null && fileNames.isEmpty;

  bool get active => state == TransferState.waiting || state == TransferState.running;

  /// Avancement entre 0 et 1.
  double get progress => totalBytes <= 0 ? (state == TransferState.done ? 1 : 0) : (bytesDone / totalBytes).clamp(0, 1);
}
