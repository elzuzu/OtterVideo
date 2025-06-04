<#
.SYNOPSIS
    Script avancé pour le transcodage par lots en VVC (lossless) et audio IAMF,
    avec interface utilisateur, validation, et multithreading via ThreadJob.

.DESCRIPTION
    # - Télécharge la dernière build complète expérimentale de FFmpeg (git master) avec libvvenc.
    # - Télécharge optionnellement iamf-tools pour un authoring audio immersif avancé.
    # - Présente une interface utilisateur pour configurer :
    #     - Utilisation de l'accélération matérielle AMD (AMF) pour le décodage et redimensionnement GPU.
    #     - Téléchargement et utilisation de iamf-tools (avec iamf-encoder.exe).
    #     - Extensions des fichiers d'entrée.
    #     - Conteneur de sortie (MKV/MP4).
    #     - Qualité VVC (QP).
    #     - Débit binaire IAMF (pour l'encodeur FFmpeg interne).
    #     - Résolution vidéo cible (hauteur en pixels).
    #     - Nombre maximum de jobs parallèles.
    # - Propose des sélecteurs de dossiers pour l'entrée et la sortie.
    # - Vérifie la validité des valeurs saisies (QP, bitrate, hauteur, nombre de jobs).
    # - Utilise ffprobe pour détecter la présence des flux audio/vidéo et adapte le traitement.
    # - Télécharge et installe (si nécessaire) le module ThreadJob pour PowerShell 5.1 et 7.
    # - Lance les transcodages dans des ThreadJobs (multithreading) avec contrôle de simultanéité.
    # - Gère les erreurs de manière robuste et nettoie les fichiers temporaires.

.NOTES
    # - Compatible Windows PowerShell 5.1 et PowerShell 7+
    # - Nécessite aisément des droits pour installer modules PSGallery si ThreadJob non présent.
    # - Fichiers temporaires sont placés dans $env:TEMP et supprimés à la fin de chaque job.

.EXAMPLE
    PS> .\Main.ps1
#>

#region Paramètres initiaux et variables globales
param(
    [string]$InitialInputDir = "",
    [string]$InitialOutputDir = ""
)

# Import configuration from Config.psm1
Import-Module .\Config.psm1 -Force

# Import utility functions from Utils.psm1
Import-Module .\Utils.psm1 -Force

# Import UI functions from UI.psm1
Import-Module .\UI.psm1 -Force

# Import Setup functions from Setup.psm1
Import-Module .\Setup.psm1 -Force

# Import Transcoding functions from Transcoding.psm1
Import-Module .\Transcoding.psm1 -Force

#endregion Paramètres initiaux

#region Logique Principale
function Main {
    # Call the main application window, passing command-line parameters for initial directories
    Show-MainApplicationWindow -InitialInputDir $InitialInputDir -InitialOutputDir $InitialOutputDir
}

Main
#endregion Logique Principale