import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/storage.dart';
import '../../models/peer.dart';
import '../../models/transfer.dart';
import '../../state/drop_controller.dart';
import '../../state/drop_scope.dart';
import '../pick.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';
import 'page_scaffold.dart';
import 'settings_page.dart';

/// Résumé d'une liste de fichiers : « photo.jpg », « photo.jpg et 2 autres ».
String describeFiles(List<String> names) => switch (names.length) {
  0 => '',
  1 => names.first,
  2 => '${names.first} et 1 autre',
  _ => '${names.first} et ${names.length - 1} autres',
};

String _count(int n) => n == 1 ? '1 fichier' : '$n fichiers';

/// Page d'accueil : les demandes reçues, les appareils visibles, les transferts.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.enableDrop});

  /// Accepte les fichiers glissés dans la fenêtre ; par défaut, sur ordinateur seulement.
  final bool? enableDrop;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _dragging = false;

  Future<void> _dropped(DropDoneDetails details) async {
    setState(() => _dragging = false);
    final controller = DropScope.read(context);
    final items = await droppedItems(details.files);
    if (items.isNotEmpty) controller.stage(items: items);
  }

  @override
  Widget build(BuildContext context) {
    final controller = DropScope.of(context);
    final c = context.colors;
    final t = context.text;
    final peers = controller.peers;
    final transfers = controller.transfers;
    final outbox = controller.outbox;

    final page = AppPage(
      header: const _HomeHeader(),
      children: [
        const NoticeArea(),
        if (controller.startError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.gap),
            child: MessageBanner(error: true, message: controller.startError!),
          ),
        for (final request in controller.pending)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.gap),
            child: _RequestTile(request: request),
          ),
        if (outbox != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.gap),
            child: _OutboxTile(outbox: outbox),
          ),
        SectionTitle('Appareils', detail: peers.isEmpty ? null : 'sur le même réseau'),
        if (peers.isEmpty)
          EmptyHint(
            icon: Icons.wifi_tethering_rounded,
            title: 'Aucun appareil pour l\'instant',
            text: 'Ouvrez sDrop sur l\'autre appareil, connecté au même Wi-Fi.',
            action: AppButton(
              label: 'Ajouter par adresse',
              icon: Icons.add_rounded,
              onPressed: () => _askAddress(context),
            ),
          )
        else ...[
          for (final peer in peers)
            Padding(
              padding: const EdgeInsets.only(bottom: Dim.gap),
              child: _PeerTile(peer: peer),
            ),
          if ((widget.enableDrop ?? isDesktop) && outbox == null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 2),
              child: Text('Astuce : glissez des fichiers dans cette fenêtre pour les envoyer.', style: t.caption),
            ),
        ],
        if (transfers.isNotEmpty) ...[
          SectionTitle(
            'Transferts',
            trailing: transfers.any((transfer) => !transfer.active)
                ? InkWell(
                    onTap: controller.clearFinished,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text('Effacer', style: t.button.copyWith(color: c.accent)),
                    ),
                  )
                : null,
          ),
          for (final transfer in transfers)
            Padding(
              padding: const EdgeInsets.only(bottom: Dim.gap),
              child: _TransferTile(transfer: transfer),
            ),
        ],
        const SizedBox(height: Dim.sectionGap),
        Text('Les fichiers reçus sont rangés dans ${controller.downloadPath}', style: t.caption),
      ],
    );

    if (!(widget.enableDrop ?? isDesktop)) return page;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _dropped,
      child: Stack(
        children: [
          page,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.accentSoft.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(Dim.tileRadius),
                    border: Border.all(color: c.accent, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.file_download_outlined, size: 44, color: c.accent),
                      const SizedBox(height: 8),
                      Text('Déposez pour envoyer', style: t.sectionTitle),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final controller = DropScope.of(context);
    final t = context.text;
    return Row(
      children: [
        Image.asset('assets/branding/logo.png', height: 44, filterQuality: FilterQuality.medium),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('sDrop', style: t.pageTitle),
              Text(
                'Visible sous le nom « ${controller.settings.deviceName} »',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.caption,
              ),
            ],
          ),
        ),
        SquareButton(
          icon: Icons.tune_rounded,
          tooltip: 'Réglages',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
        ),
      ],
    );
  }
}

/// Une demande d'envoi reçue : à accepter ou à refuser.
class _RequestTile extends StatefulWidget {
  const _RequestTile({required this.request});

  final PendingRequest request;

  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  bool _always = false;

