import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../models/peer.dart';
import '../storage.dart';
import 'protocol.dart';

/// Ce que le serveur de réception demande à l'application.
abstract class DropReceiver {
  /// Identité de cet appareil.
  DeviceInfo get self;

  /// Un autre appareil vient de se signaler directement.
  void hello(DeviceInfo info, InternetAddress address);

  /// Demande d'envoi reçue : la réponse attend la décision de l'utilisateur.
  Future<OfferReply> decide(Offer offer, InternetAddress address, String session);

  /// Dossier où ranger les fichiers reçus.
  Future<Directory> directory();

  /// Octets reçus depuis le début de l'envoi.
  void progress(String session, int bytes);

  void fileReceived(String session, File file);

  /// Fin d'un envoi : [complete] si tous les fichiers sont arrivés.
  void finished(String session, {required bool complete, String? error});
}

class _Session {
  _Session(this.id, this.address, this.offer);

  final String id;
  final InternetAddress address;
  final Offer offer;
  final Set<int> received = {};
  final Set<int> inProgress = {};
  int bytes = 0;
  DateTime lastActivity = DateTime.now();
}

/// Serveur HTTP qui reçoit les envois des autres appareils.
///
///  * `GET  /info`     : qui est cet appareil ;
///  * `POST /bonjour`  : un appareil se signale ;
///  * `POST /demande`  : demande d'envoi (fichiers annoncés, ou texte) ;
///  * `POST /envoi`    : contenu d'un fichier d'un envoi accepté ;
///  * `POST /annuler`  : l'expéditeur abandonne.
class DropServer {
  DropServer(this.receiver, {this.idleTimeout = const Duration(seconds: 45)});

  final DropReceiver receiver;

  /// Un envoi accepté dont plus rien n'arrive est abandonné après ce délai.
  final Duration idleTimeout;

  HttpServer? _server;
  Timer? _watchdog;
  final Map<String, _Session> _sessions = {};
  final _random = Random.secure();

  /// Port d'écoute effectif.
  int get port => _server?.port ?? 0;

