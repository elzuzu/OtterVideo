# Transcoding.psm1 - Core file processing logic for ov.ps1

# Import utility functions (for Start-ExternalProcess)
Import-Module .\Utils.psm1 -Force

#region Fonction de traitement d'un seul fichier
function Invoke-FileProcessing {
    param(
        [string]$inputFile,
        [string]$outDir,
        [string]$inputRoot,
        [hashtable]$config,
        [string]$ffExePath,
        [string]$ffProbePath,
        [string]$iamfEncoderPath
    )
    try {
        if (-not $config) { Write-Error "Transcoding.psm1: \$config hashtable not provided."; throw }
        if (-not $inputRoot) { Write-Error "Transcoding.psm1: \$inputRoot not provided."; throw }

        # Recherche des flux avec ffprobe
        $probeJson = & "$ffProbePath" -v quiet -print_format json -show_streams $inputFile | ConvertFrom-Json
        $hasVideo = $probeJson.streams | Where-Object { $_.codec_type -eq "video" }
        $hasAudio = $probeJson.streams | Where-Object { $_.codec_type -eq "audio" }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($inputFile)
        $ext = if ($config.OutputContainer -eq "MP4") { ".mp4" } else { ".mkv" }
        $outputFileName = "${baseName}_vvc${ext}"

        # Gérer la structure de sous-dossiers
        $relativePath = [System.IO.Path]::GetDirectoryName($inputFile).Substring($inputRoot.Length)
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
                $processResult = Start-ExternalProcess -FilePath $ffExePath -ArgumentList $ffmpegVideoCmd
                if ($config.ShowFFmpegOutput) {
                    if ($processResult.StdOut) { $processResult.StdOut -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDOUT (Video): $_" } }
                    if ($processResult.StdErr) { $processResult.StdErr -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDERR (Video): $_" } }
                }
                if ($processResult.ExitCode -ne 0) {
                    $errMsg = "Encodage vidéo H.266/VVC échoué (code $($processResult.ExitCode))."
                    if (-not $config.ShowFFmpegOutput -and $processResult.StdErr) { $errMsg += " Stderr: $($processResult.StdErr | Out-String -Width 4096)" }
                    throw $errMsg
                }

                # Extraction audio
                $ffmpegAudioExtractCmd = $commonArgs + $hwAccelArgs + @("-y", "-i", $inputFile, "-vn", "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2", $tempAudioWav)
                $processResult = Start-ExternalProcess -FilePath $ffExePath -ArgumentList $ffmpegAudioExtractCmd
                if ($config.ShowFFmpegOutput) {
                    if ($processResult.StdOut) { $processResult.StdOut -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDOUT (AudioExtract): $_" } }
                    if ($processResult.StdErr) { $processResult.StdErr -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDERR (AudioExtract): $_" } }
                }
                if ($processResult.ExitCode -ne 0) {
                    $errMsg = "Extraction audio WAV échouée (code $($processResult.ExitCode))."
                    if (-not $config.ShowFFmpegOutput -and $processResult.StdErr) { $errMsg += " Stderr: $($processResult.StdErr | Out-String -Width 4096)" }
                    throw $errMsg
                }

                # Encodage IAMF externe
                $bitValue = [regex]::Match($config.IamfBitrate, '^(\d+)k$').Groups[1].Value + "000"
                $iamfArgs = @("-i", $tempAudioWav, "-o", $tempAudioIamf, "--mode", "0", "--bitrate", $bitValue)
                $processResult = Start-ExternalProcess -FilePath $iamfEncoderPath -ArgumentList $iamfArgs
                if ($config.ShowFFmpegOutput) {
                    if ($processResult.StdOut) { $processResult.StdOut -split "`r?`n" | ForEach-Object { Write-Host "IAMF_ENCODER_STDOUT: $_" } }
                    if ($processResult.StdErr) { $processResult.StdErr -split "`r?`n" | ForEach-Object { Write-Host "IAMF_ENCODER_STDERR: $_" } }
                }
                if ($processResult.ExitCode -ne 0) {
                    $errMsg = "Encodage IAMF externe échoué (code $($processResult.ExitCode))."
                    if (-not $config.ShowFFmpegOutput -and $processResult.StdErr) { $errMsg += " Stderr: $($processResult.StdErr | Out-String -Width 4096)" }
                    throw $errMsg
                }

                # Muxage final
                $ffmpegMuxCmd = $commonArgs + @("-y", "-i", $tempVideoFile, "-i", $tempAudioIamf, "-c", "copy")
                if ($config.OutputContainer -eq "MP4") { $ffmpegMuxCmd += @("-movflags", "+faststart") }
                $ffmpegMuxCmd += @($outputFile)
                $processResult = Start-ExternalProcess -FilePath $ffExePath -ArgumentList $ffmpegMuxCmd
                if ($config.ShowFFmpegOutput) {
                    if ($processResult.StdOut) { $processResult.StdOut -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDOUT (Mux): $_" } }
                    if ($processResult.StdErr) { $processResult.StdErr -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDERR (Mux): $_" } }
                }
                if ($processResult.ExitCode -ne 0) {
                    $errMsg = "Muxage final échoué (code $($processResult.ExitCode))."
                    if (-not $config.ShowFFmpegOutput -and $processResult.StdErr) { $errMsg += " Stderr: $($processResult.StdErr | Out-String -Width 4096)" }
                    throw $errMsg
                }

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
                $processResult = Start-ExternalProcess -FilePath $ffExePath -ArgumentList $ffmpegCmd
                if ($config.ShowFFmpegOutput) {
                    if ($processResult.StdOut) { $processResult.StdOut -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDOUT (Internal): $_" } }
                    if ($processResult.StdErr) { $processResult.StdErr -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDERR (Internal): $_" } }
                }
                if ($processResult.ExitCode -ne 0) {
                    $errMsg = "Transcodage FFmpeg interne échoué (code $($processResult.ExitCode))."
                    if (-not $config.ShowFFmpegOutput -and $processResult.StdErr) { $errMsg += " Stderr: $($processResult.StdErr | Out-String -Width 4096)" }
                    throw $errMsg
                }
            }
        }
        # Si vidéo seule
        elseif ($hasVideo -and -not $hasAudio) {
            $ffmpegCmd = $commonArgs + $hwAccelArgs + @("-y", "-i", $inputFile) + $videoArgs + @($outputFile)
            if ($config.OutputContainer -eq "MP4") { $ffmpegCmd += @("-movflags", "+faststart") }
            $processResult = Start-ExternalProcess -FilePath $ffExePath -ArgumentList $ffmpegCmd
            if ($config.ShowFFmpegOutput) {
                if ($processResult.StdOut) { $processResult.StdOut -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDOUT (VideoOnly): $_" } }
                if ($processResult.StdErr) { $processResult.StdErr -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDERR (VideoOnly): $_" } }
            }
            if ($processResult.ExitCode -ne 0) {
                $errMsg = "Encodage vidéo seule échoué (code $($processResult.ExitCode))."
                if (-not $config.ShowFFmpegOutput -and $processResult.StdErr) { $errMsg += " Stderr: $($processResult.StdErr | Out-String -Width 4096)" }
                throw $errMsg
            }
        }
        # Si audio seul
        elseif ($hasAudio -and -not $hasVideo) {
            if ($config.iamfInternalAvailable) {
                $audioArgsOnly = @("-c:a", "iamf", "-b:a", $config.IamfBitrate, "-stream_group", "mode=iamf_simple_profile")
            } else {
                $audioArgsOnly = @("-c:a", "flac")
            }
            $ffmpegCmd = $commonArgs + @("-y", "-i", $inputFile, "-vn") + $audioArgsOnly + @($outputFile)
            $processResult = Start-ExternalProcess -FilePath $ffExePath -ArgumentList $ffmpegCmd
            if ($config.ShowFFmpegOutput) {
                if ($processResult.StdOut) { $processResult.StdOut -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDOUT (AudioOnly): $_" } }
                if ($processResult.StdErr) { $processResult.StdErr -split "`r?`n" | ForEach-Object { Write-Host "FFMPEG_STDERR (AudioOnly): $_" } }
            }
            if ($processResult.ExitCode -ne 0) {
                $errMsg = "Encodage audio seul échoué (code $($processResult.ExitCode))."
                if (-not $config.ShowFFmpegOutput -and $processResult.StdErr) { $errMsg += " Stderr: $($processResult.StdErr | Out-String -Width 4096)" }
                throw $errMsg
            }
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

Export-ModuleMember -Function Invoke-FileProcessing