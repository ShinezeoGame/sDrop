# sDrop — notes pour Claude

- **Toujours communiquer avec l'utilisateur en français.** L'interface, les commentaires
  et les messages de commit sont aussi en français.
- Application Flutter pour **Android et Windows** (même code) : envoie des fichiers, des
  photos ou un texte entre le téléphone de l'utilisateur (Samsung Galaxy S25) et son PC,
  sur le réseau local, sans câble ni serveur.
- Architecture :
  - `lib/data/net/` : `discovery.dart` (annonces UDP, multidiffusion + diffusion),
    `server.dart` (réception, HTTP), `client.dart` (envoi), `protocol.dart` (formats et
    limites). Port 47873 par défaut, un autre si celui-ci est pris.
  - `lib/state/drop_controller.dart` : tout l'état (appareils visibles, demandes en
    attente, transferts, confiance). Il implémente `DropReceiver`, que le serveur appelle.
  - `lib/data/system_bridge.dart` ↔ `android/.../MainActivity.kt` (canal `sdrop/systeme`) :
    nom du téléphone, verrou de multidiffusion, contenu reçu du menu « Partager ».
- Règles de sécurité à ne pas affaiblir : rien n'est écrit sans demande acceptée ; les noms
  de fichiers reçus passent par `sanitizeFileName` ; un fichier existant n'est jamais écrasé
  (`uniqueFile`) ; les tailles annoncées sont vérifiées ; la confiance repose sur un jeton,
  pas sur l'identifiant annoncé. Les échanges ne sont pas chiffrés (réseau local de
  confiance) : c'est dit dans l'interface et le README, ne pas prétendre le contraire.
- Direction artistique : celle de **sDash** et **sPhone** (autres applications de
  l'utilisateur). Interface à plat (ni texture, ni flou, ni dégradé décoratif), tons
  chauds, thème clair et sombre, police Outfit.
  - Couleurs uniquement par rôle : `context.colors` / `context.text` (`lib/ui/theme.dart`),
    jamais de couleur en dur dans un widget.
  - Tuile ambrée = demande d'envoi à traiter ; ses boutons utilisent `AppButton(onActive: true)`
    (en thème sombre, l'ambre de la tuile est aussi la couleur d'accent).
  - Composants dans `lib/ui/widgets/` ; chaque page passe par `AppPage` (`page_scaffold.dart`).
  - Mise en page étroite, identique sur le téléphone et le PC (fenêtre 420 × 760 par
    défaut, 360 × 480 au minimum) : tout doit tenir sans débordement à ces tailles.
- Vérifications avant de pousser : `flutter analyze` et `flutter test`. `test/core_test.dart`
  lance deux appareils réels sur des ports locaux (`test/support/harness.dart`) ;
  `test/app_test.dart` parcourt l'interface à trois tailles de fenêtre.
- Formatage : `dart format -l 120 lib test`.
- **Publication automatique (demande de l'utilisateur)** : dès qu'un travail est fini et que
  les vérifications passent, l'enregistrer, l'envoyer sur la branche de travail puis sur
  `main` (`git push origin HEAD:main`, en avance rapide), sans demander. Chaque envoi sur
  `main` publie une Release, sauf si seuls des `.md` ou `docs/` changent (`paths-ignore` de
  la CI). Vérifier ensuite que la compilation a réussi et que la Release a ses trois fichiers.
- Captures de la documentation : `SDROP_CAPTURES=1 flutter test test/captures_test.dart`.
- La CI (`.github/workflows/build.yml`) teste, compile l'APK (`sdrop-android`) et
  l'application Windows (`sdrop-windows` : installateur Inno Setup `tools/installer/sdrop.iss`
  et archive), lance l'exécutable Windows et l'interroge sur `/info`. La Release n'est
  publiée que sur `main` ou à la demande.
- Jamais essayé sur un vrai téléphone au moment de l'écriture : la partie Android
  (`MainActivity.kt`, écriture dans `Download/sDrop`, menu « Partager ») n'est vérifiée que
  par la compilation.
- Logo : sDrop, sDash et sPhone forment la marque « s » de l'utilisateur. Règles : même
  carré arrondi orange `#C2571A`, même trait clair à bouts ronds, le dessin de chaque application est **centré** dans le carré, et **le point ambre est posé ensuite dans l'angle en haut à droite**, toujours au même endroit et de la même taille (l'utilisateur a demandé de ne pas décaler le dessin pour faire de la place au point). Seul le dessin
  change : flèche qui tombe dans un bac pour sDrop, maison pour sDash, téléphone pour
  sPhone ; le « S » seul est le signe de la marque.
  Source : `tools/logo/generer_logo.py` (identique dans les trois dépôts, à garder
  synchronisé) → `docs/logo/*.svg`, puis `tools/logo/exporter.py` → PNG, icône Windows et
  icônes Android. Le fond de l'icône adaptative Android est la couleur
  `sdrop_icon_background` (`values/colors.xml`).