  /// Démarre le serveur sur [port], ou sur un port libre si celui-ci est pris.
  Future<int> start({int port = sdropPort}) async {
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } on SocketException {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server = server;
    server.listen(_handle, onError: (Object _) {});
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) => _dropIdleSessions());
    return server.port;
  }

  Future<void> stop() async {
    _watchdog?.cancel();
    await _server?.close(force: true);
    _server = null;
    for (final session in [..._sessions.values]) {
      _end(session, complete: false, error: 'Réception interrompue.');
    }
  }

  String _newId() => [for (var i = 0; i < 16; i++) _random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/info') {
        await _json(request, 200, receiver.self.toJson());
      } else if (request.method != 'POST') {
        await _json(request, 405, {'erreur': 'méthode'});
      } else if (path == '/bonjour') {
        await _hello(request);
      } else if (path == '/demande') {
        await _offer(request);
      } else if (path == '/envoi') {
        await _upload(request);
      } else if (path == '/annuler') {
        await _cancel(request);
      } else {
        await _json(request, 404, {'erreur': 'inconnu'});
      }
    } on Object {
      try {
        await _json(request, 500, {'erreur': 'interne'});
      } on Object {
        // Réponse déjà partie ou liaison coupée.
      }
    }
  }

  Future<void> _json(HttpRequest request, int status, Map<String, dynamic> body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  /// Lit un corps JSON de taille bornée ; `null` s'il est trop gros ou illisible.
  Future<Object?> _readJson(HttpRequest request) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytes.add(chunk);
      if (bytes.length > Limits.requestBytes) return null;
    }
    try {
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } on Object {
      return null;
    }
  }

  Future<void> _hello(HttpRequest request) async {
    final info = DeviceInfo.fromJson(await _readJson(request));
    final address = request.connectionInfo?.remoteAddress;
    if (info == null || address == null) return _json(request, 400, {'erreur': 'annonce invalide'});
    if (info.id != receiver.self.id) receiver.hello(info, address);
    await _json(request, 200, receiver.self.toJson());
  }

  Future<void> _offer(HttpRequest request) async {
    final offer = Offer.fromJson(await _readJson(request));
    final address = request.connectionInfo?.remoteAddress;
    if (offer == null || address == null) return _json(request, 400, {'erreur': 'demande invalide'});
    final id = _newId();
    final reply = await receiver.decide(offer, address, id);
    if (!reply.accepted) return _json(request, 403, const OfferReply.refused().toJson());
    if (offer.items.isEmpty) {
      // Texte seul : rien d'autre à recevoir.
      return _json(request, 200, OfferReply(accepted: true, token: reply.token).toJson());
    }
    _sessions[id] = _Session(id, address, offer);
    await _json(request, 200, OfferReply(accepted: true, session: id, token: reply.token).toJson());
  }

  Future<void> _upload(HttpRequest request) async {
    final session = _sessions[request.uri.queryParameters['session']];
    final index = int.tryParse(request.uri.queryParameters['i'] ?? '');
    if (session == null) return _json(request, 404, {'erreur': 'envoi inconnu'});
    // Seul l'appareil dont la demande a été acceptée peut déposer les fichiers.
    if (request.connectionInfo?.remoteAddress != session.address) return _json(request, 403, {'erreur': 'refusé'});
    if (index == null || index < 0 || index >= session.offer.items.length) {
      return _json(request, 400, {'erreur': 'fichier inconnu'});
    }
    if (session.received.contains(index) || !session.inProgress.add(index)) {
      return _json(request, 409, {'erreur': 'déjà reçu'});
    }
    final item = session.offer.items[index];
    if (request.contentLength != item.size) {
      session.inProgress.remove(index);
      return _json(request, 400, {'erreur': 'taille inattendue'});
    }

    File? partial;
    IOSink? sink;
    try {
      final directory = await receiver.directory();
      await directory.create(recursive: true);
      final target = uniqueFile(directory, sanitizeFileName(item.name));
      partial = File('${target.path}.sdrop-part');
      sink = partial.openWrite();
      var count = 0;
      await for (final chunk in request) {
        count += chunk.length;
        if (count > item.size) throw const FormatException('trop de données');
        sink.add(chunk);
        session
          ..bytes += chunk.length
          ..lastActivity = DateTime.now();
        receiver.progress(session.id, session.bytes);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (count != item.size) throw const FormatException('fichier incomplet');
      final file = await partial.rename(target.path);
      session.inProgress.remove(index);
      session.received.add(index);
      receiver.fileReceived(session.id, file);
      await _json(request, 200, {'ok': true});
      if (session.received.length == session.offer.items.length) _end(session, complete: true);
    } on Object catch (error) {
      session.inProgress.remove(index);
      try {
        await sink?.close();
        if (partial != null && partial.existsSync()) await partial.delete();
      } on Object {
        // Le fichier partiel restera, sans conséquence.
      }
      _end(session, complete: false, error: _explain(error));
      try {
        await _json(request, 500, {'erreur': 'réception'});
      } on Object {
        // Liaison déjà coupée.
      }
    }
  }

  static String _explain(Object error) {
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      // 28 (ENOSPC) sous Linux et Android, 112 (ERROR_DISK_FULL) sous Windows.
      if (code == 28 || code == 112) return 'Plus de place sur cet appareil.';
      return 'Impossible d\'écrire dans le dossier de réception.';
    }
    return 'La liaison a été coupée pendant l\'envoi.';
  }

  Future<void> _cancel(HttpRequest request) async {
    final session = _sessions[request.uri.queryParameters['session']];
    if (session != null && request.connectionInfo?.remoteAddress == session.address) {
      _end(session, complete: false, error: 'Envoi annulé par l\'expéditeur.');
    }
    await _json(request, 200, {'ok': true});
  }

  void _dropIdleSessions() {
    final limit = DateTime.now().subtract(idleTimeout);
    for (final session in [..._sessions.values]) {
      if (session.lastActivity.isBefore(limit)) {
        _end(session, complete: false, error: 'L\'expéditeur ne répond plus.');
      }
    }
  }

  void _end(_Session session, {required bool complete, String? error}) {
    if (_sessions.remove(session.id) == null) return;
    receiver.finished(session.id, complete: complete, error: error);
  }
}
