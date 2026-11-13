import 'dart:io';

/// Nature d'un appareil : elle ne sert qu'à choisir son icône.
enum DeviceKind {
  phone('telephone'),
  computer('ordinateur');

  const DeviceKind(this.code);

  /// Valeur échangée sur le réseau.
  final String code;

  static DeviceKind parse(Object? code) => code == 'telephone' ? phone : computer;
}

/// Ce qu'un appareil annonce de lui-même.
class DeviceInfo {
  const DeviceInfo({required this.id, required this.name, required this.kind, required this.port});

  /// Identifiant tiré au hasard à la première ouverture de l'application.
  final String id;

  /// Nom choisi par l'utilisateur (« Galaxy S25 », « PC du bureau »).
  final String name;
  final DeviceKind kind;

  /// Port sur lequel l'appareil reçoit les envois.
  final int port;

  Map<String, dynamic> toJson() => {'sdrop': 1, 'id': id, 'nom': name, 'type': kind.code, 'port': port};

  /// Lit une annonce ; `null` si elle n'est pas valide.
  static DeviceInfo? fromJson(Object? json) {
    if (json is! Map || json['sdrop'] != 1) return null;
    final id = json['id'], name = json['nom'], port = json['port'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    if (name is! String || name.trim().isEmpty) return null;
    if (port is! int || port < 1 || port > 65535) return null;
    final clean = name.replaceAll(RegExp(r'[\x00-\x1f]'), ' ').trim();
    return DeviceInfo(
      id: id,
      name: clean.length > 60 ? clean.substring(0, 60) : clean,
      kind: DeviceKind.parse(json['type']),
      port: port,
    );
  }
}

/// Un autre appareil visible sur le réseau.
class Peer {
  Peer({required this.info, required this.address, required this.lastSeen, this.manual = false});

  DeviceInfo info;
  InternetAddress address;
  DateTime lastSeen;

  /// Ajouté par son adresse : il n'est pas oublié quand il cesse de s'annoncer.
  final bool manual;

  String get id => info.id;
  String get name => info.name;
  DeviceKind get kind => info.kind;
  int get port => info.port;
}
