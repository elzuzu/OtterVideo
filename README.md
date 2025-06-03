# PowerShell Advanced Transcoder (VVC/IAMF)

## 1. Overview

This PowerShell script provides an advanced solution for batch transcoding video and audio files into modern formats, specifically focusing on H.266/VVC (Versatile Video Coding) for video and IAMF (Immersive Audio Model and Formats) for audio. It features a user-friendly graphical interface (GUI) for configuration, validation of inputs, and leverages multithreading for efficient processing.

The script is designed to automate the download and setup of necessary external tools like FFmpeg and IAMF tools.

## 2. Features

*   **User-Friendly GUI**: Configure all transcoding options through a Windows Forms interface.
*   **Batch Processing**: Process multiple files from an input directory, maintaining subdirectory structures in the output.
*   **VVC (H.266) Video Encoding**: Transcode video streams to VVC using FFmpeg with `libvvenc`.
    *   Configurable QP (Quantization Parameter) for quality control (0 for lossless).
    *   Adjustable target video height for resolution scaling.
*   **IAMF Audio Encoding**:
    *   Option to use an external `iamf-encoder.exe` (downloaded via the script).
    *   Option to use FFmpeg's internal IAMF encoder (if supported by the FFmpeg build).
    *   Fallback to FLAC encoding if IAMF is unavailable or not selected.
    *   Configurable bitrate for IAMF audio.
*   **Hardware Acceleration**: Supports AMD AMF for GPU-accelerated decoding and scaling (if available and selected).
*   **Dependency Management**:
    *   Automatically downloads and extracts the latest essential FFmpeg build from Gyan.dev.
    *   Optionally downloads and extracts the latest IAMF tools from the AOMediaCodec GitHub releases.
    *   Automatically installs the `ThreadJob` PowerShell module from PSGallery if not already present (for PowerShell 5.1 and 7+).
    *   Downloads `7zr.exe` (portable 7-Zip) if a system version of `7z.exe` is not found, for archive extraction.
*   **Flexible Input/Output**:
    *   Customizable input file extensions (e.g., *.mp4, *.mov, *.mkv, *.wav).
    *   Selectable output container (MKV or MP4).
*   **Parallel Processing**: Utilizes `ThreadJob` to transcode multiple files simultaneously, with configurable maximum parallel jobs.
    *   Graceful fallback to single-threaded mode if `ThreadJob` module cannot be installed/loaded.
*   **Robust Error Handling**:
    *   Detailed logging within the UI.
    *   Handles errors during tool download, setup, and transcoding.
    *   Cleans up temporary files.
*   **Stream Detection**: Uses `ffprobe` to detect existing audio/video streams and adapts processing accordingly (e.g., video-only, audio-only files).

## 3. Prerequisites

*   **Operating System**: Windows (due to Windows Forms UI and specific tool paths).
*   **PowerShell**:
    *   Windows PowerShell 5.1
    *   PowerShell 7+
    *   (The script attempts to install `ThreadJob` module which is compatible with these versions).
*   **.NET Framework/Core**: Required for PowerShell and Windows Forms. Usually comes pre-installed with Windows or with PowerShell 7.
*   **Internet Connection**: Required for the initial download of FFmpeg, IAMF tools, 7zr.exe (if needed), and the `ThreadJob` module.
*   **Execution Policy**: You may need to adjust your PowerShell execution policy to run scripts. For example:
    ```powershell
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```
*   **Administrative Rights**: May be required if `Install-Module` needs to write to system-wide directories, though the script specifies `-Scope CurrentUser` to minimize this need.

## 4. How to Run

1.  **Download/Clone**: Get all script files (`Main.ps1`, `Config.psm1`, `UI.psm1`, `Setup.psm1`, `Transcoding.psm1`, `Utils.psm1`) into a single directory.
2.  **Open PowerShell**: Navigate to the directory where you saved the files.
3.  **Run the Main Script**:
    ```powershell
    .\Main.ps1
    ```
    You can optionally provide initial input and output directories as parameters:
    ```powershell
    .\Main.ps1 -InitialInputDir "C:\path	o\your
ideos" -InitialOutputDir "D:\path
or	ranscoded
iles"
    ```
