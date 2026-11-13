import '../../models/peer.dart';

/// Port par défaut : annonces (UDP) et envois (TCP).
const sdropPort = 47873;

/// Groupe de multidiffusion des annonces, limité au réseau local.
const sdropMulticastGroup = '239.83.68.82';

/// Garde-fous appliqués à ce qui arrive du réseau.
abstract final class Limits {
  /// Taille maximale d'une demande (liste de fichiers ou texte), en octets.
  static const requestBytes = 512 * 1024;

  /// Nombre maximal de fichiers dans un envoi.
  static const items = 500;

  /// Longueur maximale d'un texte envoyé.
  static const textLength = 200000;
}

/// Un fichier annoncé dans une demande d'envoi.
class OfferItem {
  const OfferItem({required this.name, required this.size});

  final String name;

  /// Taille en octets.
  final int size;

  Map<String, dynamic> toJson() => {'nom': name, 'taille': size};
}

/// Demande d'envoi : des fichiers, ou un texte.
class Offer {
  const Offer({required this.from, this.token = '', this.items = const [], this.text});

  final DeviceInfo from;

  /// Jeton remis par le destinataire lors d'un envoi précédent, s'il a choisi de toujours
  /// accepter cet appareil.
  final String token;
  final List<OfferItem> items;
  final String? text;

  int get totalBytes => items.fold(0, (sum, item) => sum + item.size);

  Map<String, dynamic> toJson() => {
    'de': from.toJson(),
    if (token.isNotEmpty) 'jeton': token,
    if (items.isNotEmpty) 'elements': [for (final item in items) item.toJson()],
    if (text != null) 'texte': text,
  };

  /// Lit une demande reçue ; `null` si elle est invalide ou dépasse les limites.
  static Offer? fromJson(Object? json) {
    if (json is! Map) return null;
    final from = DeviceInfo.fromJson(json['de']);
    if (from == null) return null;
    final items = <OfferItem>[];
    final rawItems = json['elements'];
    if (rawItems != null) {
      if (rawItems is! List || rawItems.length > Limits.items) return null;
      for (final raw in rawItems) {
        if (raw is! Map) return null;
        final name = raw['nom'], size = raw['taille'];
        if (name is! String || name.isEmpty || size is! int || size < 0) return null;
        items.add(OfferItem(name: name, size: size));
      }
    }
    final text = json['texte'];
    if (text != null && (text is! String || text.length > Limits.textLength)) return null;
    if (items.isEmpty && (text == null || (text as String).isEmpty)) return null;
    final token = json['jeton'];
    return Offer(from: from, token: token is String ? token : '', items: items, text: text as String?);
  }
}

/// Réponse du destinataire à une demande.
class OfferReply {
  const OfferReply({required this.accepted, this.session = '', this.token = ''});

  const OfferReply.refused() : this(accepted: false);

  final bool accepted;

  /// Identifiant à rappeler pour envoyer chaque fichier.
  final String session;

  /// Jeton à présenter aux prochains envois pour être accepté d'office.
  final String token;

  Map<String, dynamic> toJson() => {
    'accepte': accepted,
    if (session.isNotEmpty) 'session': session,
    if (token.isNotEmpty) 'jeton': token,
  };

  static OfferReply fromJson(Object? json) {
    if (json is! Map || json['accepte'] != true) return const OfferReply.refused();
    final session = json['session'], token = json['jeton'];
    return OfferReply(accepted: true, session: session is String ? session : '', token: token is String ? token : '');
  }
}
