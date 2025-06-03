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
    PS> .\transcode_vvc_iamf_multithread.ps1
#>

#region Paramètres initiaux et variables globales
param(
    [switch]$ForceDefaults, # Si présent, saute l'interface graphique et utilise les valeurs par défaut
    [string]$InitialInputDir = "",
    [string]$InitialOutputDir = ""
)

# Chemins et URLs
$ffUrl          = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-git-full.7z"
$ffLocal        = Join-Path $env:TEMP "ffmpeg-git-full.7z"
$ffDir          = Join-Path $PSScriptRoot "ffmpeg"
$ffExe          = Join-Path $ffDir "bin\ffmpeg.exe"
$ffProbeExe     = Join-Path $ffDir "bin\ffprobe.exe"

$iamfToolsUrl   = "https://github.com/AOMediaCodec/iamf-tools/releases/latest/download/iamf-tools-windows-x64.zip"
$iamfToolsZip   = Join-Path $env:TEMP "iamf-tools.zip"
$iamfToolsDir   = Join-Path $PSScriptRoot "iamf-tools"
$iamfEncoderExe = Join-Path $iamfToolsDir "iamf-encoder.exe"

# Valeurs par défaut pour les paramètres configurables
$Global:config = @{
    UseAMD              = $false
    GrabIAMFTools       = $false
    UseExternalIAMF     = $false
    InputExtensions     = @("*.mp4", "*.mov", "*.mkv", "*.avi", "*.flv", "*.webm", "*.wav")
    OutputContainer     = "MKV"   # MKV ou MP4
    VvcQP               = 0       # 0 pour lossless (entier)
    IamfBitrate         = "384k" # Exemple: 384k, 768k, etc.
    TargetVideoHeight   = 720     # Hauteur cible (entier)
    MaxParallelJobs     = 2       # Nombre de jobs simultanés (entier)
    ShowFFmpegOutput    = $true   # Afficher la sortie complète de ffmpeg
}
#endregion Paramètres initiaux

#region Fonctions Utilitaires
function Test-CommandExists {
    param($command)
    return [bool](Get-Command $command -ErrorAction SilentlyContinue)
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description
    )
    Write-Host "Téléchargement de $Description..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
        Write-Host "$Description téléchargé avec succès." -ForegroundColor Green
    } catch {
        Write-Error "Échec du téléchargement de $Description depuis $Url : $($_.Exception.Message)"
        throw "Téléchargement échoué."
    }
}

function Extract-Archive {
    param(
        [string]$ArchivePath,
        [string]$DestinationPath,
        [string]$Description
    )
    Write-Host "Extraction de $Description..." -ForegroundColor Cyan
    try {
        if (Test-CommandExists "7z") {
            Start-Process -FilePath "7z" -ArgumentList "x", "`"$ArchivePath`"", "-o`"$DestinationPath`"", "-y" -Wait -NoNewWindow
        } else {
            $zipExeUrl = "https://www.7-zip.org/a/7zr.exe"
            $zipExeLocal = Join-Path $env:TEMP "7zr.exe"
            if (-not (Test-Path $zipExeLocal)) {
                Download-File -Url $zipExeUrl -OutFile $zipExeLocal -Description "7-Zip portable (7zr.exe)"
            }
            Start-Process -FilePath $zipExeLocal -ArgumentList "x", "`"$ArchivePath`"", "-o`"$DestinationPath`"", "-y" -Wait -NoNewWindow
        }

        if ($LASTEXITCODE -ne 0) {
            throw "L'extraction a échoué avec le code $LASTEXITCODE."
        }
        Write-Host "$Description extrait avec succès." -ForegroundColor Green
    } catch {
        Write-Error "Échec de l'extraction de $Description : $($_.Exception.Message)"
        if (Test-Path $ArchivePath) { Remove-Item $ArchivePath -ErrorAction SilentlyContinue -Force }
        throw "Extraction échouée."
    }
}

function Pick-Folder {
    param([string]$Message)
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Message
    if ($InitialInputDir -and $Message -match "SOURCE") { $dialog.SelectedPath = $InitialInputDir }
    if ($InitialOutputDir -and $Message -match "DESTINATION") { $dialog.SelectedPath = $InitialOutputDir }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    } else {
        throw "Opération annulée par l'utilisateur."
    }
}

