import 'package:flutter/material.dart';

import '../../data/settings.dart';
import '../../state/drop_scope.dart';
import '../pick.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';
import 'page_scaffold.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  TextEditingController? _name;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = DropScope.of(context);
    final s = controller.settings;
    final c = context.colors;
    final t = context.text;
    final name = _name ??= TextEditingController(text: s.deviceName);

    void set(Settings next) => controller.updateSettings(next);

    void rename() {
      final value = name.text.trim();
      if (value.isEmpty) {
        name.text = s.deviceName;
      } else if (value != s.deviceName) {
        set(s.copyWith(deviceName: value.length > 60 ? value.substring(0, 60) : value));
      }
    }

    final address = controller.addresses.isEmpty
        ? 'Aucun réseau détecté'
        : controller.addresses.map((a) => controller.serverPort == 47873 ? a : '$a:${controller.serverPort}').join(', ');

    return AppPage(
      header: const PageHeader(title: 'Réglages'),
      children: [
        const NoticeArea(),
        const SectionTitle('Cet appareil'),
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: name,
                      style: t.body,
                      onSubmitted: (_) => rename(),
                      decoration: const InputDecoration(labelText: 'Nom vu par les autres appareils'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppButton(label: 'Renommer', onPressed: rename),
                ],
              ),
              const SizedBox(height: 12),
              SettingRow(
                title: 'Adresse',
                subtitle: 'À saisir sur l\'autre appareil s\'il ne trouve pas celui-ci tout seul.',
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: SelectableText(address, textAlign: TextAlign.end, style: t.body.copyWith(color: c.textMuted)),
                ),
              ),
            ],
          ),
        ),

        const SectionTitle('Réception'),
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingRow(
                title: 'Accepter sans demander',
                subtitle: 'Pour les appareils auxquels vous avez choisi de toujours faire confiance.',
                trailing: AppSwitch(value: s.autoAccept, onChanged: (v) => set(s.copyWith(autoAccept: v))),
              ),
              const SizedBox(height: 6),
              Text('Dossier de réception', style: t.body),
              Text(controller.downloadPath, style: t.caption),
              if (isDesktop) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Changer…',
                        icon: Icons.folder_open_rounded,
                        compact: true,
                        expand: true,
                        onPressed: () async {
                          final path = await pickDirectory();
                          if (path != null) set(controller.settings.copyWith(downloadPath: path));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: 'Par défaut',
                        compact: true,
                        expand: true,
                        onPressed: s.downloadPath.isEmpty ? null : () => set(s.copyWith(downloadPath: '')),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        if (s.trusted.isNotEmpty) ...[
          const SectionTitle('Appareils de confiance'),
          Tile(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            child: Column(
              children: [
                for (final entry in s.trusted.entries)
                  SettingRow(
                    title: entry.value.name.isEmpty ? 'Appareil' : entry.value.name,
                    subtitle: 'Ses envois sont acceptés d\'office.',
                    trailing: SquareButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Ne plus faire confiance à ${entry.value.name}',
                      onPressed: () => controller.untrust(entry.key),
                    ),
                  ),
              ],
            ),
          ),
        ],

        const SectionTitle('Apparence'),
        Tile(
          child: SettingBlock(
            title: 'Thème',
            child: Segmented<AppThemeMode>(
              values: AppThemeMode.values,
              selected: s.theme,
              labelOf: (v) => switch (v) {
                AppThemeMode.auto => 'Automatique',
                AppThemeMode.light => 'Clair',
                AppThemeMode.dark => 'Sombre',
              },
              onSelected: (v) => set(s.copyWith(theme: v)),
            ),
          ),
        ),

        const SizedBox(height: Dim.sectionGap),
        Text(
          'Les envois vont directement d\'un appareil à l\'autre, sur votre réseau local, sans passer par '
          'Internet. Ils ne sont pas chiffrés : n\'utilisez sDrop que sur un réseau de confiance, comme '
          'celui de la maison.',
          textAlign: TextAlign.center,
          style: t.caption,
        ),
      ],
    );
  }
}
