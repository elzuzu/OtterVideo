# Config.psm1 - Configuration settings for ov.ps1 - URLs corrigées

# Chemins et URLs (moved from ov.ps1)
$Global:ffUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full.7z"
$Global:ffLocal = Join-Path $PSScriptRoot "ffmpeg.7z"
$Global:ffDir = Join-Path $PSScriptRoot "ffmpeg"
$Global:ffExe = Join-Path (Join-Path $Global:ffDir "bin") "ffmpeg.exe"
$Global:ffProbeExe = Join-Path (Join-Path $Global:ffDir "bin") "ffprobe.exe"

# URL des iamf-tools (aucun binaire officiel n'est fourni)
# On laisse l'URL vers la dernière release à titre indicatif mais
# l'option de téléchargement est désactivée par défaut.
$Global:iamfToolsUrl = "https://github.com/AOMediaCodec/iamf-tools/releases/latest/download/iamf-tools-windows-x64.zip"
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

# Configuration file stored in the user's profile
$Global:configFile = Join-Path $env:APPDATA "OtterVideo\config.json"

function Load-UserConfig {
    if (Test-Path $Global:configFile) {
        try {
            $json = Get-Content $Global:configFile -Raw | ConvertFrom-Json
            foreach ($key in $json.PSObject.Properties.Name) {
                $Global:config[$key] = $json.$key
            }
        } catch {
            Write-Warning "Failed to load user config from $($Global:configFile): $($_.Exception.Message)"
        }
    }
}

function Save-UserConfig {
    try {
        $dir = Split-Path $Global:configFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $Global:config | ConvertTo-Json -Depth 4 | Set-Content $Global:configFile
    } catch {
        Write-Warning "Failed to save user config to $($Global:configFile): $($_.Exception.Message)"
    }
}

# Load user configuration if available
Load-UserConfig

# Export paths as global variables so they can be accessed by other modules
Export-ModuleMember -Variable ffUrl, ffLocal, ffDir, ffExe, ffProbeExe, iamfToolsUrl, iamfToolsZip, iamfToolsDir, iamfEncoderExe
Export-ModuleMember -Variable config
Export-ModuleMember -Function Load-UserConfig, Save-UserConfig
