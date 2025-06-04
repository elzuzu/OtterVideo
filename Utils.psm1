# Utils.psm1 - Utility functions for ov.ps1

#region Fonctions Utilitaires
function Test-Command {
    param($command)
    return [bool](Get-Command $command -ErrorAction SilentlyContinue)
}

function Get-RemoteFile {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description
    )
    Write-Host "Téléchargement de $Description..." -ForegroundColor Cyan
    try {
        if (Test-Command "curl") {
            $curlArgs = @("-L", "-o", $OutFile, $Url)
            $result = Start-ExternalProcess -FilePath "curl" -ArgumentList $curlArgs
            if ($result.ExitCode -ne 0) {
                throw "curl exit code $($result.ExitCode): $($result.StdErr)"
            }
        } else {
            Invoke-WebRequest $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
        }
        Write-Host "$Description téléchargé avec succès." -ForegroundColor Green
    } catch {
        Write-Error "Échec du téléchargement de $Description depuis $Url : $($_.Exception.Message)"
        throw "Téléchargement échoué."
    }
}

function Expand-ArchiveFile {
    param(
        [string]$ArchivePath,
        [string]$DestinationPath,
        [string]$Description
    )
    Write-Host "Extraction de $Description..." -ForegroundColor Cyan
    try {
        if (Test-Command "7z") {
            $args = @("x", $ArchivePath, "-o$DestinationPath", "-y")
            $result = Start-ExternalProcess -FilePath "7z" -ArgumentList $args
        } else {
            $zipExeUrl = "https://www.7-zip.org/a/7zr.exe"
            $zipExeLocal = Join-Path $env:TEMP "7zr.exe"
            if (-not (Test-Path $zipExeLocal)) {
                Get-RemoteFile -Url $zipExeUrl -OutFile $zipExeLocal -Description "7-Zip portable (7zr.exe)"
            }
            $args = @("x", $ArchivePath, "-o$DestinationPath", "-y")
            $result = Start-ExternalProcess -FilePath $zipExeLocal -ArgumentList $args
        }

        if ($result.ExitCode -ne 0) {
            throw "L'extraction a échoué avec le code $($result.ExitCode)."
        }
        Write-Host "$Description extrait avec succès." -ForegroundColor Green
    } catch {
        Write-Error "Échec de l'extraction de $Description : $($_.Exception.Message)"
        if (Test-Path $ArchivePath) { Remove-Item $ArchivePath -ErrorAction SilentlyContinue -Force }
        throw "Extraction échouée."
    }
}

function Get-Folder {
    param(
        [string]$Message,
        [string]$InitialDirectory
    )
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Message
    if ($InitialDirectory -and (Test-Path $InitialDirectory)) { 
        $dialog.SelectedPath = $InitialDirectory 
    }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    } else {
        return $null
    }
}

function Test-IntegerValue {
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

function Test-BitrateValue {
    param(
        [string]$Value,
        [string]$FieldName
    )
    if ($Value -notmatch '^[0-9]+k$') {
        [System.Windows.Forms.MessageBox]::Show("'$Value' n'est pas un débit valide (ex: 384k) pour $FieldName.", "Erreur", 'OK', 'Error')
        return $false
    }
    return $true
}

function Start-ExternalProcess {
    param(
        [string]$FilePath,
        [array]$ArgumentList
    )
    $stdoutLog = Join-Path $env:TEMP "stdout_$([guid]::NewGuid()).txt"
    $stderrLog = Join-Path $env:TEMP "stderr_$([guid]::NewGuid()).txt"

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow `
                                 -RedirectStandardOutput $stdoutLog `
                                 -RedirectStandardError $stderrLog

        $stdoutContent = Get-Content $stdoutLog -Raw -ErrorAction SilentlyContinue
        $stderrContent = Get-Content $stderrLog -Raw -ErrorAction SilentlyContinue

        Remove-Item $stdoutLog -ErrorAction SilentlyContinue -Force
        Remove-Item $stderrLog -ErrorAction SilentlyContinue -Force

        return @{
            ExitCode = $process.ExitCode
            StdOut   = $stdoutContent
            StdErr   = $stderrContent
        }
    } catch {
        if (Test-Path $stdoutLog) { Remove-Item $stdoutLog -ErrorAction SilentlyContinue -Force }
        if (Test-Path $stderrLog) { Remove-Item $stderrLog -ErrorAction SilentlyContinue -Force }

        Write-Error "Échec du lancement du processus $FilePath : $($_.Exception.Message)"
        return @{
            ExitCode = -1
            StdOut   = ""
            StdErr   = "Failed to start process ${FilePath}: $($_.Exception.Message)"
        }
    }
}
#endregion Fonctions Utilitaires

Export-ModuleMember -Function Test-Command, Get-RemoteFile, Expand-ArchiveFile, Get-Folder, Test-IntegerValue, Test-BitrateValue, Start-ExternalProcess
