import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/net/client.dart';
import '../data/net/discovery.dart';
import '../data/net/protocol.dart';
import '../data/net/server.dart';
import '../data/settings.dart';
import '../data/storage.dart';
import '../data/system_bridge.dart';
import '../models/peer.dart';
import '../models/transfer.dart';

/// Une demande d'envoi reçue, en attente de la décision de l'utilisateur.
class PendingRequest {
  PendingRequest(this.session, this.offer, this.address);

  final String session;
  final Offer offer;
  final InternetAddress address;
  final Completer<bool> _decision = Completer();
  bool _always = false;

  String get peerName => offer.from.name;
}

/// Ce qui attend le choix d'un destinataire : fichiers déposés dans la fenêtre, ou
/// contenu reçu du menu « Partager » d'Android.
class Outbox {
  const Outbox({this.items = const [], this.text});

  final List<OutgoingItem> items;
  final String? text;

  int get totalBytes => items.fold(0, (sum, item) => sum + item.size);
}

/// Message affiché en haut de l'écran après une action.
class Notice {
  const Notice(this.message, {this.error = false});

  final String message;
  final bool error;
}

/// État de l'application : appareils visibles, demandes reçues, transferts.
class DropController extends ChangeNotifier implements DropReceiver {
  DropController({
    SettingsStore? store,
    DropClient? client,
    this.bridge = const SystemBridge(),
    this.port = sdropPort,
    this.discoveryTargets,
    this.kind,
    this.announceInterval = const Duration(seconds: 4),
    this.peerTimeout = const Duration(seconds: 14),
    this.decisionTimeout = const Duration(seconds: 120),
    Directory Function()? downloadDirectory,
  }) : _store = store ?? SettingsStore(),
       client = client ?? DropClient(),
       _defaultDirectory = downloadDirectory ?? defaultDownloadDirectory;

  final SettingsStore _store;
  final DropClient client;
  final SystemBridge bridge;

  /// Port souhaité pour les annonces et la réception.
  final int port;

  /// Destinataires imposés des annonces (tests).
  final List<(InternetAddress, int)>? discoveryTargets;

  /// Nature de cet appareil ; déduite du système si elle n'est pas donnée.
  final DeviceKind? kind;
  final Duration announceInterval;

  /// Un appareil qui ne s'annonce plus est oublié après ce délai.
  final Duration peerTimeout;

  /// Une demande restée sans réponse est refusée après ce délai.
  final Duration decisionTimeout;
  final Directory Function() _defaultDirectory;

  Settings _settings = const Settings();
  Settings get settings => _settings;

  late final DropServer _server = DropServer(this);
  Discovery? _discovery;
  StreamSubscription<Announcement>? _announcements;
  Timer? _housekeeping;
  int _serverPort = 0;

  /// Port sur lequel cet appareil reçoit réellement.
  int get serverPort => _serverPort;

  bool _ready = false;

  /// Vrai une fois l'appareil à l'écoute.
  bool get ready => _ready;

  String? _startError;

  /// Raison pour laquelle l'appareil n'a pas pu se mettre à l'écoute.
  String? get startError => _startError;

  final Map<String, Peer> _peers = {};
  final Map<String, DateTime> _lastHello = {};

  /// Appareils visibles, par ordre alphabétique.
  List<Peer> get peers =>
      _peers.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  final List<PendingRequest> _pending = [];
  List<PendingRequest> get pending => List.unmodifiable(_pending);

  final List<Transfer> _transfers = [];

  /// Transferts, du plus récent au plus ancien.
  List<Transfer> get transfers => List.unmodifiable(_transfers);

  final Map<String, (Peer, String)> _outgoingSessions = {};

  Outbox? _outbox;
  Outbox? get outbox => _outbox;

  Notice? _notice;
  Notice? get notice => _notice;

  List<String> _addresses = const [];

  /// Adresses de cet appareil sur le réseau local.
  List<String> get addresses => _addresses;

  bool _disposed = false;
  Timer? _notifyTimer;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  int _localId = 0;

  // ── Démarrage et arrêt ──

