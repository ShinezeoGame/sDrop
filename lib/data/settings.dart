import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Thème de l'interface : automatique (suit le réglage du système), clair ou sombre.
enum AppThemeMode { auto, light, dark }

/// Un appareil dont les envois sont acceptés sans demander.
class TrustedDevice {
  const TrustedDevice({required this.name, required this.token});

  final String name;

  /// Jeton remis à cet appareil : il doit le présenter à chaque envoi.
  final String token;

  Map<String, dynamic> toJson() => {'nom': name, 'jeton': token};
}

class Settings {
  const Settings({
    this.theme = AppThemeMode.auto,
    this.deviceId = '',
    this.deviceName = '',
    this.autoAccept = true,
    this.downloadPath = '',
    this.trusted = const {},
    this.tokens = const {},
    this.manualPeers = const [],
  });

  final AppThemeMode theme;

  /// Identifiant de cet appareil, tiré au hasard à la première ouverture.
  final String deviceId;

  /// Nom sous lequel les autres appareils voient celui-ci.
  final String deviceName;

  /// Accepter sans demander les envois des appareils de confiance.
  final bool autoAccept;

  /// Dossier de réception choisi ; vide pour `Téléchargements/sDrop`.
  final String downloadPath;

  /// Appareils de confiance, par identifiant.
  final Map<String, TrustedDevice> trusted;

  /// Jetons reçus des appareils qui font confiance à celui-ci, par identifiant.
  final Map<String, String> tokens;

  /// Appareils ajoutés par leur adresse (`192.168.1.20:47873`).
  final List<String> manualPeers;

  Settings copyWith({
    AppThemeMode? theme,
    String? deviceId,
    String? deviceName,
    bool? autoAccept,
    String? downloadPath,
    Map<String, TrustedDevice>? trusted,
    Map<String, String>? tokens,
    List<String>? manualPeers,
  }) => Settings(
    theme: theme ?? this.theme,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    autoAccept: autoAccept ?? this.autoAccept,
    downloadPath: downloadPath ?? this.downloadPath,
    trusted: trusted ?? this.trusted,
    tokens: tokens ?? this.tokens,
    manualPeers: manualPeers ?? this.manualPeers,
  );
}

/// Identifiant ou jeton aléatoire (32 chiffres hexadécimaux).
String randomHex([int bytes = 16]) {
  final random = Random.secure();
  return [for (var i = 0; i < bytes; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

/// Lecture et écriture des réglages sur le disque.
class SettingsStore {
  Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> map(String key) {
      try {
        return jsonDecode(prefs.getString(key) ?? '{}') as Map<String, dynamic>;
      } on Object {
        return const {};
      }
    }

    final trusted = <String, TrustedDevice>{};
    for (final entry in map('trusted').entries) {
      final value = entry.value;
      if (value is Map && value['jeton'] is String) {
        trusted[entry.key] = TrustedDevice(name: value['nom'] as String? ?? '', token: value['jeton'] as String);
      }
    }
    final themeName = prefs.getString('theme');
    return Settings(
      theme: AppThemeMode.values.firstWhere((mode) => mode.name == themeName, orElse: () => AppThemeMode.auto),
      deviceId: prefs.getString('deviceId') ?? '',
      deviceName: prefs.getString('deviceName') ?? '',
      autoAccept: prefs.getBool('autoAccept') ?? true,
      downloadPath: prefs.getString('downloadPath') ?? '',
      trusted: trusted,
      tokens: {
        for (final entry in map('tokens').entries)
          if (entry.value is String) entry.key: entry.value as String,
      },
      manualPeers: prefs.getStringList('manualPeers') ?? const [],
    );
  }

  Future<void> save(Settings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', s.theme.name);
    await prefs.setString('deviceId', s.deviceId);
    await prefs.setString('deviceName', s.deviceName);
    await prefs.setBool('autoAccept', s.autoAccept);
    await prefs.setString('downloadPath', s.downloadPath);
    await prefs.setString('trusted', jsonEncode({for (final e in s.trusted.entries) e.key: e.value.toJson()}));
    await prefs.setString('tokens', jsonEncode(s.tokens));
    await prefs.setStringList('manualPeers', s.manualPeers);
  }
}
