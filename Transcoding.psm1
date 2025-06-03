# Transcoding.psm1 - Core file processing logic for ov.ps1

# Import utility functions (for Run-Process)
Import-Module .\Utils.psm1 -Force

#region Fonction de traitement d'un seul fichier
function Process-File {
    param(
        [string]$inputFile,
        [string]$outDir,
        [string]$inputRoot, # Added parameter to replace $Global:inputRoot
        [hashtable]$config,
        [string]$ffExePath,
        [string]$ffProbePath,
        [string]$iamfEncoderPath
    )
    try {
        # Check for critical global variables/config elements if needed (e.g. $config itself)
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
        # Use the $inputRoot parameter instead of $Global:inputRoot
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
        # Accessing $config which is passed as a parameter
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
                # Run-Process is imported from Utils.psm1
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

Export-ModuleMember -Function Process-File
