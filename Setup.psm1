# Setup.psm1 - Module and tool preparation for ov.ps1

# Import utility functions (for Download-File, Extract-Archive)
Import-Module .\Utils.psm1 -Force

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
            $Global:config.ThreadJobAvailable = $false
        }
    }
}
#endregion Préparation des modules externes

#region Préparation des outils (FFmpeg, iamf-tools)
function Prepare-Tools {
    # Accessing global variables set by Config.psm1 (e.g., $ffExe, $ffUrl, $Global:config)
    # $PSScriptRoot in this module will refer to the directory of Setup.psm1.
    # Assuming Setup.psm1, Config.psm1, and ov.ps1 are in the same directory,
    # paths derived from $PSScriptRoot (like for $iamfToolsDir) should be consistent.

    # Check for critical global variables
    if (-not $Global:config) { Write-Error "Setup.psm1: \$Global:config not found."; throw }
    if (-not $ffUrl) { Write-Error "Setup.psm1: \$ffUrl not found."; throw } # Example check

    # Télécharger et décompresser FFmpeg si nécessaire
    if (-not (Test-Path $ffExe)) {
        try {
            # Download-File and Extract-Archive are from Utils.psm1
            Download-File -Url $ffUrl -OutFile $ffLocal -Description "FFmpeg" # Description simplified
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
        # $iamfToolsDir is defined in Config.psm1 using Join-Path $PSScriptRoot "iamf-tools"
        # If Config.psm1's $PSScriptRoot is the same as this module's, it's fine.
        # $iamfEncoderExe is derived from $iamfToolsDir.
        if (-not (Test-Path $iamfEncoderExe)) {
            try {
                Download-File -Url $iamfToolsUrl -OutFile $iamfToolsZip -Description "iamf-tools"
                # Original logic for Extract-Archive for iamf-tools used $PSScriptRoot directly for DestinationPath
                # This should be $PSScriptRoot of this module (Setup.psm1) if we want to keep the extracted folder relative to the script files.
                # The definition of $iamfToolsDir in Config.psm1 is Join-Path $PSScriptRoot "iamf-tools" (Config.psm1's root)
                # So, we should extract to a path from which $iamfToolsDir can be resolved, or ensure $iamfToolsDir is correctly used.
                # The original Extract-Archive call in ov.ps1 used $PSScriptRoot.
                # This $PSScriptRoot will be the directory of Setup.psm1.
                # The $iamfToolsDir variable itself is defined in Config.psm1 as Join-Path $PSScriptRoot "iamf-tools".
                # For consistency, let's assume the extraction target for iamf-tools should lead to the path defined in $iamfToolsDir.
                # If $iamfToolsDir is "C:\scripts\iamf-tools", we should extract such that the exe is at $iamfToolsDir\iamf-encoder.exe.
                # The original code extracted to $PSScriptRoot and then renamed. This means it expected "iamf-tools-windows-x64" folder.

                # Let's simplify and assume extraction should create the $iamfToolsDir directly if possible,
                # or handle the subfolder within Extract-Archive or here.
                # The original logic was: Extract to $PSScriptRoot, then rename Get-ChildItem "iamf-tools*" to $iamfToolsDir.
                # This implies $iamfToolsDir is the target directory name.

                $tempExtractDir = Join-Path $env:TEMP "iamf_extract_temp"
                if (Test-Path $tempExtractDir) { Remove-Item -Recurse -Force $tempExtractDir }
                New-Item -ItemType Directory -Path $tempExtractDir -Force | Out-Null

                Extract-Archive -ArchivePath $iamfToolsZip -DestinationPath $tempExtractDir -Description "iamf-tools"

                # The IAMF tools archive might contain a versioned top-level directory.
                # This logic attempts to find that single directory within the temporary extraction path
                # and then move it to the target $iamfToolsDir.
                # Find the actual extracted folder (e.g., "iamf-tools-windows-x64")
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
                $Global:config.UseExternalIAMF = $false # Ensure this modification to Global:config is intentional and correct
            }
        } else {
            Write-Host "iamf-tools trouvé : $iamfEncoderExe" -ForegroundColor Green
        }
    }

    # Vérifier l'encodeur IAMF interne si on ne compte pas utiliser l'externe
    if (-not $Global:config.UseExternalIAMF) {
        if (Test-Path $ffExe) {
            # Ensure $ffExe is the correct path from Config.psm1
            $iamfInternalOK = & "$ffExe" -hide_banner -encoders | Select-String -Pattern " iamf\s" -Quiet
        } else { $iamfInternalOK = $false } # Should not happen if FFmpeg check passed
        if (-not $iamfInternalOK) {
            Write-Warning "L'encodeur IAMF interne de FFmpeg n'a pas été trouvé. L'audio sera encodé en FLAC à la place."
        }
        # Ensure this modification to Global:config is intentional
        $Global:config.iamfInternalAvailable = $iamfInternalOK
    }
}
#endregion Préparation des outils

Export-ModuleMember -Function Ensure-ThreadJob, Prepare-Tools
