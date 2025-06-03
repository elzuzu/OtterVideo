<#
.SYNOPSIS
    Script avancé pour le transcodage par lots en VVC (lossless) et audio IAMF,
    avec interface utilisateur, validation, et multithreading via ThreadJob.

.DESCRIPTION
    • Télécharge la dernière build complète expérimentale de FFmpeg (git master) avec libvvenc.
    • Télécharge optionnellement iamf-tools pour un authoring audio immersif avancé.
    • Présente une interface utilisateur pour configurer :
        - Utilisation de l'accélération matérielle AMD (AMF) pour le décodage et redimensionnement GPU.
        - Téléchargement et utilisation de iamf-tools (avec iamf-encoder.exe).
        - Extensions des fichiers d'entrée.
        - Conteneur de sortie (MKV/MP4).
        - Qualité VVC (QP).
        - Débit binaire IAMF (pour l'encodeur FFmpeg interne).
        - Résolution vidéo cible (hauteur en pixels).
        - Nombre maximum de jobs parallèles.
    • Propose des sélecteurs de dossiers pour l'entrée et la sortie.
    • Vérifie la validité des valeurs saisies (QP, bitrate, hauteur, nombre de jobs).
    • Utilise ffprobe pour détecter la présence des flux audio/vidéo et adapte le traitement.
    • Télécharge et installe (si nécessaire) le module ThreadJob pour PowerShell 5.1 et 7.
    • Lance les transcodages dans des ThreadJobs (multithreading) avec contrôle de simultanéité.
    • Gère les erreurs de manière robuste et nettoie les fichiers temporaires.

.NOTES
    • Compatible Windows PowerShell 5.1 et PowerShell 7+
    • Nécessite aisément des droits pour installer modules PSGallery si ThreadJob non présent.
    • Fichiers temporaires sont placés dans $env:TEMP et supprimés à la fin de chaque job.

.EXAMPLE
    PS> .\Main.ps1
#>

#region Paramètres initiaux et variables globales
param(
    [switch]$ForceDefaults, # Si présent, saute l'interface graphique et utilise les valeurs par défaut
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
    # Afficher GUI ou utiliser valeurs par défaut
    if (-not $ForceDefaults) {
        if (-not (Show-SettingsForm)) {
            Write-Host "Configuration annulée par l'utilisateur. Arrêt du script." -ForegroundColor Yellow
            return
        }
    } else {
        Write-Host "Utilisation des paramètres par défaut (ou ceux fournis en ligne de commande)." -ForegroundColor Yellow
    }

    Write-Host "`n--- Configuration Actuelle ---" -ForegroundColor Cyan
    $Global:config.GetEnumerator() | ForEach-Object { Write-Host (("{0,-20} : {1}" -f $_.Name, $_.Value)) }
    Write-Host "----------------------------`n" -ForegroundColor Cyan

    # Préparer modules externes
    Ensure-ThreadJob

    # Préparer FFmpeg et iamf-tools
    try {
        Prepare-Tools
    } catch {
        Write-Error "Erreur critique lors de la préparation des outils. Arrêt du script."
        return
    }

    # Sélection des dossiers
    try {
        # Use the InitialInputDir and InitialOutputDir from ov.ps1's own params for the Pick-Folder dialogs
        $inDir  = Pick-Folder -Message "Choisissez le dossier SOURCE contenant les fichiers à transcoder" -InitialDirectory $InitialInputDir
        $outDir = Pick-Folder -Message "Choisissez le dossier de DESTINATION pour les fichiers transcodés" -InitialDirectory $InitialOutputDir
    } catch {
        Write-Error "Sélection de dossier annulée ou échouée : $($_.Exception.Message)"
        return
    }

    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    if ($inDir -eq $outDir) { Write-Error "Les dossiers source et destination ne peuvent pas être identiques."; return }

    # Récupérer la liste des fichiers à traiter (filtrage correct)
    $patterns = $Global:config.InputExtensions
    $filesToProcess = @()
    foreach ($pattern in $patterns) {
        $filesToProcess += Get-ChildItem -Path (Join-Path $inDir "*") -Recurse -File -Include $pattern
    }
    $filesToProcess = $filesToProcess | Sort-Object FullName | Select-Object -Unique
    if (-not $filesToProcess) {
        Write-Warning "Aucun fichier correspondant aux extensions $($Global:config.InputExtensions -join ', ') trouvé dans $inDir."
        return
    }

    Write-Host "`n--- Début du Transcodage (Multithread: $($Global:config.MaxParallelJobs) jobs) ---" -ForegroundColor Cyan

    # Pour que Process-File connaisse la racine
    $Global:inputRoot = $inDir

    # Tableau des jobs
    $jobList = @()

    foreach ($file in $filesToProcess) {
        # Tant que le nombre de jobs en cours atteint MaxParallelJobs, on attend
        while ($jobList.Count -ge $Global:config.MaxParallelJobs) {
            $finished = Wait-Job -Job $jobList -Any -Timeout 2
            if ($finished) {
                foreach ($j in $finished) {
                    $result = Receive-Job -Job $j -ErrorAction SilentlyContinue
                    if ($result.Status -eq "SUCCESS") {
                        Write-Host "Job terminé (OK) : $($j.Name)" -ForegroundColor Green
                    } else {
                        Write-Warning "Job en erreur : $($j.Name) → $($result.Message)"
                    }
                    Remove-Job -Job $j
                    $jobList = $jobList | Where-Object { $_.Id -ne $j.Id }
                }
            } else {
                Start-Sleep -Milliseconds 200
            }
        }

        # Créer un ThreadJob pour ce fichier
        $jobName = "Transcode_$($file.BaseName)"
        # Ensure the ArgumentList matches the updated Process-File signature in Transcoding.psm1
        # Process-File params: $inputFile, $outDir, $inputRoot, $config, $ffExePath, $ffProbePath, $iamfEncoderPath
        $jobArguments = $file.FullName, $outDir, $Global:inputRoot, $Global:config, $ffExe, $ffProbeExe, $iamfEncoderExe
        $job = Start-ThreadJob -Name $jobName -ScriptBlock ${function:Process-File} -ArgumentList $jobArguments
        $jobList += $job
    }

    # Attendre la fin des derniers jobs
    if ($jobList.Count -gt 0) {
        Write-Host "Attente de la fin des jobs restants..." -ForegroundColor Cyan
        Wait-Job -Job $jobList
        foreach ($j in $jobList) {
            $result = Receive-Job -Job $j
            if ($result.Status -eq "SUCCESS") {
                Write-Host "Job finalisé (OK) : $($j.Name)" -ForegroundColor Green
            } else {
                Write-Warning "Job finalisé (ERREUR) : $($j.Name) → $($result.Message)"
            }
            Remove-Job -Job $j
        }
    }

    Write-Host "`n--- Transcodage Terminé pour tous les fichiers ---" -ForegroundColor Cyan
}

Main
#endregion Logique Principale