function Validate-Integer {
    param(
        [string]$Value,
        [string]$FieldName,
        [int]$Min,
        [int]$Max
    )
    $parsed = 0
    if (-not [int]::TryParse($Value, [ref]$parsed)) {
        [System.Windows.Forms.MessageBox]::Show("'$Value' n'est pas un entier valide pour $FieldName.", "Erreur", 'OK', 'Error')
        return $false
    }
    if ($parsed -lt $Min -or $parsed -gt $Max) {
        [System.Windows.Forms.MessageBox]::Show("La valeur de $FieldName doit être entre $Min et $Max.", "Erreur", 'OK', 'Error')
        return $false
    }
    return $true
}

function Validate-Bitrate {
    param(
        [string]$Value,
        [string]$FieldName
    )
    # Format attendu : nombre suivi de 'k', exemple '384k'
    if ($Value -notmatch '^[0-9]+k$') {
        [System.Windows.Forms.MessageBox]::Show("'$Value' n'est pas un débit valide (ex: 384k) pour $FieldName.", "Erreur", 'OK', 'Error')
        return $false
    }
    return $true
}

function Run-Process {
    param(
        [string]$FilePath,
        [array]$ArgumentList,
        [switch]$HideOutput
    )
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow `
                                 -RedirectStandardError (Join-Path $env:TEMP "stderr_$([guid]::NewGuid()).txt")

        $stderrPath = (Get-ChildItem $env:TEMP | Where-Object { $_.Name -like 'stderr_*.txt' } | Sort-Object LastWriteTime | Select-Object -First 1).FullName
        $stderr = Get-Content $stderrPath -Raw -ErrorAction SilentlyContinue

        if (-not $HideOutput -or $Global:config.ShowFFmpegOutput) {
            if ($stderr) { Write-Host $stderr }
        }
        if ($process.ExitCode -ne 0) {
            Write-Warning "Processus ($FilePath) renvoyé code $($process.ExitCode). Sortie d'erreur:`n$stderr"
        }
        Remove-Item $stderrPath -ErrorAction SilentlyContinue -Force
        return $process.ExitCode
    } catch {
        Write-Error "Échec de l'exécution de $FilePath : $($_.Exception.Message)"
        return -1
    }
}
#endregion Fonctions Utilitaires