  /// Lit les réglages ; au premier lancement, donne à l'appareil un identifiant et un nom.
  Future<void> loadSettings() async {
    var settings = await _store.load();
    if (settings.deviceId.isEmpty || settings.deviceName.isEmpty) {
      var name = settings.deviceName;
      if (name.isEmpty) name = (await bridge.deviceName())?.trim() ?? '';
      if (name.isEmpty) name = _hostName();
      settings = settings.copyWith(deviceId: settings.deviceId.isEmpty ? randomHex() : null, deviceName: name);
      await _store.save(settings);
    }
    _settings = settings;
    _notify();
  }

  static String _hostName() {
    try {
      final name = Platform.localHostname;
      if (name.isNotEmpty && name != 'localhost') return name;
    } on Object {
      // Nom indisponible.
    }
    return Platform.isAndroid ? 'Téléphone' : 'Ordinateur';
  }

  /// Met l'appareil à l'écoute et commence à s'annoncer.
  Future<void> start() async {
    try {
      _serverPort = await _server.start(port: port);
      await bridge.multicastLock(true);
      final discovery = _discovery = Discovery(
        self: () => self,
        port: port,
        targets: discoveryTargets,
        interval: announceInterval,
      );
      _announcements = discovery.announcements.listen(_onAnnouncement);
      await discovery.start();
      _ready = true;
    } on Object catch (error) {
      _startError = 'sDrop ne peut pas se mettre à l\'écoute du réseau : $error';
    }
    await _checkDirectory();
    _housekeeping = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    unawaited(_refreshAddresses());
    unawaited(_restoreManualPeers());
    bridge.onShare(_onShare);
    _onShare(await bridge.initialShare());
    _notify();
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    _housekeeping?.cancel();
    _notifyTimer?.cancel();
    for (final request in [..._pending]) {
      refuse(request);
    }
    await _announcements?.cancel();
    await _discovery?.stop();
    await _server.stop();
    await bridge.multicastLock(false);
    client.close();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    _lastNotify = DateTime.now();
    notifyListeners();
  }

  /// Rafraîchit l'affichage sans le faire à chaque paquet reçu pendant un transfert.
  void _notifySoon() {
    if (_disposed || _notifyTimer != null) return;
    final wait = const Duration(milliseconds: 100) - DateTime.now().difference(_lastNotify);
    if (wait <= Duration.zero) return _notify();
    _notifyTimer = Timer(wait, () {
      _notifyTimer = null;
      _notify();
    });
  }

  Future<void> _refreshAddresses() async {
    final found = await localAddresses();
    if (listEquals(found, _addresses)) return;
    _addresses = found;
    _notify();
  }

  // ── Appareils ──

  @override
  DeviceInfo get self => DeviceInfo(
    id: _settings.deviceId,
    name: _settings.deviceName,
    kind: kind ?? (Platform.isAndroid || Platform.isIOS ? DeviceKind.phone : DeviceKind.computer),
    port: _serverPort == 0 ? port : _serverPort,
  );

  void _onAnnouncement(Announcement announcement) {
    _seen(announcement.info, announcement.address);
    // On se signale en retour, directement : l'autre appareil nous voit ainsi même si
    // nos annonces ne lui parviennent pas (multidiffusion filtrée d'un côté).
    final last = _lastHello[announcement.info.id];
    if (last == null || DateTime.now().difference(last) > const Duration(seconds: 8)) {
      _lastHello[announcement.info.id] = DateTime.now();
      unawaited(_sayHello(announcement.address, announcement.info.port));
    }
  }

  Future<void> _sayHello(InternetAddress address, int port) async {
    try {
      final info = await client.hello(address, port, self);
      if (info != null) _seen(info, address);
    } on DropException {
      // Appareil momentanément injoignable.
    }
  }

  @override
  void hello(DeviceInfo info, InternetAddress address) => _seen(info, address);

  void _seen(DeviceInfo info, InternetAddress address, {bool manual = false}) {
    if (_disposed || info.id == _settings.deviceId) return;
    final known = _peers[info.id];
    if (known == null) {
      _peers[info.id] = Peer(info: info, address: address, lastSeen: DateTime.now(), manual: manual);
      _notify();
      return;
    }
    final changed = known.name != info.name || known.port != info.port || known.address != address;
    known
      ..info = info
      ..address = address
      ..lastSeen = DateTime.now();
    if (changed) _notify();
  }

