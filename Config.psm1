# Config.psm1 - Configuration settings for ov.ps1 - URLs corrigées

# Chemins et URLs (moved from ov.ps1)
$Global:ffUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
$Global:ffLocal = Join-Path $PSScriptRoot "ffmpeg.zip"
$Global:ffDir = Join-Path $PSScriptRoot "ffmpeg"
$Global:ffExe = Join-Path (Join-Path $Global:ffDir "bin") "ffmpeg.exe"
$Global:ffProbeExe = Join-Path (Join-Path $Global:ffDir "bin") "ffprobe.exe"

# URL corrigée pour IAMF tools
$Global:iamfToolsUrl = "https://github.com/AOMediaCodec/iamf-tools/releases/download/v1.0.0/iamf-tools-v1.0.0-windows-x64.zip"
$Global:iamfToolsZip = Join-Path $PSScriptRoot "iamf-tools.zip"
$Global:iamfToolsDir = Join-Path $PSScriptRoot "iamf-tools"
$Global:iamfEncoderExe = Join-Path $Global:iamfToolsDir "iamf_encoder.exe" # Nom correct du fichier

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
    iamfInternalAvailable = $false # Will be set by Setup.psm1 based on FFmpeg capabilities
    InitialInputDir     = ""      # Will store last selected input directory
    InitialOutputDir    = ""      # Will store last selected output directory
}

# Export paths as global variables so they can be accessed by other modules
Export-ModuleMember -Variable ffUrl, ffLocal, ffDir, ffExe, ffProbeExe, iamfToolsUrl, iamfToolsZip, iamfToolsDir, iamfEncoderExe
Export-ModuleMember -Variable config