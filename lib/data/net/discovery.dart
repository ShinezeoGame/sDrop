import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/peer.dart';
import 'protocol.dart';

/// Une annonce reçue d'un autre appareil.
class Announcement {
  const Announcement(this.info, this.address);

  final DeviceInfo info;
  final InternetAddress address;
}

/// Découverte des appareils du réseau local.
///
/// Chaque appareil annonce régulièrement qui il est par un petit message UDP, envoyé à la
/// fois en multidiffusion et en diffusion (selon les box et les téléphones, l'un des deux
/// seulement passe), et écoute les annonces des autres.
class Discovery {
  Discovery({
    required this.self,
    this.port = sdropPort,
    this.targets,
    this.interval = const Duration(seconds: 4),
  });

  /// Ce que l'appareil annonce (relu à chaque envoi : le nom peut changer).
  final DeviceInfo Function() self;

  /// Port d'écoute des annonces.
  final int port;

  /// Destinataires imposés (tests). `null` : multidiffusion et diffusion du réseau local.
  final List<(InternetAddress, int)>? targets;
  final Duration interval;

  final _announcements = StreamController<Announcement>.broadcast();

  /// Annonces des autres appareils (les siennes sont ignorées).
  Stream<Announcement> get announcements => _announcements.stream;

  RawDatagramSocket? _socket;
  Timer? _timer;
  List<(InternetAddress, int)> _resolved = const [];
  DateTime _resolvedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Faux si le port d'écoute était déjà pris (autre copie de l'application) : l'appareil
  /// s'annonce mais n'entend pas les autres, qui se signalent alors directement à lui.
  bool listening = false;

  Future<void> start() async {
    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
      listening = true;
    } on SocketException {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
    _socket = socket;
    socket.broadcastEnabled = true;
    if (targets == null && listening) await _joinMulticast(socket);
    socket.listen(_onEvent, onError: (Object _) {});
    unawaited(announce());
    _timer = Timer.periodic(interval, (_) => announce());
  }

  Future<void> _joinMulticast(RawDatagramSocket socket) async {
    final group = InternetAddress(sdropMulticastGroup);
    try {
      socket.joinMulticast(group);
    } on Object {
      // Certains systèmes exigent de nommer l'interface : on essaie ci-dessous.
    }
    try {
      for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        try {
          socket.joinMulticast(group, interface);
        } on Object {
          // Interface sans multidiffusion : la diffusion prendra le relais.
        }
      }
    } on Object {
      // Liste des interfaces indisponible.
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    for (var datagram = socket.receive(); datagram != null; datagram = socket.receive()) {
      if (datagram.data.length > 2048) continue;
      DeviceInfo? info;
      try {
        info = DeviceInfo.fromJson(jsonDecode(utf8.decode(datagram.data)));
      } on Object {
        continue;
      }
      if (info == null || info.id == self().id) continue;
      _announcements.add(Announcement(info, datagram.address));
    }
  }

  /// Envoie une annonce tout de suite.
  Future<void> announce() async {
    final socket = _socket;
    if (socket == null) return;
    final data = utf8.encode(jsonEncode(self().toJson()));
    for (final (address, targetPort) in await _destinations()) {
      try {
        socket.send(data, address, targetPort);
      } on Object {
        // Réseau momentanément indisponible : la prochaine annonce repassera.
      }
    }
  }

  Future<List<(InternetAddress, int)>> _destinations() async {
    final fixed = targets;
    if (fixed != null) return fixed;
    // Les interfaces changent rarement (Wi-Fi coupé, câble branché) : relues toutes les 20 s.
    if (DateTime.now().difference(_resolvedAt) < const Duration(seconds: 20)) return _resolved;
    final addresses = <String>{sdropMulticastGroup, '255.255.255.255'};
    try {
      for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final address in interface.addresses) {
          // Diffusion dirigée, en supposant le masque courant des réseaux domestiques (/24).
          final parts = address.address.split('.');
          if (parts.length == 4) addresses.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    } on Object {
      // On garde la multidiffusion et la diffusion générale.
    }
    _resolved = [for (final address in addresses) (InternetAddress(address), port)];
    _resolvedAt = DateTime.now();
    return _resolved;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _socket?.close();
    _socket = null;
    await _announcements.close();
  }
}

/// Adresses de cet appareil sur le réseau local, pour les afficher à l'utilisateur.
Future<List<String>> localAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (!address.isLoopback && !address.isLinkLocal) address.address,
    ];
  } on Object {
    return const [];
  }
}
