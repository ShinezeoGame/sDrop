import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/peer.dart';
import '../../models/transfer.dart';
import 'protocol.dart';

/// Échec d'un échange avec un autre appareil, avec un message à afficher.
class DropException implements Exception {
  const DropException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parle au serveur de réception d'un autre appareil (voir `DropServer`).
class DropClient {
  DropClient({Duration connectTimeout = const Duration(seconds: 4)}) {
    _http.connectionTimeout = connectTimeout;
    // Réseau local uniquement : jamais de mandataire entre deux appareils de la maison.
    _http.findProxy = (_) => 'DIRECT';
  }

  final HttpClient _http = HttpClient();
  final Map<String, HttpClientRequest> _uploads = {};

  Uri _uri(InternetAddress address, int port, String path, [Map<String, String>? query]) =>
      Uri(scheme: 'http', host: address.address, port: port, path: path, queryParameters: query);

  Future<(int, Object?)> _post(Uri uri, Object? body, Duration timeout) async {
    try {
      final request = await _http.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      Object? json;
      try {
        json = jsonDecode(text);
      } on Object {
        json = null;
      }
      return (response.statusCode, json);
    } on TimeoutException {
      throw const DropException('L\'appareil ne répond pas.');
    } on SocketException {
      throw const DropException('Appareil injoignable. Vérifiez qu\'il est sur le même réseau et que sDrop y est ouvert.');
    } on HttpException {
      throw const DropException('La liaison avec l\'appareil a été coupée.');
    }
  }

  /// Demande à un appareil qui il est (ajout par adresse).
  Future<DeviceInfo> info(InternetAddress address, int port) async {
    try {
      final request = await _http.getUrl(_uri(address, port, '/info'));
      final response = await request.close().timeout(const Duration(seconds: 5));
      final text = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
      final info = DeviceInfo.fromJson(jsonDecode(text));
      if (info == null) throw const DropException('Cet appareil n\'est pas un appareil sDrop.');
      return info;
    } on DropException {
      rethrow;
    } on Object {
      throw const DropException('Aucun appareil sDrop à cette adresse.');
    }
  }

  /// Se signale à un appareil ; renvoie son identité.
  Future<DeviceInfo?> hello(InternetAddress address, int port, DeviceInfo self) async {
    final (status, json) = await _post(_uri(address, port, '/bonjour'), self.toJson(), const Duration(seconds: 5));
    return status == 200 ? DeviceInfo.fromJson(json) : null;
  }

  /// Demande à [peer] d'accepter un envoi. Attend la décision de son utilisateur.
  Future<OfferReply> offer(Peer peer, Offer offer, {Duration timeout = const Duration(seconds: 150)}) async {
    final (status, json) = await _post(_uri(peer.address, peer.port, '/demande'), offer.toJson(), timeout);
    if (status == 200) return OfferReply.fromJson(json);
    if (status == 403) return const OfferReply.refused();
    throw const DropException('L\'appareil n\'a pas compris la demande.');
  }

  /// Envoie le contenu d'un fichier d'un envoi accepté. [onProgress] reçoit le nombre
  /// d'octets partis pour ce fichier.
  Future<void> upload(Peer peer, String session, int index, OutgoingItem item, void Function(int sent) onProgress) async {
    try {
      final request = await _http.postUrl(
        _uri(peer.address, peer.port, '/envoi', {'session': session, 'i': '$index'}),
      );
      _uploads[session] = request;
      request
        ..contentLength = item.size
        ..headers.contentType = ContentType.binary;
      var sent = 0;
      await request.addStream(
        item.open().map((chunk) {
          sent += chunk.length;
          onProgress(sent);
          return chunk;
        }),
      );
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != 200) throw const DropException('Le destinataire a interrompu la réception.');
    } on DropException {
      rethrow;
    } on FileSystemException {
      throw DropException('Impossible de lire « ${item.name} ».');
    } on Object {
      throw const DropException('La liaison a été coupée pendant l\'envoi.');
    } finally {
      _uploads.remove(session);
    }
  }

  /// Abandonne un envoi en cours et prévient le destinataire.
  Future<void> cancel(Peer peer, String session) async {
    _uploads.remove(session)?.abort();
    try {
      await _post(_uri(peer.address, peer.port, '/annuler', {'session': session}), const {}, const Duration(seconds: 3));
    } on DropException {
      // Destinataire déjà parti.
    }
  }

  void close() => _http.close(force: true);
}
