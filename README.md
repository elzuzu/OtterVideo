# OtterVideo - Transcodeur PowerShell VVC/IAMF

## 1. Aperçu

Ce projet fournit un ensemble de scripts PowerShell permettant de transcoder en lot des fichiers vidéo et audio vers les formats modernes H.266/VVC et IAMF. L'interface graphique Windows Forms facilite la configuration tandis que les dépendances externes (FFmpeg, iamf-tools) sont téléchargées et installées automatiquement.

## 2. Fonctionnalités principales

- **Interface graphique** pour définir tous les paramètres de transcodage et suivre la progression.
- **Traitement par lot** des fichiers en conservant l'arborescence des dossiers.
- **Encodage vidéo VVC** via `libvvenc` avec réglage du QP et redimensionnement optionnel.
- **Encodage audio IAMF** au choix via `iamf_encoder.exe` ou l'encodeur interne de FFmpeg, avec bascule en FLAC si nécessaire.
- **Accélération matérielle AMD AMF** pour le décodage et le redimensionnement quand disponible.
- **Gestion automatique des dépendances** : téléchargement de FFmpeg, des iamf-tools, de 7‑Zip portable et installation du module `ThreadJob`.
- **Transcodage multithread** grâce à `ThreadJob`, avec retour en mode séquentiel si le module n'est pas disponible.
- **Détection des flux** audio/vidéo via `ffprobe` avant traitement.
- **Journalisation détaillée** et nettoyage systématique des fichiers temporaires.

## 3. Prérequis

- Windows avec PowerShell 5.1 ou PowerShell 7+
- .NET Framework/Core pour l’interface Windows Forms
- Connexion internet pour le premier lancement (téléchargements automatiques)
- Outil `curl` recommandé sinon `Invoke-WebRequest` est utilisé
- Politique d’exécution autorisant l’exécution de scripts (par exemple : `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`)

## 4. Utilisation

1. Télécharger tous les fichiers du dépôt (`Main.ps1`, `Config.psm1`, `UI.psm1`, `Setup.psm1`, `Transcoding.psm1`, `Utils.psm1`).
2. Ouvrir une console PowerShell et se placer dans le dossier contenant les scripts.
3. Exécuter :
   ```powershell
   .\Main.ps1 [-InitialInputDir <dossier source>] [-InitialOutputDir <dossier cible>]
   ```
4. Configurer les options dans la fenêtre "Paramètres de Transcodage VVC/IAMF".
5. Sélectionner le dossier source puis le dossier de destination et lancer le transcodage.
6. Suivre la progression et les messages dans la zone de log.

## 5. Options de l'interface

- **Utiliser l'accélération AMD** : décodage et redimensionnement GPU.
- **Télécharger iamf-tools** puis **Utiliser iamf-encoder.exe** pour l'audio externe.
- **Extensions d'entrée** à traiter (par défaut `*.mp4,*.mov,*.mkv,*.avi,*.flv,*.webm,*.wav`).
- **Conteneur de sortie** : MKV ou MP4.
- **Qualité VVC (QP)** : 0 = lossless, jusqu’à 63.
- **Débit audio IAMF** (ex. `384k`).
- **Hauteur vidéo cible** en pixels.
- **Nombre max de jobs parallèles** (1‑16).
- **Afficher la sortie complète de FFmpeg** pour un log détaillé.

## 6. Outils externes utilisés

- **FFmpeg** et **ffprobe** pour l’encodage et l’analyse des flux.
- **iamf-tools** pour `iamf_encoder.exe` lorsque choisi.
- **7‑Zip portable** (`7zr.exe`) pour extraire les archives.
- **curl** pour les téléchargements si disponible.

## 7. Dépannage

- Vérifier la politique d’exécution de PowerShell si le script refuse de s’exécuter.
- Contrôler la connexion internet en cas d’échec de téléchargement des outils.
- Si l’installation de `ThreadJob` échoue, le script utilisera un mode mono‑thread plus lent.
- Activer l’option d’affichage complet de FFmpeg pour obtenir les messages d’erreur précis.
- Pour l’audio IAMF, s’assurer que la version de FFmpeg ou des iamf-tools prise en charge est installée.

## 8. Licence

Ces scripts sont fournis tels quels. Respectez les licences des outils tiers (FFmpeg, iamf-tools, 7‑Zip) lors de leur utilisation.
