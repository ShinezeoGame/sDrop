[← Retour à la présentation](../README.md)

# Guide d'utilisation de sDrop

## Installation

- **Téléphone** : téléchargez [`sdrop.apk`](https://github.com/ShinezeoGame/sDrop/releases/latest/download/sdrop.apk),
  ouvrez-le et autorisez l'installation d'applications de sources inconnues si Android le
  demande. Android 11 au minimum.
- **PC** : téléchargez [`sdrop-setup.exe`](https://github.com/ShinezeoGame/sDrop/releases/latest/download/sdrop-setup.exe)
  et lancez-le. L'application n'est pas signée : si Windows affiche « Windows a protégé
  votre ordinateur », cliquez sur « Informations complémentaires » puis « Exécuter quand
  même ». **Au premier lancement, autorisez sDrop sur les réseaux privés** quand le
  pare-feu Windows le demande : sans cela, le PC ne peut ni être vu ni recevoir.
- **Version portable** : [`sdrop-windows.zip`](https://github.com/ShinezeoGame/sDrop/releases/latest/download/sdrop-windows.zip),
  à décompresser, puis lancez `sdrop.exe`.

Les compilations de chaque branche sont aussi disponibles en artefacts **sdrop-android** et
**sdrop-windows** dans l'onglet **Actions** du dépôt.

## Utilisation

1. Ouvrez sDrop sur les deux appareils, connectés au même Wi-Fi. Ils apparaissent l'un
   chez l'autre en quelques secondes.
2. Sur celui qui envoie, choisissez **Fichiers**, **Photos** ou **Texte** sous le nom du
   destinataire. Sur le PC, vous pouvez aussi déposer des fichiers dans la fenêtre puis
   cliquer sur l'appareil destinataire ; sur le téléphone, partager vers sDrop depuis une
   autre application.
3. Sur celui qui reçoit, **Acceptez**. Cochez « Toujours accepter cet appareil » pour vos
   propres appareils : les envois suivants arriveront sans demande. Cette confiance se
   retire dans les réglages.

L'application doit être ouverte sur l'appareil qui reçoit.

Les fichiers reçus sont rangés dans `Téléchargements\sDrop` (sur Android : `Download/sDrop`).
Un fichier du même nom n'est jamais écrasé : le nouveau reçoit un numéro.

## En cas de souci

| Souci | Solution |
| --- | --- |
| Les appareils ne se voient pas | Vérifiez qu'ils sont sur le même Wi-Fi (pas le réseau « invités » de la box). Sur le PC, vérifiez que sDrop est autorisé dans le pare-feu pour les réseaux privés. |
| Toujours rien | **Ajouter par adresse** : saisissez sur un appareil l'adresse affichée dans les réglages de sDrop de l'autre. |
| Les fichiers reçus sont introuvables sur le téléphone | Ils sont dans l'application Mes fichiers → Téléchargements → sDrop. |

## Confidentialité et sécurité

Les envois vont directement d'un appareil à l'autre sur le réseau local. Ils ne sont
**pas chiffrés** : quelqu'un qui écouterait votre réseau pourrait les lire. N'utilisez
sDrop que sur un réseau de confiance, comme celui de la maison, pas sur un Wi-Fi public.

Un appareil du réseau ne peut rien déposer chez vous sans que vous l'acceptiez. La
confiance accordée à un appareil repose sur un jeton secret qui lui est remis, pas sur son
nom ; vous la retirez dans les réglages.