  @override
  Widget build(BuildContext context) {
    final controller = DropScope.read(context);
    final c = context.colors;
    final t = context.text;
    final offer = widget.request.offer;
    final text = offer.text;
    final isText = offer.items.isEmpty && text != null;
    return Tile(
      active: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconBadge(icon: isText ? Icons.notes_rounded : Icons.file_download_outlined, tone: BadgeTone.onActive),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.request.peerName} veut vous envoyer',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.itemTitle.copyWith(color: c.onActive),
                    ),
                    Text(
                      isText ? 'un texte' : '${_count(offer.items.length)} · ${formatSize(offer.totalBytes)}',
                      style: t.secondary.copyWith(color: c.onActive.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isText ? text : describeFiles([for (final item in offer.items) sanitizeFileName(item.name)]),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: t.body.copyWith(color: c.onActive),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(label: 'Refuser', expand: true, onPressed: () => controller.refuse(widget.request)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: 'Accepter',
                  kind: ButtonKind.primary,
                  expand: true,
                  onPressed: () => controller.accept(widget.request, always: _always),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => setState(() => _always = !_always),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _always ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    size: 22,
                    color: c.onActive,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Toujours accepter cet appareil', style: t.secondary.copyWith(color: c.onActive)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ce qui attend un destinataire (fichiers déposés ou partagés).
class _OutboxTile extends StatelessWidget {
  const _OutboxTile({required this.outbox});

  final Outbox outbox;

  @override
  Widget build(BuildContext context) {
    final controller = DropScope.read(context);
    final t = context.text;
    final summary = outbox.items.isEmpty
        ? 'Un texte à envoyer'
        : '${_count(outbox.items.length)} à envoyer · ${formatSize(outbox.totalBytes)}';
    return Tile(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          const IconBadge(icon: Icons.upload_rounded, tone: BadgeTone.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.itemTitle),
                Text(
                  controller.peers.isEmpty ? 'En attente d\'un appareil…' : 'Choisissez le destinataire ci-dessous.',
                  style: t.secondary,
                ),
              ],
            ),
          ),
          SquareButton(icon: Icons.close_rounded, tooltip: 'Annuler l\'envoi', onPressed: controller.clearOutbox),
        ],
      ),
    );
  }
}

/// Un appareil visible, avec les boutons d'envoi.
class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer});

  final Peer peer;

  Future<void> _pick(BuildContext context, {bool media = false}) async {
    final controller = DropScope.read(context);
    final items = await pickItems(media: media);
    if (items.isNotEmpty) await controller.send(peer, items: items);
  }

  @override
  Widget build(BuildContext context) {
    final controller = DropScope.of(context);
    final t = context.text;
    final staged = controller.outbox != null;
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconBadge(icon: peer.kind == DeviceKind.phone ? Icons.smartphone_rounded : Icons.computer_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.itemTitle),
                    Text(
                      peer.manual ? '${peer.address.address} · ajouté par adresse' : peer.address.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.secondary,
                    ),
                  ],
                ),
              ),
              if (peer.manual)
                SquareButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Oublier cet appareil',
                  onPressed: () => controller.forgetPeer(peer),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (staged)
            AppButton(
              label: 'Envoyer ici',
              icon: Icons.send_rounded,
              kind: ButtonKind.primary,
              expand: true,
              onPressed: () => controller.sendOutbox(peer),
            )
          else
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Fichiers',
                    icon: Icons.attach_file_rounded,
                    kind: ButtonKind.primary,
                    compact: true,
                    expand: true,
                    onPressed: () => _pick(context),
                  ),
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppButton(
                      label: 'Photos',
                      icon: Icons.photo_outlined,
                      compact: true,
                      expand: true,
                      onPressed: () => _pick(context, media: true),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    label: 'Texte',
                    icon: Icons.notes_rounded,
                    compact: true,
                    expand: true,
                    onPressed: () => _askText(context, peer),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Un transfert en cours ou terminé.
class _TransferTile extends StatelessWidget {
  const _TransferTile({required this.transfer});

  final Transfer transfer;

  String _status() => switch (transfer.state) {
    TransferState.waiting => 'En attente de l\'accord du destinataire…',
    TransferState.running =>
      '${formatSize(transfer.bytesDone)} sur ${formatSize(transfer.totalBytes)} · ${(transfer.progress * 100).round()} %',
    TransferState.done => transfer.incoming ? 'Reçu' : 'Envoyé',
    TransferState.refused => 'Refusé par le destinataire',
    TransferState.failed => transfer.error ?? 'Échec',
  };

  @override
  Widget build(BuildContext context) {
    final controller = DropScope.read(context);
    final c = context.colors;
    final t = context.text;
    final failed = transfer.state == TransferState.failed || transfer.state == TransferState.refused;
    final text = transfer.text;
    final summary = transfer.isText
        ? text!
        : '${describeFiles(transfer.fileNames)}${transfer.totalBytes > 0 ? ' · ${formatSize(transfer.totalBytes)}' : ''}';

    Widget? action;
    if (!transfer.incoming && transfer.state == TransferState.running) {
      action = AppButton(label: 'Annuler', compact: true, onPressed: () => controller.cancel(transfer));
    } else if (transfer.incoming && transfer.isText) {
      action = AppButton(
        label: 'Copier',
        icon: Icons.copy_rounded,
        compact: true,
        onPressed: () => Clipboard.setData(ClipboardData(text: text!)),
      );
    } else if (transfer.incoming && isDesktop && transfer.files.isNotEmpty) {
      action = AppButton(
        label: 'Ouvrir',
        icon: Icons.folder_open_rounded,
        compact: true,
        onPressed: () => openFolder(transfer.files.first.parent.path),
      );
    }

    return Tile(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  transfer.incoming ? Icons.south_west_rounded : Icons.north_east_rounded,
                  size: 20,
                  color: failed ? c.danger : (transfer.state == TransferState.done ? c.success : c.textMuted),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      transfer.incoming ? 'De ${transfer.peerName}' : 'Vers ${transfer.peerName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.itemTitle,
                    ),
                    Text(summary, maxLines: transfer.isText ? 4 : 1, overflow: TextOverflow.ellipsis, style: t.body),
                    const SizedBox(height: 2),
                    Text(_status(), style: t.secondary.copyWith(color: failed ? c.danger : c.textMuted)),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 8), action],
            ],
          ),
          if (transfer.state == TransferState.running) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: transfer.progress,
                minHeight: 6,
                backgroundColor: c.surfaceMuted,
                color: c.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Boîte de saisie d'un texte à envoyer à [peer].
