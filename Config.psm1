ï»¿# Config.psm1 - Configuration settings for ov.ps1
# This file will hold parameters, paths, URLs, and default configuration values.

# Chemins et URLs (moved from ov.ps1)
$ffUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
$ffLocal = Join-Path $PSScriptRoot "ffmpeg.zip"
$ffDir = Join-Path $PSScriptRoot "ffmpeg"
$ffExe = Join-Path (Join-Path $ffDir "bin") "ffmpeg.exe"
$ffProbeExe = Join-Path (Join-Path $ffDir "bin") "ffprobe.exe"

$iamfToolsUrl = "https://github.com/AOMediaCodec/iamf/releases/latest/download/iamf-tools-windows-latest.zip" # Official URL for IAMF tools
$iamfToolsZip = Join-Path $PSScriptRoot "iamf-tools.zip"
$iamfToolsDir = Join-Path $PSScriptRoot "iamf-tools"
$iamfEncoderExe = Join-Path $iamfToolsDir "iamf-encoder.exe" # Path to the IAMF encoder executable

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
    ThreadJobAvailable  = $true # Will be set to false by Setup.psm1 if ThreadJob can't be loaded
}

# Export members
Export-ModuleMember -Variable * -Function *
# Specifically ensuring $Global:config is available.
# If $Global:config is intended to be modified from outside and changes reflected globally,
# this direct export might be sufficient for script modules, but for binary modules,
# getter/setter functions are often preferred. For .psm1, this should work.
Export-ModuleMember -Variable "Global:config"