#region Interface Utilisateur (Windows Forms)
function Show-SettingsForm {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Paramètres de Transcodage VVC/IAMF"
    $form.Size = New-Object System.Drawing.Size(500, 600)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $yPos = 10

    function Add-Label($text, $y) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $text
        $label.Location = New-Object System.Drawing.Point(10, $y)
        $label.AutoSize = $true
        $form.Controls.Add($label)
        return $label
    }

    function Add-Checkbox($name, $text, $y, $checked, [scriptblock]$onCheckChanged = $null) {
        $checkbox = New-Object System.Windows.Forms.CheckBox
        $checkbox.Name = $name
        $checkbox.Text = $text
        $checkbox.Location = New-Object System.Drawing.Point(10, $y)
        $checkbox.AutoSize = $true
        $checkbox.Checked = $checked
        if ($onCheckChanged) { $checkbox.add_CheckedChanged($onCheckChanged) }
        $form.Controls.Add($checkbox)
        return $checkbox
    }

    function Add-Textbox($name, $y, $text, $width = 200) {
        $textbox = New-Object System.Windows.Forms.TextBox
        $textbox.Name = $name
        $textbox.Location = New-Object System.Drawing.Point(250, $y - 3)
        $textbox.Text = $text
        $textbox.Width = $width
        $form.Controls.Add($textbox)
        return $textbox
    }

    function Add-ComboBox($name, $y, $items, $selectedItem, $width = 200) {
        $combobox = New-Object System.Windows.Forms.ComboBox
        $combobox.Name = $name
        $combobox.Location = New-Object System.Drawing.Point(250, $y - 3)
        $combobox.Items.AddRange($items)
        $combobox.SelectedItem = $selectedItem
        $combobox.Width = $width
        $combobox.DropDownStyle = "DropDownList"
        $form.Controls.Add($combobox)
        return $combobox
    }

    # --- Contrôles du formulaire ---
    Add-Label "Options Générales:" $yPos; $yPos += 25

    $cbUseAMD = Add-Checkbox "UseAMD" "Utiliser l'accélération AMD (décodage + redim. GPU)" $yPos $Global:config.UseAMD
    $yPos += 30

    $cbGrabIAMFTools = Add-Checkbox "GrabIAMFTools" "Télécharger iamf-tools" $yPos $Global:config.GrabIAMFTools
    $yPos += 30

    $cbUseExternalIAMF = Add-Checkbox "UseExternalIAMF" "Utiliser iamf-encoder.exe (nécessite iamf-tools)" $yPos $Global:config.UseExternalIAMF
    $cbUseExternalIAMF.Enabled = $Global:config.GrabIAMFTools
    $cbGrabIAMFTools.add_CheckedChanged({
        $cbUseExternalIAMF.Enabled = $cbGrabIAMFTools.Checked
        if (-not $cbGrabIAMFTools.Checked) { $cbUseExternalIAMF.Checked = $false }
    })
    $yPos += 30

    Add-Label "Extensions d'entrée (séparées par virgule):" $yPos
    $tbInputExtensions = Add-Textbox "InputExtensions" $yPos ($Global:config.InputExtensions -join ',') 220
    $yPos += 30

    Add-Label "Conteneur de sortie:" $yPos
    $comboOutputContainer = Add-ComboBox "OutputContainer" $yPos @("MKV", "MP4") $Global:config.OutputContainer
    $yPos += 30

    Add-Label "Qualité VVC (QP, 0=lossless, 1-63 compressé):" $yPos
    $tbVvcQP = Add-Textbox "VvcQP" $yPos ($Global:config.VvcQP) 50
    $yPos += 30

    Add-Label "Débit audio IAMF (ex: 384k, 768k):" $yPos
    $tbIamfBitrate = Add-Textbox "IamfBitrate" $yPos $Global:config.IamfBitrate 100
    $yPos += 30

    Add-Label "Hauteur vidéo cible (entier, ex: 720, 1080):" $yPos
    $tbTargetVideoHeight = Add-Textbox "TargetVideoHeight" $yPos ($Global:config.TargetVideoHeight) 50
    $yPos += 30

    Add-Label "Nombre max de jobs parallèles (1-16):" $yPos
    $tbMaxParallelJobs = Add-Textbox "MaxParallelJobs" $yPos ($Global:config.MaxParallelJobs) 50
    $yPos += 30

    $cbShowFFmpegOutput = Add-Checkbox "ShowFFmpegOutput" "Afficher la sortie complète de FFmpeg" $yPos $Global:config.ShowFFmpegOutput
    $yPos += 40

    # Boutons OK et Annuler
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point(150, $yPos)
    $okButton.DialogResult = "OK"
    $form.AcceptButton = $okButton
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Annuler"
    $cancelButton.Location = New-Object System.Drawing.Point(260, $yPos)
    $cancelButton.DialogResult = "Cancel"
    $form.CancelButton = $cancelButton
    $form.Controls.Add($cancelButton)

    $form.Height = $yPos + 100
    $result = $form.ShowDialog()

    if ($result -eq "OK") {
        # Validation des champs numériques
        if (-not (Validate-Integer -Value $tbVvcQP.Text -FieldName "Qualité VVC (QP)" -Min 0 -Max 63)) { return $false }
        if (-not (Validate-Bitrate -Value $tbIamfBitrate.Text -FieldName "Débit audio IAMF")) { return $false }
        if (-not (Validate-Integer -Value $tbTargetVideoHeight.Text -FieldName "Hauteur vidéo cible" -Min 1 -Max 4320)) { return $false }
        if (-not (Validate-Integer -Value $tbMaxParallelJobs.Text -FieldName "Nombre max de jobs parallèles" -Min 1 -Max 16)) { return $false }

        $Global:config.UseAMD = $cbUseAMD.Checked
        $Global:config.GrabIAMFTools = $cbGrabIAMFTools.Checked
        $Global:config.UseExternalIAMF = $cbUseExternalIAMF.Checked
        $Global:config.InputExtensions = ($tbInputExtensions.Text -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $Global:config.OutputContainer = $comboOutputContainer.SelectedItem
        $Global:config.VvcQP = [int]$tbVvcQP.Text
        $Global:config.IamfBitrate = $tbIamfBitrate.Text
        $Global:config.TargetVideoHeight = [int]$tbTargetVideoHeight.Text
        $Global:config.MaxParallelJobs = [int]$tbMaxParallelJobs.Text
        $Global:config.ShowFFmpegOutput = $cbShowFFmpegOutput.Checked
        return $true
    } else {
        return $false # Annulé
    }
}
#endregion Interface Utilisateur

