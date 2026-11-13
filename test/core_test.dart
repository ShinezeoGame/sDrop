import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sdrop/models/peer.dart';
import 'package:sdrop/models/transfer.dart';

import 'support/harness.dart';

OutgoingItem memoryItem(String name, List<int> bytes) =>
    OutgoingItem(name: name, size: bytes.length, open: () => Stream.value(bytes));

/// Deux appareils sDrop réels sur cette machine : un téléphone et un PC.
void main() {
  late TestDevice phone;
  late TestDevice pc;

  Future<void> startBoth({Duration decisionTimeout = const Duration(seconds: 5), bool pcAnnounces = true}) async {
    final phonePort = await freePort();
    final pcPort = await freePort();
    phone = await TestDevice.start(
      'Galaxy S25',
      port: phonePort,
      announceTo: [pcPort],
      kind: DeviceKind.phone,
      decisionTimeout: decisionTimeout,
    );
    pc = await TestDevice.start(
      'PC du bureau',
      port: pcPort,
      announceTo: pcAnnounces ? [phonePort] : const [],
      decisionTimeout: decisionTimeout,
    );
    await until(() => phone.controller.peers.isNotEmpty && pc.controller.peers.isNotEmpty, reason: 'découverte');
  }

  tearDown(() async {
    await phone.stop();
    await pc.stop();
  });

  group('découverte', () {
    test('les deux appareils se voient, avec leur nom et leur nature', () async {
      await startBoth();
      final seenByPhone = phone.controller.peers.single;
      final seenByPc = pc.controller.peers.single;
      expect((seenByPhone.name, seenByPhone.kind), ('PC du bureau', DeviceKind.computer));
      expect((seenByPc.name, seenByPc.kind), ('Galaxy S25', DeviceKind.phone));
      expect(seenByPc.port, phone.controller.serverPort);
    });

    test('si les annonces ne passent que dans un sens, ils se voient quand même', () async {
      // Le PC n'annonce rien : c'est en entendant le téléphone qu'il se signale à lui.
      await startBoth(pcAnnounces: false);
      expect(phone.controller.peers.single.name, 'PC du bureau');
      expect(pc.controller.peers.single.name, 'Galaxy S25');
    });

    test('un appareil qui se ferme disparaît de la liste', () async {
      await startBoth();
      await pc.controller.shutdown();
      await until(() => phone.controller.peers.isEmpty, reason: 'oubli du PC');
    });

    test('un changement de nom est répercuté', () async {
      await startBoth();
      await phone.controller.updateSettings(phone.controller.settings.copyWith(deviceName: 'Téléphone de Shine'));
      await until(() => pc.controller.peers.single.name == 'Téléphone de Shine');
    });

    test('ajout par adresse', () async {
      await startBoth();
      expect(await pc.controller.addPeerByAddress('pas une adresse'), isFalse);
      expect(pc.controller.notice!.error, isTrue);
      expect(await pc.controller.addPeerByAddress('127.0.0.1:1'), isFalse, reason: 'personne à cette adresse');
      expect(await pc.controller.addPeerByAddress('127.0.0.1:${pc.controller.serverPort}'), isFalse, reason: 'soi-même');

      expect(await pc.controller.addPeerByAddress('127.0.0.1:${phone.controller.serverPort}'), isTrue);
      expect(pc.peer('Galaxy S25').manual, isTrue);
      expect(pc.controller.settings.manualPeers, ['127.0.0.1:${phone.controller.serverPort}']);
    });
  });

  group('envoi de fichiers', () {
    test('accepté : les fichiers arrivent intacts dans le dossier de réception', () async {
      await startBoth();
      final photo = Uint8List.fromList(List.generate(700000, (i) => (i * 7) % 256));
      final sending = phone.controller.send(
        phone.peer('PC du bureau'),
        items: [memoryItem('photo.jpg', photo), memoryItem('notes.txt', utf8.encode('Penser au pain'))],
      );

      await until(() => pc.controller.pending.isNotEmpty, reason: 'demande reçue');
      final request = pc.controller.pending.single;
      expect(request.peerName, 'Galaxy S25');
      expect(request.offer.items.map((i) => i.name), ['photo.jpg', 'notes.txt']);
      expect(request.offer.totalBytes, 700014);
      expect(phone.controller.transfers.single.state, TransferState.waiting);

      pc.controller.accept(request);
      final sent = await sending;
      expect(sent.state, TransferState.done);
      expect(sent.progress, 1);

      await until(() => pc.controller.transfers.single.state == TransferState.done);
      final received = pc.controller.transfers.single;
      expect(received.incoming, isTrue);
      expect(received.files.map((f) => p.basename(f.path)), ['photo.jpg', 'notes.txt']);
      expect(File(p.join(pc.directory.path, 'photo.jpg')).readAsBytesSync(), photo);
      expect(File(p.join(pc.directory.path, 'notes.txt')).readAsStringSync(), 'Penser au pain');
      expect(pc.controller.pending, isEmpty);
      expect(pc.directory.listSync().where((f) => f.path.endsWith('.sdrop-part')), isEmpty);
    });

    test('dans l\'autre sens, du PC vers le téléphone, depuis un vrai fichier', () async {
      await startBoth();
      final source = File(p.join(pc.directory.path, 'à envoyer.bin'))..writeAsBytesSync(List.filled(123456, 42));
      final sending = pc.controller.send(pc.peer('Galaxy S25'), items: [await OutgoingItem.fromFile(source)]);
      await until(() => phone.controller.pending.isNotEmpty);
      phone.controller.accept(phone.controller.pending.single);
      expect((await sending).state, TransferState.done);
      await until(() => phone.controller.transfers.single.state == TransferState.done);
      expect(File(p.join(phone.directory.path, 'à envoyer.bin')).lengthSync(), 123456);
    });

    test('refusé : rien n\'est écrit, l\'expéditeur est prévenu', () async {
      await startBoth();
      final sending = phone.controller.send(phone.peer('PC du bureau'), items: [memoryItem('a.txt', [1, 2, 3])]);
      await until(() => pc.controller.pending.isNotEmpty);
      pc.controller.refuse(pc.controller.pending.single);
      expect((await sending).state, TransferState.refused);
      expect(pc.directory.listSync(), isEmpty);
      expect(pc.controller.transfers, isEmpty);
      expect(pc.controller.pending, isEmpty);
    });

    test('sans réponse, la demande est refusée d\'elle-même', () async {
      await startBoth(decisionTimeout: const Duration(milliseconds: 400));
      final sent = await phone.controller.send(phone.peer('PC du bureau'), items: [memoryItem('a.txt', [1])]);
      expect(sent.state, TransferState.refused);
      expect(pc.controller.pending, isEmpty);
    });

    test('un nom piégé ne sort pas du dossier, un doublon n\'écrase rien', () async {
      await startBoth();
      File(p.join(pc.directory.path, 'rapport.txt')).writeAsStringSync('ancien');
      final sending = phone.controller.send(
        phone.peer('PC du bureau'),
        items: [memoryItem('../../../rapport.txt', utf8.encode('nouveau')), memoryItem(r'..\secret.txt', [9])],
      );
      await until(() => pc.controller.pending.isNotEmpty);
      pc.controller.accept(pc.controller.pending.single);
      await sending;
      await until(() => pc.controller.transfers.single.state == TransferState.done);
      expect(File(p.join(pc.directory.path, 'rapport.txt')).readAsStringSync(), 'ancien');
      expect(File(p.join(pc.directory.path, 'rapport (2).txt')).readAsStringSync(), 'nouveau');
      expect(File(p.join(pc.directory.path, 'secret.txt')).existsSync(), isTrue);
      expect(pc.directory.parent.listSync().where((f) => p.basename(f.path) == 'rapport.txt'), isEmpty);
    });

    test('annulé en cours de route : le destinataire le sait et ne garde pas de fichier partiel', () async {
      await startBoth();
      // Un fichier qui n'arrive que par petits morceaux espacés.
      Stream<List<int>> slow() async* {
        for (var i = 0; i < 200; i++) {
          yield List.filled(1000, i % 256);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      final sending = phone.controller.send(
        phone.peer('PC du bureau'),
        items: [OutgoingItem(name: 'film.mkv', size: 200000, open: slow)],
      );
      await until(() => pc.controller.pending.isNotEmpty);
      pc.controller.accept(pc.controller.pending.single);
      await until(() => pc.controller.transfers.isNotEmpty && pc.controller.transfers.single.bytesDone > 3000);

      await phone.controller.cancel(phone.controller.transfers.single);
      final sent = await sending;
      expect(sent.state, TransferState.failed);
      expect(sent.error, 'Envoi annulé.');
      await until(() => pc.controller.transfers.single.state == TransferState.failed, reason: 'échec côté réception');
      await until(() => pc.directory.listSync().isEmpty, reason: 'fichier partiel supprimé');
    });

    test('destinataire injoignable : l\'échec est expliqué', () async {
      await startBoth();
      final target = phone.peer('PC du bureau');
      await pc.controller.shutdown();
      final sent = await phone.controller.send(target, items: [memoryItem('a.txt', [1])]);
      expect(sent.state, TransferState.failed);
      expect(sent.error, contains('injoignable'));
    });
  });

  group('envoi de texte', () {
    test('le texte accepté apparaît chez le destinataire', () async {
      await startBoth();
      final sending = pc.controller.send(pc.peer('Galaxy S25'), text: 'https://exemple.fr/une-adresse\nà ouvrir');
      await until(() => phone.controller.pending.isNotEmpty);
      expect(phone.controller.pending.single.offer.text, startsWith('https://exemple.fr'));
      phone.controller.accept(phone.controller.pending.single);
      expect((await sending).state, TransferState.done);
      final received = phone.controller.transfers.single;
      expect(received.isText, isTrue);
      expect(received.text, 'https://exemple.fr/une-adresse\nà ouvrir');
      expect(received.state, TransferState.done);
    });
  });

  group('appareils de confiance', () {
    test('« toujours accepter » : les envois suivants passent sans demander', () async {
      await startBoth();
      final target = phone.peer('PC du bureau');
      final first = phone.controller.send(target, items: [memoryItem('1.txt', [1])]);
      await until(() => pc.controller.pending.isNotEmpty);
      pc.controller.accept(pc.controller.pending.single, always: true);
      expect((await first).state, TransferState.done);
      expect(pc.controller.settings.trusted['id-Galaxy S25']!.name, 'Galaxy S25');
      expect(phone.controller.settings.tokens['id-PC du bureau'], isNotEmpty);

      // Deuxième envoi : accepté d'office.
      final second = await phone.controller.send(target, items: [memoryItem('2.txt', [2])]);
      expect(second.state, TransferState.done);
      expect(pc.controller.pending, isEmpty);
      await until(() => File(p.join(pc.directory.path, '2.txt')).existsSync());
    });

    test('la confiance repose sur le jeton, pas sur le nom : sans jeton, il faut accepter', () async {
      await startBoth();
      final target = phone.peer('PC du bureau');
      final first = phone.controller.send(target, text: 'un');
      await until(() => pc.controller.pending.isNotEmpty);
      pc.controller.accept(pc.controller.pending.single, always: true);
      await first;

      // Un appareil qui se présente sous la même identité mais sans le jeton.
      await phone.controller.updateSettings(phone.controller.settings.copyWith(tokens: const {}));
      final second = phone.controller.send(target, text: 'deux');
      await until(() => pc.controller.pending.isNotEmpty, reason: 'la demande doit être soumise à l\'utilisateur');
      pc.controller.refuse(pc.controller.pending.single);
      expect((await second).state, TransferState.refused);
    });

    test('retirer la confiance ou couper l\'acceptation automatique redemande', () async {
      await startBoth();
      final target = phone.peer('PC du bureau');
      final first = phone.controller.send(target, text: 'un');
      await until(() => pc.controller.pending.isNotEmpty);
      pc.controller.accept(pc.controller.pending.single, always: true);
      await first;

      await pc.controller.updateSettings(pc.controller.settings.copyWith(autoAccept: false));
      final second = phone.controller.send(target, text: 'deux');
      await until(() => pc.controller.pending.isNotEmpty);
      pc.controller.accept(pc.controller.pending.single);
      await second;

      await pc.controller.updateSettings(pc.controller.settings.copyWith(autoAccept: true));
      await pc.controller.untrust('id-Galaxy S25');
      final third = phone.controller.send(target, text: 'trois');
      await until(() => pc.controller.pending.isNotEmpty);
      pc.controller.refuse(pc.controller.pending.single);
      expect((await third).state, TransferState.refused);
    });
  });

  group('serveur de réception', () {
    Future<(int, String)> post(int port, String path, Object body) async {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
      if (body is List<int>) {
        request.add(body);
      } else {
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      client.close();
      return (response.statusCode, text);
    }

    test('un dépôt sans demande acceptée est rejeté', () async {
      await startBoth();
      final port = pc.controller.serverPort;
      expect((await post(port, '/envoi?session=inconnue&i=0', [1, 2, 3])).$1, 404);
      expect((await post(port, '/demande', {'n\'importe': 'quoi'})).$1, 400);
      expect((await post(port, '/demande', 'x' * 600000)).$1, 400, reason: 'demande trop volumineuse');
      expect((await post(port, '/inconnu', const {})).$1, 404);
      expect(pc.controller.pending, isEmpty);
      expect(pc.directory.listSync(), isEmpty);
    });

    test('un fichier plus gros qu\'annoncé est refusé', () async {
      await startBoth();
      final port = pc.controller.serverPort;
      final offering = post(port, '/demande', {
        'de': {'sdrop': 1, 'id': 'intrus', 'nom': 'Intrus', 'type': 'ordinateur', 'port': 9},
        'elements': [
          {'nom': 'petit.txt', 'taille': 4},
        ],
      });
      await until(() => pc.controller.pending.isNotEmpty);
      pc.controller.accept(pc.controller.pending.single);
      final (status, body) = await offering;
      expect(status, 200);
      final session = (jsonDecode(body) as Map)['session'] as String;

      expect((await post(port, '/envoi?session=$session&i=0', List.filled(5000, 1))).$1, 400);
      expect((await post(port, '/envoi?session=$session&i=7', [1, 2, 3, 4])).$1, 400);
      expect(pc.directory.listSync(), isEmpty);
    });
  });
}
