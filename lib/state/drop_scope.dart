import 'package:flutter/widgets.dart';

import 'drop_controller.dart';

/// Rend le [DropController] accessible dans tout l'arbre de widgets.
class DropScope extends InheritedNotifier<DropController> {
  const DropScope({super.key, required DropController controller, required super.child}) : super(notifier: controller);

  /// Récupère le contrôleur et reconstruit le widget à chaque changement d'état.
  static DropController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DropScope>()!.notifier!;

  /// Récupère le contrôleur sans s'abonner aux changements (pour les actions).
  static DropController read(BuildContext context) => context.getInheritedWidgetOfExactType<DropScope>()!.notifier!;
}