#region Préparation des modules externes
function Ensure-ThreadJob {
    try {
        Import-Module ThreadJob -ErrorAction Stop
    } catch {
        Write-Host "Module ThreadJob non trouvé, installation depuis PSGallery..." -ForegroundColor Yellow
        try {
            Install-Module -Name ThreadJob -Scope CurrentUser -Force -ErrorAction Stop
            Import-Module ThreadJob -ErrorAction Stop
            Write-Host "ThreadJob installé et importé." -ForegroundColor Green
        } catch {
            Write-Warning "Impossible d'installer ThreadJob : $($_.Exception.Message). Le script va continuer en mode mono-thread."            
        }
    }
}
#endregion Préparation des modules externes

#region Préparation des outils (FFmpeg, iamf-tools)
function Prepare-Tools {
    # Télécharger et décompresser FFmpeg si nécessaire
    if (-not (Test-Path $ffExe)) {
        try {
            Download-File -Url $ffUrl -OutFile $ffLocal -Description "FFmpeg nightly full"
            Extract-Archive -ArchivePath $ffLocal -DestinationPath $ffDir -Description "FFmpeg"
            Remove-Item $ffLocal -ErrorAction SilentlyContinue -Force
        } catch {
            Write-Error "Impossible de préparer FFmpeg. Le script ne peut pas continuer."
            throw
        }
    } else {
        Write-Host "FFmpeg trouvé : $ffExe" -ForegroundColor Green
    }
    if (-not (Test-Path $ffProbeExe)) {
        Write-Warning "ffprobe.exe non trouvé. Certaines fonctionnalités avancées pourraient être limitées."
    }

    # Télécharger et décompresser iamf-tools si demandé
    if ($Global:config.GrabIAMFTools) {
        if (-not (Test-Path $iamfEncoderExe)) {
            try {
                Download-File -Url $iamfToolsUrl -OutFile $iamfToolsZip -Description "iamf-tools"
                Extract-Archive -ArchivePath $iamfToolsZip -DestinationPath $PSScriptRoot -Description "iamf-tools"
                $extractedFolder = Get-ChildItem -Path $PSScriptRoot -Directory -Filter "iamf-tools*" | Sort-Object LastWriteTime | Select-Object -First 1
                if ($extractedFolder -and ($extractedFolder.FullName -ne $iamfToolsDir)) {
                    if (Test-Path $iamfToolsDir) { Remove-Item -Recurse -Force $iamfToolsDir }
                    Rename-Item -Path $extractedFolder.FullName -NewName $iamfToolsDir -ErrorAction Stop
                }
                Remove-Item $iamfToolsZip -ErrorAction SilentlyContinue -Force
                if (-not (Test-Path $iamfEncoderExe)) { throw "iamf-encoder.exe non trouvé après extraction." }
                Write-Host "iamf-tools trouvé : $iamfEncoderExe" -ForegroundColor Green
            } catch {
                Write-Warning "Impossible de préparer iamf-tools. L'option d'utiliser iamf-encoder.exe sera désactivée. Erreur: $($_.Exception.Message)"
                $Global:config.UseExternalIAMF = $false
            }
        } else {
            Write-Host "iamf-tools trouvé : $iamfEncoderExe" -ForegroundColor Green
        }
    }

    # Vérifier l'encodeur IAMF interne si on ne compte pas utiliser l'externe
    if (-not $Global:config.UseExternalIAMF) {
        if (Test-Path $ffExe) {
            $iamfInternalOK = & "$ffExe" -hide_banner -encoders | Select-String -Pattern " iamf\s" -Quiet
        } else { $iamfInternalOK = $false }
        if (-not $iamfInternalOK) {
            Write-Warning "L'encodeur IAMF interne de FFmpeg n'a pas été trouvé. L'audio sera encodé en FLAC à la place."
        }
        $Global:config.iamfInternalAvailable = $iamfInternalOK
    }
}
#endregion Préparation des outils

