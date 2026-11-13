import 'dart:io';

import 'package:flutter/services.dart';

/// Ce qu'une autre application confie à sDrop par le menu « Partager » d'Android.
class SharedContent {
  const SharedContent({this.files = const [], this.text});

  /// Chemins des fichiers (copiés par Android dans le dossier temporaire de l'application).
  final List<String> files;
  final String? text;

  bool get isEmpty => files.isEmpty && (text == null || text!.isEmpty);

  static SharedContent fromMap(Object? map) {
    if (map is! Map) return const SharedContent();
    final files = map['fichiers'];
    final text = map['texte'];
    return SharedContent(
      files: files is List ? [for (final f in files) if (f is String) f] : const [],
      text: text is String ? text : null,
    );
  }
}

/// Fonctions propres à Android, fournies par `MainActivity.kt`. Sans effet ailleurs.
class SystemBridge {
  const SystemBridge();

  static const _channel = MethodChannel('sdrop/systeme');

  bool get _android => Platform.isAndroid;

  /// Nom donné au téléphone par son propriétaire (« Galaxy S25 »).
  Future<String?> deviceName() async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<String>('nomAppareil');
    } on Object {
      return null;
    }
  }

  /// Autorise la réception des annonces en multidiffusion, qu'Android filtre par défaut
  /// pour économiser la batterie.
  Future<void> multicastLock(bool enabled) async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('verrouMultidiffusion', enabled);
    } on Object {
      // La diffusion classique reste disponible.
    }
  }

  /// Contenu partagé qui a ouvert l'application, s'il y en a un.
  Future<SharedContent> initialShare() async {
    if (!_android) return const SharedContent();
    try {
      return SharedContent.fromMap(await _channel.invokeMethod<Object?>('partageInitial'));
    } on Object {
      return const SharedContent();
    }
  }

  /// Écoute les partages reçus pendant que l'application est ouverte.
  void onShare(void Function(SharedContent content) handler) {
    if (!_android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'partage') handler(SharedContent.fromMap(call.arguments));
    });
  }
}