  void _tick() {
    final limit = DateTime.now().subtract(peerTimeout);
    final before = _peers.length;
    _peers.removeWhere((_, peer) => !peer.manual && peer.lastSeen.isBefore(limit));
    _lastHello.removeWhere((id, _) => !_peers.containsKey(id));
    if (_peers.length != before) _notify();
    unawaited(_refreshAddresses());
  }

  /// Ajoute un appareil par son adresse (`192.168.1.20` ou `192.168.1.20:47873`), quand
  /// le réseau ne laisse pas passer les annonces.
  Future<bool> addPeerByAddress(String input) async {
    final parsed = parseAddress(input);
    if (parsed == null) {
      _setNotice(const Notice('Adresse invalide. Exemple : 192.168.1.20', error: true));
      return false;
    }
    final (address, peerPort) = parsed;
    try {
      final info = await client.info(address, peerPort);
      if (info.id == _settings.deviceId) {
        _setNotice(const Notice('Cette adresse est celle de cet appareil.', error: true));
        return false;
      }
      _peers.remove(info.id);
      _seen(info, address, manual: true);
      final entry = '${address.address}:$peerPort';
      if (!_settings.manualPeers.contains(entry)) {
        await updateSettings(_settings.copyWith(manualPeers: [..._settings.manualPeers, entry]));
      }
      unawaited(_sayHello(address, peerPort));
      _setNotice(Notice('${info.name} ajouté.'));
      return true;
    } on DropException catch (error) {
      _setNotice(Notice(error.message, error: true));
      return false;
    }
  }

  Future<void> _restoreManualPeers() async {
    for (final entry in _settings.manualPeers) {
      final parsed = parseAddress(entry);
      if (parsed == null) continue;
      try {
        final info = await client.info(parsed.$1, parsed.$2);
        _peers.remove(info.id);
        _seen(info, parsed.$1, manual: true);
        unawaited(_sayHello(parsed.$1, parsed.$2));
      } on DropException {
        // Appareil éteint : il réapparaîtra s'il s'annonce.
      }
    }
  }

  /// Oublie un appareil ajouté par son adresse.
  Future<void> forgetPeer(Peer peer) async {
    _peers.remove(peer.id);
    final entry = '${peer.address.address}:${peer.port}';
    await updateSettings(_settings.copyWith(manualPeers: [for (final m in _settings.manualPeers) if (m != entry) m]));
  }

  // ── Réception ──

  @override
  Future<OfferReply> decide(Offer offer, InternetAddress address, String session) async {
    if (_disposed) return const OfferReply.refused();
    _seen(offer.from, address);
    final trusted = _settings.trusted[offer.from.id];
    final known = trusted != null && offer.token.isNotEmpty && offer.token == trusted.token;
    if (known && _settings.autoAccept) return _acceptIncoming(session, offer, always: false);

    final request = PendingRequest(session, offer, address);
    _pending.add(request);
    _notify();
    final accepted = await request._decision.future.timeout(decisionTimeout, onTimeout: () => false);
    _pending.remove(request);
    if (!accepted) {
      _notify();
      return const OfferReply.refused();
    }
    return _acceptIncoming(session, offer, always: request._always);
  }

  Future<OfferReply> _acceptIncoming(String session, Offer offer, {required bool always}) async {
    final transfer = Transfer(
      id: session,
      direction: TransferDirection.incoming,
      peerName: offer.from.name,
      fileNames: [for (final item in offer.items) sanitizeFileName(item.name)],
      totalBytes: offer.totalBytes,
      text: offer.text,
      state: offer.items.isEmpty ? TransferState.done : TransferState.running,
    );
    _addTransfer(transfer);
    var token = '';
    if (always) {
      token = randomHex();
      await updateSettings(
        _settings.copyWith(
          trusted: {..._settings.trusted, offer.from.id: TrustedDevice(name: offer.from.name, token: token)},
        ),
      );
    }
    _notify();
    return OfferReply(accepted: true, token: token);
  }

