import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sdrop/data/net/protocol.dart';
import 'package:sdrop/data/storage.dart';
import 'package:sdrop/models/peer.dart';
import 'package:sdrop/state/drop_controller.dart';

void main() {
  group('nom d\'un fichier reçu', () {
    test('un nom ordinaire est gardé tel quel', () {
      expect(sanitizeFileName('Photo de vacances (1).jpg'), 'Photo de vacances (1).jpg');
      expect(sanitizeFileName('été à la mer.pdf'), 'été à la mer.pdf');
    });

    test('il ne peut pas sortir du dossier de réception', () {
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName(r'..\..\Windows\System32\evil.dll'), 'evil.dll');
      expect(sanitizeFileName('/chemin/absolu/notes.txt'), 'notes.txt');
      expect(sanitizeFileName(r'C:\Users\moi\notes.txt'), 'notes.txt');
      expect(sanitizeFileName('..'), 'fichier');
      expect(sanitizeFileName('dossier/'), 'fichier');
    });

    test('les caractères et les noms interdits sous Windows sont neutralisés', () {
      expect(sanitizeFileName('a<b>c:d"e|f?g*h.txt'), 'a_b_c_d_e_f_g_h.txt');
      expect(sanitizeFileName('CON'), '_CON');
      expect(sanitizeFileName('nul.txt'), '_nul.txt');
      expect(sanitizeFileName('rapport. '), 'rapport');
      expect(sanitizeFileName('ligne\ncoupée.txt'), 'ligne_coupée.txt');
    });

    test('un nom interminable est raccourci en gardant son extension', () {
      final name = sanitizeFileName('${'x' * 400}.jpeg');
      expect(name.length, 180);
      expect(name.endsWith('.jpeg'), isTrue);
    });
  });

  test('un fichier du même nom n\'est jamais écrasé', () {
    final dir = Directory.systemTemp.createTempSync('sdrop_unique');
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(p.basename(uniqueFile(dir, 'photo.jpg').path), 'photo.jpg');
    File(p.join(dir.path, 'photo.jpg')).writeAsStringSync('1');
    expect(p.basename(uniqueFile(dir, 'photo.jpg').path), 'photo (2).jpg');
    File(p.join(dir.path, 'photo (2).jpg')).writeAsStringSync('2');
    expect(p.basename(uniqueFile(dir, 'photo.jpg').path), 'photo (3).jpg');
  });

  test('tailles lisibles', () {
    expect(formatSize(0), '0 o');
    expect(formatSize(999), '999 o');
    expect(formatSize(1536), '1,5 Ko');
    expect(formatSize(12 * 1024 * 1024 + 400 * 1024), '12,4 Mo');
    expect(formatSize(3 * 1024 * 1024 * 1024), '3,0 Go');
  });

  test('dossier de réception par défaut', () {
    expect(defaultDownloadDirectory(android: true).path, '/storage/emulated/0/Download/sDrop');
    expect(
      defaultDownloadDirectory(environment: {'USERPROFILE': p.join('C:', 'Users', 'moi')}, android: false).path,
      p.join('C:', 'Users', 'moi', 'Downloads', 'sDrop'),
    );
  });

  group('messages reçus du réseau', () {
    const from = {'sdrop': 1, 'id': 'abc', 'nom': 'Galaxy S25', 'type': 'telephone', 'port': 47873};

    test('une annonce valide est lue, une annonce étrangère est ignorée', () {
      final info = DeviceInfo.fromJson(from)!;
      expect((info.id, info.name, info.kind, info.port), ('abc', 'Galaxy S25', DeviceKind.phone, 47873));
      expect(DeviceInfo.fromJson({'id': 'abc', 'nom': 'x', 'port': 1}), isNull, reason: 'pas une annonce sDrop');
      expect(DeviceInfo.fromJson({...from, 'port': 70000}), isNull);
      expect(DeviceInfo.fromJson({...from, 'nom': '   '}), isNull);
      expect(DeviceInfo.fromJson('texte'), isNull);
      expect(DeviceInfo.fromJson({...from, 'nom': 'x' * 500})!.name.length, 60);
    });

    test('une demande d\'envoi est validée', () {
      final offer = Offer.fromJson({
        'de': from,
        'elements': [
          {'nom': 'a.jpg', 'taille': 10},
          {'nom': 'b.jpg', 'taille': 32},
        ],
      })!;
      expect(offer.items.length, 2);
      expect(offer.totalBytes, 42);
      expect(Offer.fromJson({'de': from, 'texte': 'bonjour'})!.text, 'bonjour');

      expect(Offer.fromJson({'de': from}), isNull, reason: 'ni fichier ni texte');
      expect(Offer.fromJson({'de': from, 'texte': ''}), isNull);
      expect(
        Offer.fromJson({
          'de': from,
          'elements': [
            {'nom': 'a', 'taille': -1},
          ],
        }),
        isNull,
      );
      expect(
        Offer.fromJson({
          'de': from,
          'elements': [
            {'nom': '', 'taille': 1},
          ],
        }),
        isNull,
      );
      expect(Offer.fromJson({'de': from, 'texte': 'x' * (Limits.textLength + 1)}), isNull);
      expect(
        Offer.fromJson({
          'de': from,
          'elements': List.filled(Limits.items + 1, {'nom': 'a', 'taille': 1}),
        }),
        isNull,
      );
    });

    test('l\'aller-retour d\'une demande conserve son contenu', () {
      const info = DeviceInfo(id: 'abc', name: 'PC', kind: DeviceKind.computer, port: 5000);
      const sent = Offer(
        from: info,
        token: 'jeton',
        items: [OfferItem(name: 'a.txt', size: 3)],
      );
      final read = Offer.fromJson(sent.toJson())!;
      expect((read.from.name, read.token, read.items.single.name, read.items.single.size), ('PC', 'jeton', 'a.txt', 3));
    });
  });

  test('saisie d\'une adresse', () {
    expect(parseAddress(' 192.168.1.20 ')!.$1.address, '192.168.1.20');
    expect(parseAddress('192.168.1.20')!.$2, sdropPort);
    expect(parseAddress('192.168.1.20:5000')!.$2, 5000);
    for (final input in ['', 'bonjour', '192.168.1', '192.168.1.20:abc', '192.168.1.20:0', '::1']) {
      expect(parseAddress(input), isNull, reason: input);
    }
  });
}