Future<void> _askText(BuildContext context, Peer peer) async {
  final controller = DropScope.read(context);
  final field = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (context) => _InputDialog(
      title: 'Texte pour ${peer.name}',
      field: field,
      hint: 'Texte, lien, adresse…',
      confirm: 'Envoyer',
      lines: 5,
      extra: AppButton(
        label: 'Coller',
        icon: Icons.content_paste_rounded,
        compact: true,
        onPressed: () async {
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          if (data?.text != null) field.text = data!.text!;
        },
      ),
    ),
  );
  field.dispose();
  if (text != null && text.trim().isNotEmpty) await controller.send(peer, text: text);
}

/// Boîte de saisie de l'adresse d'un appareil qui n'apparaît pas tout seul.
Future<void> _askAddress(BuildContext context) async {
  final controller = DropScope.read(context);
  final field = TextEditingController();
  final address = await showDialog<String>(
    context: context,
    builder: (context) => _InputDialog(
      title: 'Ajouter un appareil',
      field: field,
      hint: '192.168.1.20',
      confirm: 'Ajouter',
      help: 'Son adresse est affichée dans les réglages de sDrop, sur l\'autre appareil.',
    ),
  );
  field.dispose();
  if (address != null && address.trim().isNotEmpty) await controller.addPeerByAddress(address);
}

class _InputDialog extends StatelessWidget {
  const _InputDialog({
    required this.title,
    required this.field,
    required this.hint,
    required this.confirm,
    this.help,
    this.extra,
    this.lines = 1,
  });

  final String title;
  final TextEditingController field;
  final String hint;
  final String confirm;
  final String? help;
  final Widget? extra;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.sectionTitle),
              if (help != null) ...[const SizedBox(height: 6), Text(help!, style: t.secondary)],
              const SizedBox(height: 14),
              TextField(
                controller: field,
                autofocus: true,
                style: t.body,
                minLines: lines,
                maxLines: lines == 1 ? 1 : 8,
                onSubmitted: lines == 1 ? (value) => Navigator.of(context).pop(value) : null,
                decoration: InputDecoration(hintText: hint),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  ?extra,
                  const Spacer(),
                  AppButton(label: 'Annuler', compact: true, onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  AppButton(
                    label: confirm,
                    kind: ButtonKind.primary,
                    compact: true,
                    onPressed: () => Navigator.of(context).pop(field.text),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
