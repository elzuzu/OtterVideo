# Setup.psm1 - Module and tool preparation for ov.ps1

# Import utility functions (for Get-RemoteFile, Expand-ArchiveFile)
Import-Module .\Utils.psm1 -Force

#region Préparation des modules externes
function Enable-ThreadJob {
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
            $Global:config.ThreadJobAvailable = $false
        }
    }
}
#endregion Préparation des modules externes

#region Préparation des outils (FFmpeg, iamf-tools)
function Initialize-Tools {
    if (-not $Global:config) { Write-Error "Setup.psm1: \$Global:config not found."; throw }
    if (-not $ffUrl) { Write-Error "Setup.psm1: \$ffUrl not found."; throw }

    # Télécharger et décompresser FFmpeg si nécessaire
    if (-not (Test-Path $ffExe)) {
        try {
            Get-RemoteFile -Url $ffUrl -OutFile $ffLocal -Description "FFmpeg"
            Expand-ArchiveFile -ArchivePath $ffLocal -DestinationPath $ffDir -Description "FFmpeg"
            Remove-Item $ffLocal -ErrorAction SilentlyContinue -Force

            if (-not (Test-Path $ffExe)) {
                $foundExe = Get-ChildItem -Path $ffDir -Recurse -Filter ffmpeg.exe | Select-Object -First 1
                if ($foundExe) {
                    $newBinDir = Split-Path $foundExe.FullName -Parent
                    $Global:ffDir = Split-Path $newBinDir -Parent
                    $Global:ffExe = $foundExe.FullName
                    $Global:ffProbeExe = Join-Path $newBinDir 'ffprobe.exe'
                    Write-Host "Chemin FFmpeg ajusté : $Global:ffExe" -ForegroundColor Yellow
                } else {
                    throw "ffmpeg.exe introuvable après extraction."
                }
            }
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
                Get-RemoteFile -Url $iamfToolsUrl -OutFile $iamfToolsZip -Description "iamf-tools"

                $tempExtractDir = Join-Path $env:TEMP "iamf_extract_temp"
                if (Test-Path $tempExtractDir) { Remove-Item -Recurse -Force $tempExtractDir }
                New-Item -ItemType Directory -Path $tempExtractDir -Force | Out-Null

                Expand-ArchiveFile -ArchivePath $iamfToolsZip -DestinationPath $tempExtractDir -Description "iamf-tools"

                $extractedFolder = Get-ChildItem -Path $tempExtractDir -Directory | Select-Object -First 1
                if ($extractedFolder) {
                    if (Test-Path $iamfToolsDir) { Remove-Item -Recurse -Force $iamfToolsDir -ErrorAction SilentlyContinue }
                    New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($iamfToolsDir)) -Force -ErrorAction SilentlyContinue | Out-Null
                    Move-Item -Path $extractedFolder.FullName -Destination $iamfToolsDir -Force
                    Write-Host "iamf-tools moved to $iamfToolsDir" -ForegroundColor Green
                } else {
                    throw "Could not find extracted folder in $tempExtractDir"
                }
                Remove-Item $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $iamfToolsZip -ErrorAction SilentlyContinue -Force

                if (-not (Test-Path $iamfEncoderExe)) { throw "iamf-encoder.exe non trouvé après extraction et déplacement vers $iamfToolsDir." }
                Write-Host "iamf-tools configuré : $iamfEncoderExe" -ForegroundColor Green
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
        } else { 
            $iamfInternalOK = $false 
        }
        if (-not $iamfInternalOK) {
            Write-Warning "L'encodeur IAMF interne de FFmpeg n'a pas été trouvé. L'audio sera encodé en FLAC à la place."
        }
        $Global:config.iamfInternalAvailable = $iamfInternalOK
    }
}
#endregion Préparation des outils

Export-ModuleMember -Function Enable-ThreadJob, Initialize-Tools