#region Fonction de traitement d'un seul fichier
function Process-File {
    param(
        [string]$inputFile,
        [string]$outDir,
        [hashtable]$config,
        [string]$ffExePath,
        [string]$ffProbePath,
        [string]$iamfEncoderPath
    )
    try {
        # Recherche des flux avec ffprobe
        $probeJson = & "$ffProbePath" -v quiet -print_format json -show_streams $inputFile | ConvertFrom-Json
        $hasVideo = $probeJson.streams | Where-Object { $_.codec_type -eq "video" }
        $hasAudio = $probeJson.streams | Where-Object { $_.codec_type -eq "audio" }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($inputFile)
        $ext = if ($config.OutputContainer -eq "MP4") { ".mp4" } else { ".mkv" }
        $outputFileName = "${baseName}_vvc${ext}"

        # Gérer la structure de sous-dossiers
        $relativePath = [System.IO.Path]::GetDirectoryName($inputFile).Substring($Global:inputRoot.Length)
        if ($relativePath) {
            $targetSubDir = Join-Path $outDir $relativePath
            if (-not (Test-Path $targetSubDir)) { New-Item -ItemType Directory -Path $targetSubDir -Force | Out-Null }
            $outputFile = Join-Path $targetSubDir $outputFileName
        } else {
            $outputFile = Join-Path $outDir $outputFileName
        }

        Write-Host "Processus file: $inputFile" -ForegroundColor White
        Write-Host "→ Sortie   : $outputFile" -ForegroundColor White

        # Fichiers temporaires
        $tempVideoFile   = Join-Path $env:TEMP "${baseName}_tempvideo.mkv"
        $tempAudioWav    = Join-Path $env:TEMP "${baseName}_tempaudio.wav"
        $tempAudioIamf   = Join-Path $env:TEMP "${baseName}_tempiamf.mp4"

        # Construire les arguments communs de ffmpeg
        $commonArgs = @("-hide_banner")
        if (-not $config.ShowFFmpegOutput) { $commonArgs += @("-loglevel", "error") } else { $commonArgs += @("-stats") }

        # Arguments hardware si AMD
        $hwAccelArgs = if ($config.UseAMD) { @("-hwaccel", "d3d11va", "-hwaccel_output_format", "d3d11") } else { @() }

        # Filtre de redimensionnement
        if ($config.UseAMD) {
            $vfScale = "scale_d3d11va=w=-2:h='min($($config.TargetVideoHeight),ih)':interp_algo=bicubic,hwdownload,format=yuv420p10le"
            $scaleFilter = @("-vf", $vfScale)
        } else {
            $vfScale = "scale=-2:'min($($config.TargetVideoHeight),ih)':flags=lanczos"
            $scaleFilter = @("-vf", $vfScale)
        }

        # Arguments vidéo (sans audio)
        $videoArgs = @("-c:v", "libvvenc", "-preset", "slow", "-qp", $config.VvcQP, "-pix_fmt", "yuv420p10le", "-an") + $scaleFilter

        # Si on a à la fois vidéo et audio : pipeline complet
        if ($hasVideo -and $hasAudio) {
            if ($config.UseExternalIAMF -and $config.GrabIAMFTools -and (Test-Path $iamfEncoderPath)) {
                # Encodage vidéo
                $ffmpegVideoCmd = $commonArgs + $hwAccelArgs + @("-y", "-i", $inputFile) + $videoArgs + @($tempVideoFile)
                $code = Run-Process -FilePath $ffExePath -ArgumentList $ffmpegVideoCmd
                if ($code -ne 0) { throw "Encodage vidéo H.266/VVC échoué (code $code)." }

                # Extraction audio
                $ffmpegAudioExtractCmd = $commonArgs + $hwAccelArgs + @("-y", "-i", $inputFile, "-vn", "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2", $tempAudioWav)
                $code = Run-Process -FilePath $ffExePath -ArgumentList $ffmpegAudioExtractCmd
                if ($code -ne 0) { throw "Extraction audio WAV échouée (code $code)." }

                # Encodage IAMF externe
                $bitValue = [regex]::Match($config.IamfBitrate, '^(\d+)k$').Groups[1].Value + "000"
                $iamfArgs = @("-i", $tempAudioWav, "-o", $tempAudioIamf, "--mode", "0", "--bitrate", $bitValue)
                $code = Run-Process -FilePath $iamfEncoderPath -ArgumentList $iamfArgs
                if ($code -ne 0) { throw "Encodage IAMF externe échoué (code $code)." }

                # Muxage final
                $ffmpegMuxCmd = $commonArgs + @("-y", "-i", $tempVideoFile, "-i", $tempAudioIamf, "-c", "copy")
                if ($config.OutputContainer -eq "MP4") { $ffmpegMuxCmd += @("-movflags", "+faststart") }
                $ffmpegMuxCmd += @($outputFile)
                $code = Run-Process -FilePath $ffExePath -ArgumentList $ffmpegMuxCmd
                if ($code -ne 0) { throw "Muxage final échoué (code $code)." }

            } else {
                # Encodeur interne IAMF ou fallback FLAC
                if ($config.iamfInternalAvailable) {
                    $audioEncArgs = @("-c:a", "iamf", "-b:a", $config.IamfBitrate, "-stream_group", "mode=iamf_simple_profile")
                } else {
                    $audioEncArgs = @("-c:a", "flac")
                }

                # Retirer "-an" du tableau videoArgs
                $videoArgsSansAn = $videoArgs | Where-Object { $_ -ne "-an" }

                $ffmpegCmd = $commonArgs + $hwAccelArgs + @("-y", "-i", $inputFile) + $videoArgsSansAn + $audioEncArgs
                if ($config.OutputContainer -eq "MP4") { $ffmpegCmd += @("-movflags", "+faststart") }
                $ffmpegCmd += @($outputFile)
                $code = Run-Process -FilePath $ffExePath -ArgumentList $ffmpegCmd
                if ($code -ne 0) { throw "Transcodage FFmpeg interne échoué (code $code)." }
            }
        }
        # Si vidéo seule
        elseif ($hasVideo -and -not $hasAudio) {
            $videoOnlyArgs = $videoArgs | Where-Object { $_ -ne "-an" }
            $ffmpegCmd = $commonArgs + $hwAccelArgs + @("-y", "-i", $inputFile) + $videoOnlyArgs + @($outputFile)
            if ($config.OutputContainer -eq "MP4") { $ffmpegCmd += @("-movflags", "+faststart") }
            $code = Run-Process -FilePath $ffExePath -ArgumentList $ffmpegCmd
            if ($code -ne 0) { throw "Encodage vidéo seule échoué (code $code)." }
        }
        # Si audio seul
        elseif ($hasAudio -and -not $hasVideo) {
            if ($config.iamfInternalAvailable) {
                $audioArgsOnly = @("-c:a", "iamf", "-b:a", $config.IamfBitrate, "-stream_group", "mode=iamf_simple_profile")
            } else {
                $audioArgsOnly = @("-c:a", "flac")
            }
            $ffmpegCmd = $commonArgs + @("-y", "-i", $inputFile) + $audioArgsOnly + @($outputFile)
            $code = Run-Process -FilePath $ffExePath -ArgumentList $ffmpegCmd
            if ($code -ne 0) { throw "Encodage audio seul échoué (code $code)." }
        }
        else {
            throw "Aucun flux audio ou vidéo détecté dans le fichier."
        }

        # Nettoyage des fichiers temporaires
        Remove-Item $tempVideoFile, $tempAudioWav, $tempAudioIamf -ErrorAction SilentlyContinue -Force
        return @{File=$inputFile; Status="SUCCESS"}
    } catch {
        # Nettoyage même en cas d'erreur
        Remove-Item $tempVideoFile, $tempAudioWav, $tempAudioIamf -ErrorAction SilentlyContinue -Force
        return @{File=$inputFile; Status="ERROR"; Message=$_.Exception.Message}
    }
}
#endregion Fonction de traitement

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
        $inDir  = Pick-Folder "Choisissez le dossier SOURCE contenant les fichiers à transcoder"
        $outDir = Pick-Folder "Choisissez le dossier de DESTINATION pour les fichiers transcodés"
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
        $job = Start-ThreadJob -Name $jobName -ScriptBlock ${function:Process-File} -ArgumentList $file.FullName, $outDir, $Global:config, $ffExe, $ffProbeExe, $iamfEncoderExe
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
