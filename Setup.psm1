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

    # Télécharger iamf-tools ? -> le projet ne fournit plus de binaires
    if ($Global:config.GrabIAMFTools) {
        Write-Warning "Les iamf-tools nécessitent une compilation depuis les sources."
        Write-Host "Consulter: https://github.com/AOMediaCodec/iamf-tools/blob/main/docs/build_instructions.md" -ForegroundColor Yellow
        Write-Host "L'option sera désactivée et l'encodeur FFmpeg interne sera utilisé." -ForegroundColor Yellow
        $Global:config.GrabIAMFTools = $false
        $Global:config.UseExternalIAMF = $false
    }

    # Vérifier l'encodeur IAMF interne si on ne compte pas utiliser l'externe
    if (-not $Global:config.UseExternalIAMF) {
        if (Test-Path $ffExe) {
            try {
                $encodersList = & "$ffExe" -hide_banner -encoders 2>$null | Out-String
                $iamfInternalOK = $encodersList -match "^\s*A.*\s+iamf\s" -or
                                  $encodersList -match "iamf" -or
                                  $encodersList -match "IAMF"

                Write-Host "=== Debug: Recherche encodeur IAMF ===" -ForegroundColor Cyan
                Write-Host "Pattern trouvé: $iamfInternalOK" -ForegroundColor Yellow

                if (-not $iamfInternalOK) {
                    Write-Host "Encodeurs audio disponibles dans FFmpeg:" -ForegroundColor Yellow
                    $audioEncoders = & "$ffExe" -hide_banner -encoders 2>$null | Select-String -Pattern "^\s*A" | Select-Object -First 5
                    $audioEncoders | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
                }
            } catch {
                Write-Warning "Erreur lors de la vérification des encodeurs FFmpeg: $($_.Exception.Message)"
                $iamfInternalOK = $false
            }
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
