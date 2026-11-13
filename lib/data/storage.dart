import 'dart:io';

import 'package:path/path.dart' as p;

final _forbidden = RegExp(r'[<>:"/\\|?*\x00-\x1f]');
final _reserved = RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$', caseSensitive: false);

/// Rend sûr un nom de fichier reçu du réseau : il ne peut ni sortir du dossier de
/// réception, ni porter un nom interdit sous Windows.
String sanitizeFileName(String received) {
  // Seul le dernier élément du chemin compte, quel que soit le séparateur employé.
  var name = received.split(RegExp(r'[/\\]')).last;
  name = name.replaceAll(_forbidden, '_').trim();
  // Windows refuse les noms finissant par un point ou une espace ; « . » et « .. » sont des dossiers.
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) return 'fichier';
  if (_reserved.hasMatch(name)) name = '_$name';
  if (name.length > 180) {
    final extension = p.extension(name);
    final keep = 180 - (extension.length > 20 ? 0 : extension.length);
    name = name.substring(0, keep) + (extension.length > 20 ? '' : extension);
  }
  return name;
}

/// Fichier libre portant ce nom dans [directory] : « photo.jpg », sinon « photo (2).jpg »…
File uniqueFile(Directory directory, String name) {
  var candidate = File(p.join(directory.path, name));
  final base = p.basenameWithoutExtension(name);
  final extension = p.extension(name);
  for (var n = 2; candidate.existsSync(); n++) {
    candidate = File(p.join(directory.path, '$base ($n)$extension'));
  }
  return candidate;
}

/// Dossier de réception par défaut : `Téléchargements/sDrop`.
Directory defaultDownloadDirectory({Map<String, String>? environment, bool? android}) {
  final env = environment ?? Platform.environment;
  if (android ?? Platform.isAndroid) return Directory('/storage/emulated/0/Download/sDrop');
  final home = env['USERPROFILE'] ?? env['HOME'] ?? Directory.current.path;
  return Directory(p.join(home, 'Downloads', 'sDrop'));
}

/// Taille lisible : « 12,4 Mo ».
String formatSize(int bytes) {
  const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0 || value >= 100 ? value.round().toString() : value.toStringAsFixed(1).replaceAll('.', ',');
  return '$text ${units[unit]}';
}