  /// Accepte une demande ; [always] accepte aussi d'office les prochains envois de cet appareil.
  void accept(PendingRequest request, {bool always = false}) {
    request._always = always;
    if (!request._decision.isCompleted) request._decision.complete(true);
  }

  void refuse(PendingRequest request) {
    if (!request._decision.isCompleted) request._decision.complete(false);
  }

  /// Dossier de repli, si « Téléchargements » s'avère inaccessible sur ce téléphone.
  String? _fallbackPath;

  /// Vérifie, sur Android, qu'on peut bien écrire dans « Téléchargements » ; sinon les
  /// fichiers iront dans le dossier propre à l'application.
  Future<void> _checkDirectory() async {
    if (!Platform.isAndroid) return;
    try {
      final directory = _defaultDirectory();
      await directory.create(recursive: true);
      final probe = File('${directory.path}/.sdrop-essai');
      await probe.writeAsString('ok');
      await probe.delete();
    } on Object {
      _fallbackPath = await bridge.fallbackDirectory();
    }
  }

  /// Dossier de réception, pour l'affichage.
  String get downloadPath =>
      _settings.downloadPath.isNotEmpty ? _settings.downloadPath : (_fallbackPath ?? _defaultDirectory().path);

  @override
  Future<Directory> directory() async => Directory(downloadPath);

  Transfer? _transfer(String id) {
    for (final transfer in _transfers) {
      if (transfer.id == id) return transfer;
    }
    return null;
  }

  @override
  void progress(String session, int bytes) {
    final transfer = _transfer(session);
    if (transfer == null) return;
    transfer.bytesDone = bytes;
    _notifySoon();
  }

  @override
  void fileReceived(String session, File file) {
    _transfer(session)?.files.add(file);
    _notifySoon();
  }

  @override
  void finished(String session, {required bool complete, String? error}) {
    final transfer = _transfer(session);
    if (transfer == null) return;
    transfer
      ..state = complete ? TransferState.done : TransferState.failed
      ..error = complete ? null : error;
    if (complete) transfer.bytesDone = transfer.totalBytes;
    _notify();
  }

  // ── Envoi ──

  void _addTransfer(Transfer transfer) {
    _transfers.insert(0, transfer);
    // On ne garde que les derniers transferts terminés.
    while (_transfers.length > 40) {
      final index = _transfers.lastIndexWhere((t) => !t.active);
      if (index < 0) break;
      _transfers.removeAt(index);
    }
  }

  /// Envoie des fichiers ou un texte à [peer]. Renvoie le transfert, dont l'état évolue.
  Future<Transfer> send(Peer peer, {List<OutgoingItem> items = const [], String? text}) async {
    final transfer = Transfer(
      id: 'envoi-${_localId++}',
      direction: TransferDirection.outgoing,
      peerName: peer.name,
      fileNames: [for (final item in items) item.name],
      totalBytes: items.fold(0, (sum, item) => sum + item.size),
      text: items.isEmpty ? text : null,
    );
    _addTransfer(transfer);
    _notify();
    try {
      final reply = await client.offer(
        peer,
        Offer(
          from: self,
          token: _settings.tokens[peer.id] ?? '',
          items: [for (final item in items) OfferItem(name: item.name, size: item.size)],
          text: items.isEmpty ? text : null,
        ),
        timeout: decisionTimeout + const Duration(seconds: 30),
      );
      if (!reply.accepted) {
        transfer.state = TransferState.refused;
        _notify();
        return transfer;
      }
      if (reply.token.isNotEmpty && _settings.tokens[peer.id] != reply.token) {
        await updateSettings(_settings.copyWith(tokens: {..._settings.tokens, peer.id: reply.token}));
      }
      if (items.isNotEmpty) {
        transfer.state = TransferState.running;
        _outgoingSessions[transfer.id] = (peer, reply.session);
        _notify();
        var before = 0;
        for (final (index, item) in items.indexed) {
          if (transfer.state != TransferState.running) return transfer;
          await client.upload(peer, reply.session, index, item, (sent) {
            transfer.bytesDone = before + sent;
            _notifySoon();
          });
          before += item.size;
        }
      }
      transfer
        ..state = TransferState.done
        ..bytesDone = transfer.totalBytes;
    } on DropException catch (error) {
      // Un envoi annulé par l'utilisateur garde son propre message.
      if (transfer.state != TransferState.failed) {
        transfer
          ..state = TransferState.failed
          ..error = error.message;
      }
    } on Object catch (error) {
      transfer
        ..state = TransferState.failed
        ..error = 'Envoi impossible : $error';
    } finally {
      _outgoingSessions.remove(transfer.id);
    }
    _notify();
    return transfer;
  }