4.  **Use the GUI**: The "Paramètres de Transcodage VVC/IAMF" window will appear. Configure the options as needed.
5.  **Select Folders**: Click "Start Transcoding", then you will be prompted to select an input folder and an output folder.
6.  **Monitor Progress**: View progress and logs in the UI.

## 5. UI Options Explained

*   **Utiliser l'accélération AMD**: Check to use AMD AMF for GPU decoding and resizing (requires compatible AMD hardware and drivers).
*   **Télécharger iamf-tools**: Check to download `iamf-encoder.exe` and associated tools. Required for the "Utiliser iamf-encoder.exe" option.
*   **Utiliser iamf-encoder.exe**: Check to use the external `iamf-encoder.exe` for audio. If unchecked (or if `iamf-tools` are not grabbed/found), FFmpeg's internal IAMF encoder will be attempted, or FLAC as a fallback.
*   **Extensions d'entrée**: Comma-separated list of input file patterns (e.g., `*.mp4,*.mkv,*.wav`).
*   **Conteneur de sortie**: Choose between MKV and MP4 for the output files.
*   **Qualité VVC (QP)**: VVC Quantization Parameter. `0` is lossless. Higher values mean more compression but lower quality (e.g., 20-35). Range: 0-63.
*   **Débit audio IAMF**: Target bitrate for IAMF audio (e.g., `384k`, `768k`).
*   **Hauteur vidéo cible**: Target height in pixels for video scaling (e.g., `720`, `1080`). Width will be adjusted automatically to maintain aspect ratio.
*   **Nombre max de jobs parallèles**: Number of files to process simultaneously (1-16).
*   **Afficher la sortie complète de FFmpeg**: Check to show detailed FFmpeg console output in the log area. If unchecked, only errors and summary stats are shown.
*   **Input/Output Directory TextBoxes**: Display the selected input and output paths (read-only).
*   **Progress Bar**: Shows overall progress of the batch.
*   **Log TextBox**: Displays detailed logs, warnings, errors, and FFmpeg output.
*   **Buttons**:
    *   `Start Transcoding`: Begins the process after configuration and folder selection.
    *   `Cancel Processing`: Stops the current transcoding batch.
    *   `Close`: Closes the application.

## 6. External Tools Used

This script relies on the following external tools, which it attempts to manage automatically:

*   **FFmpeg**: For core transcoding capabilities (video/audio encoding, decoding, muxing, scaling). Downloaded from [Gyan.dev](https://www.gyan.dev/ffmpeg/builds/).
*   **ffprobe**: Part of FFmpeg, used for stream analysis.
*   **IAMF Tools**: Specifically `iamf-encoder.exe` for encoding IAMF audio when the external option is selected. Downloaded from [AOMediaCodec GitHub releases](https://github.com/AOMediaCodec/iamf/releases).
*   **7-Zip (7zr.exe)**: Portable command-line version of 7-Zip, downloaded if needed for extracting archives (`.zip`, `.7z`). Downloaded from [7-zip.org](https://www.7-zip.org).

## 7. Troubleshooting

*   **Script Execution Issues**: Ensure your PowerShell execution policy allows running local scripts.
*   **Tool Download Failures**: Check your internet connection. Some corporate networks might block downloads from GitHub or other sources; try downloading manually and placing them in the expected subfolders (`ffmpeg`, `iamf-tools`) if the script fails.
*   **`ThreadJob` Module Installation Fails**: If `Install-Module -Scope CurrentUser` fails, you might lack necessary permissions or PSGallery might be inaccessible. The script will attempt to run in a slower, single-threaded mode if `ThreadJob` is completely unavailable.
*   **FFmpeg Errors**: If `ShowFFmpegOutput` is enabled, the log will show detailed FFmpeg errors, which can help diagnose issues with specific files or codecs.
*   **IAMF Encoding Issues**: IAMF is a newer format. Ensure the FFmpeg build (if using internal) or the IAMF tools version supports your desired configuration.

## 8. License

This script is provided as-is. Please ensure compliance with the licenses of all external tools (FFmpeg, IAMF tools, 7-Zip) when using this script. (No specific license is provided for the script itself in this version).
