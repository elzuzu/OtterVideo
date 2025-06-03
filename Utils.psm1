# Utils.psm1 - Utility functions for ov.ps1

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
        # Ensure dependent commands are available or handled within the function
        if (Test-CommandExists "7z") {
            Start-Process -FilePath "7z" -ArgumentList "x", "`"$ArchivePath`"", "-o`"$DestinationPath`"", "-y" -Wait -NoNewWindow
        } else {
            # Consider if Download-File should be used here or if 7zr.exe is expected to be handled by the main script's Prepare-Tools
            # For now, keeping the original logic which includes downloading 7zr.exe if needed.
            # This creates a dependency from Utils.psm1 back to Download-File if it were not also in Utils.psm1
            # Since Download-File is part of this Utils module, this is fine.
            $zipExeUrl = "https://www.7-zip.org/a/7zr.exe"
            $zipExeLocal = Join-Path $env:TEMP "7zr.exe"
            if (-not (Test-Path $zipExeLocal)) {
                # Calling Download-File which is also in this module
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
    param(
        [string]$Message,
        [string]$InitialDirectory # Added to make it more generic, ov.ps1 can pass $InitialInputDir or $InitialOutputDir
    )
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Message
    if ($InitialDirectory -and (Test-Path $InitialDirectory)) { $dialog.SelectedPath = $InitialDirectory }

    # The original ov.ps1 had specific logic for $InitialInputDir and $InitialOutputDir.
    # This is a more generic version. The calling script ov.ps1 will need to pass the correct initial path.
    # For example: Pick-Folder "Select Source" $InitialInputDir

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
        [switch]$HideOutput,
        [hashtable]$GlobalConfig # Explicitly pass $Global:config if needed, or access it if available
    )
    # If Run-Process needs to access $Global:config.ShowFFmpegOutput,
    # it must be passed in or Utils.psm1 must also import Config.psm1 (which might be too coupled).
    # For now, let's assume $GlobalConfig will be passed if specific config values are needed.
    # The original Run-Process directly accessed $Global:config.ShowFFmpegOutput.
    # To maintain that, $Global:config would need to be accessible.
    # Since Config.psm1 exports $Global:config to the global scope, it *should* be accessible.
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow `
                                 -RedirectStandardError (Join-Path $env:TEMP "stderr_$([guid]::NewGuid()).txt")

        $stderrPath = (Get-ChildItem $env:TEMP | Where-Object { $_.Name -like 'stderr_*.txt' } | Sort-Object LastWriteTime | Select-Object -First 1).FullName
        $stderr = Get-Content $stderrPath -Raw -ErrorAction SilentlyContinue

        # Check if $Global:config is available and has ShowFFmpegOutput
        $showOutput = $false
        if ($Global:config -and $Global:config.ContainsKey('ShowFFmpegOutput')) {
            $showOutput = $Global:config.ShowFFmpegOutput
        }

        if (-not $HideOutput -or $showOutput) {
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

Export-ModuleMember -Function Test-CommandExists, Download-File, Extract-Archive, Pick-Folder, Validate-Integer, Validate-Bitrate, Run-Process