  /// Interrompt un envoi en cours.
  Future<void> cancel(Transfer transfer) async {
    final session = _outgoingSessions.remove(transfer.id);
    if (session == null || !transfer.active) return;
    transfer
      ..state = TransferState.failed
      ..error = 'Envoi annulé.';
    _notify();
    await client.cancel(session.$1, session.$2);
  }

  /// Retire de la liste les transferts terminés.
  void clearFinished() {
    _transfers.removeWhere((transfer) => !transfer.active);
    _notify();
  }

  // ── En attente d'un destinataire ──

  /// Met de côté des fichiers ou un texte : l'utilisateur choisit ensuite l'appareil.
  void stage({List<OutgoingItem> items = const [], String? text}) {
    if (items.isEmpty && (text == null || text.trim().isEmpty)) return;
    _outbox = Outbox(items: items, text: text);
    _notify();
  }

  void clearOutbox() {
    if (_outbox == null) return;
    _outbox = null;
    _notify();
  }

  /// Envoie à [peer] ce qui avait été mis de côté.
  Future<Transfer?> sendOutbox(Peer peer) async {
    final outbox = _outbox;
    if (outbox == null) return null;
    _outbox = null;
    return send(peer, items: outbox.items, text: outbox.text);
  }

  Future<void> _onShare(SharedContent content) async {
    if (content.isEmpty) return;
    final items = <OutgoingItem>[];
    for (final path in content.files) {
      try {
        items.add(await OutgoingItem.fromFile(File(path)));
      } on Object {
        // Fichier illisible : ignoré.
      }
    }
    stage(items: items, text: content.text);
  }

  // ── Réglages et messages ──

  Future<void> updateSettings(Settings settings) async {
    final renamed = settings.deviceName != _settings.deviceName;
    _settings = settings;
    _notify();
    await _store.save(settings);
    if (renamed) unawaited(_discovery?.announce());
  }

  /// Ne fait plus confiance à un appareil : ses prochains envois seront à accepter.
  Future<void> untrust(String deviceId) =>
      updateSettings(_settings.copyWith(trusted: {..._settings.trusted}..remove(deviceId)));

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    _notify();
  }

  void _setNotice(Notice notice) {
    _notice = notice;
    _notify();
  }

  /// État imposé, pour les tests d'affichage et les captures de la documentation.
  @visibleForTesting
  void debugSetState({
    List<Peer>? peers,
    List<PendingRequest>? pending,
    List<Transfer>? transfers,
    Outbox? outbox,
    List<String>? addresses,
    bool? ready,
  }) {
    if (peers != null) {
      _peers
        ..clear()
        ..addEntries(peers.map((peer) => MapEntry(peer.id, peer)));
    }
    if (pending != null) {
      _pending
        ..clear()
        ..addAll(pending);
    }
    if (transfers != null) {
      _transfers
        ..clear()
        ..addAll(transfers);
    }
    if (outbox != null) _outbox = outbox;
    if (addresses != null) _addresses = addresses;
    if (ready != null) _ready = ready;
    notifyListeners();
  }
}

/// Lit une adresse saisie : `192.168.1.20` ou `192.168.1.20:47873`.
(InternetAddress, int)? parseAddress(String input) {
  final text = input.trim();
  var host = text;
  var port = sdropPort;
  final colon = text.lastIndexOf(':');
  if (colon > 0) {
    final parsed = int.tryParse(text.substring(colon + 1));
    if (parsed == null || parsed < 1 || parsed > 65535) return null;
    host = text.substring(0, colon);
    port = parsed;
  }
  final address = InternetAddress.tryParse(host);
  if (address == null || address.type != InternetAddressType.IPv4) return null;
  return (address, port);
}
