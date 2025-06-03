ï»¿# UI.psm1 - Windows Forms UI for ov.ps1

# Import utilities (for Validate-Integer, Validate-Bitrate)
Import-Module .\Utils.psm1 -Force

#region Interface Utilisateur (Windows Forms)
function Show-MainApplicationWindow {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Ensure $Global:config is accessible. If this script module is imported by ov.ps1,
    # and ov.ps1 has already imported Config.psm1 which exports $Global:config,
    # then $Global:config should be available in the global scope.
    if (-not $Global:config) {
        Write-Error "UI.psm1: \$Global:config is not available. Ensure Config.psm1 is imported before UI.psm1 in the main script."
        return $false # Or throw an error
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Paramètres de Transcodage VVC/IAMF"
    $form.Size = New-Object System.Drawing.Size(500, 750) # Increased height
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "Sizable"
    $form.MaximizeBox = $true
    $form.MinimizeBox = $true

    # Initialize Job List for managing running transcode jobs
    $jobList = [System.Collections.Generic.List[System.Management.Automation.Job]]::new()

    $yPos = 10

    # Helper functions remain encapsulated within Show-SettingsForm
    function Add-Label($text, $y) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $text
        $label.Location = New-Object System.Drawing.Point(10, $y)
        $label.AutoSize = $true
        $form.Controls.Add($label)
        return $label
    }

    function Add-Checkbox($name, $text, $y, $checked, [scriptblock]$onCheckChanged = $null) {
        $checkbox = New-Object System.Windows.Forms.CheckBox
        $checkbox.Name = $name
        $checkbox.Text = $text
        $checkbox.Location = New-Object System.Drawing.Point(10, $y)
        $checkbox.AutoSize = $true
        $checkbox.Checked = $checked
        if ($onCheckChanged) { $checkbox.add_CheckedChanged($onCheckChanged) }
        $form.Controls.Add($checkbox)
        return $checkbox
    }

    function Add-Textbox($name, $y, $text, $width = 200) {
        $textbox = New-Object System.Windows.Forms.TextBox
        $textbox.Name = $name
        $textbox.Location = New-Object System.Drawing.Point(250, ([int]$y - 3))
        $textbox.Text = $text
        $textbox.Width = $width
        $form.Controls.Add($textbox)
        return $textbox
    }

    function Add-ComboBox($name, $y, $items, $selectedItem, $width = 200) {
        $combobox = New-Object System.Windows.Forms.ComboBox
        $combobox.Name = $name
        $combobox.Location = New-Object System.Drawing.Point(250, ([int]$y - 3))
        $combobox.Items.AddRange($items)
        $combobox.SelectedItem = $selectedItem
        $combobox.Width = $width
        $combobox.DropDownStyle = "DropDownList"
        $form.Controls.Add($combobox)
        return $combobox
    }

    # --- Contrôles du formulaire ---
    Add-Label "Options Générales:" $yPos; $yPos += 25

    # Accessing $Global:config for default values
    $cbUseAMD = Add-Checkbox "UseAMD" "Utiliser l'accélération AMD (décodage + redim. GPU)" $yPos $Global:config.UseAMD
    $yPos += 30

    $cbGrabIAMFTools = Add-Checkbox "GrabIAMFTools" "Télécharger iamf-tools" $yPos $Global:config.GrabIAMFTools
    $yPos += 30

    $cbUseExternalIAMF = Add-Checkbox "UseExternalIAMF" "Utiliser iamf-encoder.exe (nécessite iamf-tools)" $yPos $Global:config.UseExternalIAMF
    $cbUseExternalIAMF.Enabled = $Global:config.GrabIAMFTools # Initial state
    $cbGrabIAMFTools.add_CheckedChanged({
        $cbUseExternalIAMF.Enabled = $cbGrabIAMFTools.Checked
        if (-not $cbGrabIAMFTools.Checked) { $cbUseExternalIAMF.Checked = $false }
    })
    $yPos += 30

    Add-Label "Extensions d'entrée (séparées par virgule):" $yPos
    $tbInputExtensions = Add-Textbox "InputExtensions" $yPos ($Global:config.InputExtensions -join ',') 220
    $yPos += 30

    Add-Label "Conteneur de sortie:" $yPos
    $comboOutputContainer = Add-ComboBox "OutputContainer" $yPos @("MKV", "MP4") $Global:config.OutputContainer
    $yPos += 30

    Add-Label "Qualité VVC (QP, 0=lossless, 1-63 compressé):" $yPos
    $tbVvcQP = Add-Textbox "VvcQP" $yPos ($Global:config.VvcQP) 50
    $yPos += 30

    Add-Label "Débit audio IAMF (ex: 384k, 768k):" $yPos
    $tbIamfBitrate = Add-Textbox "IamfBitrate" $yPos ($Global:config.IamfBitrate) 100
    $yPos += 30

    Add-Label "Hauteur vidéo cible (entier, ex: 720, 1080):" $yPos
    $tbTargetVideoHeight = Add-Textbox "TargetVideoHeight" $yPos ($Global:config.TargetVideoHeight) 50
    $yPos += 30

    Add-Label "Nombre max de jobs parallèles (1-16):" $yPos
    $tbMaxParallelJobs = Add-Textbox "MaxParallelJobs" $yPos ($Global:config.MaxParallelJobs) 50
    $yPos += 30

    $cbShowFFmpegOutput = Add-Checkbox "ShowFFmpegOutput" "Afficher la sortie complète de FFmpeg" $yPos $Global:config.ShowFFmpegOutput
    $yPos += 40

    # --- Path Displays ---
    Add-Label "Input Directory:" $yPos
    $inputDirTextBox = New-Object System.Windows.Forms.TextBox
    $inputDirTextBox.Name = "inputDirTextBox"
    $inputDirTextBox.Location = New-Object System.Drawing.Point(150, ([int]$yPos - 3)) # Align with other textboxes
    $inputDirTextBox.Width = 320
    $inputDirTextBox.ReadOnly = $true
    $inputDirTextBox.Text = "Not selected"
    $form.Controls.Add($inputDirTextBox)
    $yPos += 30

    Add-Label "Output Directory:" $yPos
    $outputDirTextBox = New-Object System.Windows.Forms.TextBox
    $outputDirTextBox.Name = "outputDirTextBox"
    $outputDirTextBox.Location = New-Object System.Drawing.Point(150, ([int]$yPos - 3)) # Align with other textboxes
    $outputDirTextBox.Width = 320
    $outputDirTextBox.ReadOnly = $true
    $outputDirTextBox.Text = "Not selected"
    $form.Controls.Add($outputDirTextBox)
    $yPos += 30

    # Progress Bar
    $overallProgressBar = New-Object System.Windows.Forms.ProgressBar
    $overallProgressBar.Name = "overallProgressBar"
    $overallProgressBar.Location = New-Object System.Drawing.Point(10, $yPos)
    $overallProgressBar.Size = New-Object System.Drawing.Size(460, 20)
    $form.Controls.Add($overallProgressBar)
    $yPos += 30 # Increment Y position for the next control

    # Log TextBox
    $logTextBox = New-Object System.Windows.Forms.TextBox
    $logTextBox.Name = "logTextBox"
    $logTextBox.Location = New-Object System.Drawing.Point(10, $yPos)
    $logTextBox.Size = New-Object System.Drawing.Size(460, 150)
    $logTextBox.Multiline = $true
    $logTextBox.ScrollBars = "Vertical"
    $logTextBox.ReadOnly = $true
    $logTextBox.WordWrap = $false
    $form.Controls.Add($logTextBox)
    $yPos += 160 # Increment Y position for the next control (150 height + 10 spacing)

    # --- Action Buttons ---
    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Name = "startButton"
    $startButton.Text = "Start Transcoding"
    $startButton.Width = 120
    $startButton.Location = New-Object System.Drawing.Point(40, $yPos)
    # $startButton.DialogResult = "None" # Or remove this line
    $form.AcceptButton = $startButton
    $form.Controls.Add($startButton)

    $cancelProcessingButton = New-Object System.Windows.Forms.Button
    $cancelProcessingButton.Name = "cancelProcessingButton"
    $cancelProcessingButton.Text = "Cancel Processing"
    $cancelProcessingButton.Width = 120
    $cancelProcessingButton.Location = New-Object System.Drawing.Point(([int]$startButton.Right + 10), [int]$yPos)
    $cancelProcessingButton.Enabled = $false
    $form.Controls.Add($cancelProcessingButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Name = "closeButton"
    $closeButton.Text = "Close"
    $closeButton.Width = 90
    $closeButton.Location = New-Object System.Drawing.Point(([int]$cancelProcessingButton.Right + 10), [int]$yPos)
    $closeButton.DialogResult = "Cancel" # This will close the form if shown with ShowDialog()
    $form.CancelButton = $closeButton
    $form.Controls.Add($closeButton)

    $form.Height = $yPos + 70 # Adjusted form height; ensure this is enough for buttons

    # Helper function to re-enable settings controls
    $enableSettingsControls = {
        param($enable)
        $form.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] -and $_.Name -ne "logTextBox" } | ForEach-Object { $_.Enabled = $enable }
        $form.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] } | ForEach-Object { $_.Enabled = $enable }
        $form.Controls | Where-Object { $_ -is [System.Windows.Forms.ComboBox] } | ForEach-Object { $_.Enabled = $enable }
        # Specific handling for path textboxes if they had browse buttons, etc.
        $inputDirTextBox.Enabled = $enable # They are ReadOnly, but this affects visual cue
        $outputDirTextBox.Enabled = $enable
    }

    # Event Handler for Start Button
    $startButtonScriptBlock = {
        # Validation des champs numériques
        if (-not (Validate-Integer -Value $tbVvcQP.Text -FieldName "Qualité VVC (QP)" -Min 0 -Max 63)) {
            [System.Windows.Forms.MessageBox]::Show("La valeur pour 'Qualité VVC (QP)' doit être un entier entre 0 et 63.", "Validation Error", "OK", "Error")
            return
        }
        if (-not (Validate-Bitrate -Value $tbIamfBitrate.Text -FieldName "Débit audio IAMF")) {
            return # Validate-Bitrate shows its own MessageBox
        }
        if (-not (Validate-Integer -Value $tbTargetVideoHeight.Text -FieldName "Hauteur vidéo cible" -Min 1 -Max 4320)) {
            [System.Windows.Forms.MessageBox]::Show("La valeur pour 'Hauteur vidéo cible' doit être un entier entre 1 et 4320.", "Validation Error", "OK", "Error")
            return
        }
        if (-not (Validate-Integer -Value $tbMaxParallelJobs.Text -FieldName "Nombre max de jobs parallèles" -Min 1 -Max 16)) {
            [System.Windows.Forms.MessageBox]::Show("La valeur pour 'Nombre max de jobs parallèles' doit être un entier entre 1 et 16.", "Validation Error", "OK", "Error")
            return
        }

        # Update $Global:config
        $Global:config.UseAMD = $cbUseAMD.Checked
        $Global:config.GrabIAMFTools = $cbGrabIAMFTools.Checked
        $Global:config.UseExternalIAMF = $cbUseExternalIAMF.Checked
        $Global:config.InputExtensions = ($tbInputExtensions.Text -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $Global:config.OutputContainer = $comboOutputContainer.SelectedItem
        $Global:config.VvcQP = [int]$tbVvcQP.Text
        $Global:config.IamfBitrate = $tbIamfBitrate.Text
        $Global:config.TargetVideoHeight = [int]$tbTargetVideoHeight.Text
        $Global:config.MaxParallelJobs = [int]$tbMaxParallelJobs.Text
        $Global:config.ShowFFmpegOutput = $cbShowFFmpegOutput.Checked

        $logTextBox.AppendText("Configuration settings applied.`n")

        # Disable settings controls and Start button, enable Cancel button
        & $enableSettingsControls $false
        $startButton.Enabled = $false
        $cancelProcessingButton.Enabled = $true
        $logTextBox.Clear()

        try {
            $logTextBox.AppendText("Ensuring ThreadJob module is available...`n")
            Ensure-ThreadJob # Assumes this function is available (e.g., imported from Setup.psm1 or Main.ps1 if it was moved there)
            $logTextBox.AppendText("ThreadJob module ensured.`n")

            $logTextBox.AppendText("Preparing FFmpeg and IAMF tools...`n")
            # These paths should be set by Prepare-Tools, assuming global or script scope for $ffExe, $ffProbeExe, $iamfEncoderExe
            Prepare-Tools
            $logTextBox.AppendText("Tools prepared: FFmpeg at $($Global:ffExe), IAMF Encoder at $($Global:iamfEncoderExe)`n")

            $logTextBox.AppendText("Awaiting input folder selection...`n")
            # Use the $InitialInputDir parameter passed to Show-MainApplicationWindow, then current text, then global config
            $currentPickerInDir = $InitialInputDir
            if (-not ([string]::IsNullOrWhiteSpace($currentPickerInDir)) -and -not (Test-Path $currentPickerInDir)) {
                $logTextBox.AppendText("Provided InitialInputDir '$currentPickerInDir' is not valid, using default behavior.`n")
                $currentPickerInDir = $inputDirTextBox.Text # Fallback to textbox if parameter is bad
                if ($currentPickerInDir -eq "Not selected") {$currentPickerInDir = ""} # If textbox is also default, use empty for Pick-Folder default
            } elseif ([string]::IsNullOrWhiteSpace($currentPickerInDir)) { # If parameter was empty or only whitespace
                 $currentPickerInDir = if ($inputDirTextBox.Text -ne "Not selected") { $inputDirTextBox.Text } else { $Global:config.InitialInputDir }
            }
            $inDir = Pick-Folder -Message "Choisissez le dossier SOURCE contenant les fichiers à transcoder" -InitialDirectory $currentPickerInDir
            if (-not $inDir) {
                $logTextBox.AppendText("Input folder selection cancelled.`n")
                [System.Windows.Forms.MessageBox]::Show("La sélection du dossier d'entrée a été annulée.", "Opération Interrompue", "OK", "Warning")
                throw "Input folder selection cancelled." # Caught by outer catch
            }
            $inputDirTextBox.Text = $inDir
            $Global:config.InitialInputDir = $inDir # Save for next time
            $logTextBox.AppendText("Input folder: $inDir`n")

            $logTextBox.AppendText("Awaiting output folder selection...`n")
            # Use the $InitialOutputDir parameter, then current text, then global config
            $currentPickerOutDir = $InitialOutputDir
            if (-not ([string]::IsNullOrWhiteSpace($currentPickerOutDir)) -and -not (Test-Path $currentPickerOutDir)) {
                $logTextBox.AppendText("Provided InitialOutputDir '$currentPickerOutDir' is not valid, using default behavior.`n")
                $currentPickerOutDir = $outputDirTextBox.Text # Fallback to textbox if parameter is bad
                if ($currentPickerOutDir -eq "Not selected") {$currentPickerOutDir = ""}
            } elseif ([string]::IsNullOrWhiteSpace($currentPickerOutDir)) { # If parameter was empty or only whitespace
                $currentPickerOutDir = if ($outputDirTextBox.Text -ne "Not selected") { $outputDirTextBox.Text } else { $Global:config.InitialOutputDir }
            }
            $outDir = Pick-Folder -Message "Choisissez le dossier de DESTINATION pour les fichiers transcodés" -InitialDirectory $currentPickerOutDir
            if (-not $outDir) {
                $logTextBox.AppendText("Output folder selection cancelled.`n")
                [System.Windows.Forms.MessageBox]::Show("La sélection du dossier de sortie a été annulée.", "Opération Interrompue", "OK", "Warning")
                throw "Output folder selection cancelled." # Caught by outer catch
            }
            $outputDirTextBox.Text = $outDir
            $Global:config.InitialOutputDir = $outDir # Save for next time
            $logTextBox.AppendText("Output folder: $outDir`n")

            if ($inDir -eq $outDir) {
                $logTextBox.AppendText("Error: Input and output folders cannot be the same.`n")
                [System.Windows.Forms.MessageBox]::Show("Les dossiers source et destination ne peuvent pas être identiques.", "Erreur de Configuration", "OK", "Error")
                throw "Input and output folders are the same." # Caught by outer catch
            }
            if (-not (Test-Path $outDir)) {
                New-Item -ItemType Directory -Path $outDir -Force | Out-Null
                $logTextBox.AppendText("Created output directory: $outDir`n")
            }

            $logTextBox.AppendText("Discovering files to process...`n")
            $patterns = $Global:config.InputExtensions
            $filesToProcess = @()
            foreach ($patternItem in $patterns) { # Renamed $pattern to $patternItem to avoid conflict
                $filesToProcess += Get-ChildItem -Path (Join-Path $inDir "*") -Recurse -File -Include $patternItem
            }
            $filesToProcess = $filesToProcess | Sort-Object FullName | Select-Object -Unique

            if (-not $filesToProcess) {
                $logTextBox.AppendText("No files found matching extensions: $($Global:config.InputExtensions -join ', ') in $inDir`n")
                [System.Windows.Forms.MessageBox]::Show("Aucun fichier correspondant aux extensions $($Global:config.InputExtensions -join ', ') trouvé dans $inDir.", "Aucun Fichier", "OK", "Information")
                throw "No files found." # Caught by outer catch
            }
            $logTextBox.AppendText("Found $($filesToProcess.Count) files to process.`n")

            $overallProgressBar.Maximum = $filesToProcess.Count
            $overallProgressBar.Value = 0
            $Global:inputRoot = $inDir # Set for Process-File
            $jobList.Clear() # Clear any previous jobs if any

            if ($Global:config.ThreadJobAvailable) {
                $logTextBox.AppendText("Starting transcoding process using ThreadJob...`n")
                foreach ($file in $filesToProcess) {
                    while ($jobList.Count -ge $Global:config.MaxParallelJobs) {
                        $finishedJob = Wait-Job -Job $jobList -Any -Timeout 1 # Timeout 1s for responsiveness
                    if ($finishedJob) {
                        foreach ($j in $finishedJob) {
                            # Receive the job's primary output object and keep stream data
                            $jobOutputData = Receive-Job -Job $j -Keep -ErrorAction SilentlyContinue

                            # Log Information Stream (includes Write-Host from the job)
                            foreach ($infoRecord in $j.ChildJobs[0].Information.ReadAll()) {
                                $logTextBox.AppendText("INFO ($($j.Name)): $($infoRecord.Message)`n")
                            }
                            # Log Warning Stream
                            foreach ($warnRecord in $j.ChildJobs[0].Warning.ReadAll()) {
                                $logTextBox.AppendText("WARN ($($j.Name)): $($warnRecord.Message)`n")
                            }
                            # Log Verbose Stream (if used)
                            foreach ($verbRecord in $j.ChildJobs[0].Verbose.ReadAll()) {
                                $logTextBox.AppendText("VERBOSE ($($j.Name)): $($verbRecord.Message)`n")
                            }
                            # Log Error Stream
                            foreach ($errRecord in $j.ChildJobs[0].Error.ReadAll()) {
                                $logTextBox.AppendText("ERROR ($($j.Name) stream): $($errRecord.ToString())`n")
                            }

                            # Process $jobOutputData (which is the return value from Process-File)
                            if ($jobOutputData.Status -eq "SUCCESS") {
                                $logTextBox.AppendText("Job COMPLETED: $($j.Name) for file $($jobOutputData.File)`n")
                            } else {
                                $logTextBox.AppendText("Job FAILED: $($j.Name) for file $($jobOutputData.File): $($jobOutputData.Message)`n")
                            }

                            $overallProgressBar.PerformStep()
                            Remove-Job -Job $j
                            $jobList.Remove($j)
                        }
                    } # Check cancel button status here if needed during wait
                    if ($cancelProcessingButton.Enabled -eq $false) { # Check if cancel was pressed
                        throw "Processing cancelled by user during job wait."
                    }
                    [System.Windows.Forms.Application]::DoEvents() # Keep UI responsive
                }
                 if ($cancelProcessingButton.Enabled -eq $false) { # Check if cancel was pressed
                    throw "Processing cancelled by user before starting new job."
                }

                $jobName = "Transcode_$($file.BaseName)"
                $jobArguments = $file.FullName, $outDir, $Global:inputRoot, $Global:config, $Global:ffExe, $Global:ffProbeExe, $Global:iamfEncoderExe
                # Need to ensure Process-File is available. If it's in Transcoding.psm1, that module must be imported or use ScriptBlock from file.
                # For simplicity, assuming Process-File is made available globally or via an imported module.
                # If Transcoding.psm1 exports Process-File, it should be fine.
                $job = Start-ThreadJob -Name $jobName -ScriptBlock ${function:Process-File} -ArgumentList $jobArguments
                $jobList.Add($job)
                $logTextBox.AppendText("Job STARTED: $($job.Name)`n")
            }

            $logTextBox.AppendText("Waiting for all remaining jobs to complete...`n")
            while($jobList.Count -gt 0){
                $finishedJob = Wait-Job -Job $jobList -Any -Timeout 1
                if ($finishedJob) {
                    foreach ($j in $finishedJob) {
                        # Receive the job's primary output object and keep stream data
                        $jobOutputData = Receive-Job -Job $j -Keep -ErrorAction SilentlyContinue

                        # Log Information Stream
                        foreach ($infoRecord in $j.ChildJobs[0].Information.ReadAll()) {
                            $logTextBox.AppendText("INFO ($($j.Name)): $($infoRecord.Message)`n")
                        }
                        # Log Warning Stream
                        foreach ($warnRecord in $j.ChildJobs[0].Warning.ReadAll()) {
                            $logTextBox.AppendText("WARN ($($j.Name)): $($warnRecord.Message)`n")
                        }
                        # Log Verbose Stream
                        foreach ($verbRecord in $j.ChildJobs[0].Verbose.ReadAll()) {
                            $logTextBox.AppendText("VERBOSE ($($j.Name)): $($verbRecord.Message)`n")
                        }
                        # Log Error Stream
                        foreach ($errRecord in $j.ChildJobs[0].Error.ReadAll()) {
                            $logTextBox.AppendText("ERROR ($($j.Name) stream): $($errRecord.ToString())`n")
                        }

                        # Process $jobOutputData
                        if ($jobOutputData.Status -eq "SUCCESS") {
                            $logTextBox.AppendText("Job COMPLETED: $($j.Name) for file $($jobOutputData.File)`n")
                        } else {
                            $logTextBox.AppendText("Job FAILED: $($j.Name) for file $($jobOutputData.File): $($jobOutputData.Message)`n")
                        }

                        $overallProgressBar.PerformStep()
                        Remove-Job -Job $j
                        $jobList.Remove($j)
                    }
                }
                if ($cancelProcessingButton.Enabled -eq $false) { # Check if cancel was pressed
                    throw "Processing cancelled by user during final wait."
                }
                [System.Windows.Forms.Application]::DoEvents()
            }
            $logTextBox.AppendText("All transcoding jobs finished.`n")
            [System.Windows.Forms.MessageBox]::Show("Transcodage terminé pour tous les fichiers!", "Terminé", "OK", "Information")

            } else { # ThreadJob not available, run sequentially
                $logTextBox.AppendText("Starting transcoding process in single-thread mode (ThreadJob module not available)...`n")
                foreach ($file in $filesToProcess) {
                    if ($cancelProcessingButton.Enabled -eq $false) { # Check for cancellation
                        $logTextBox.AppendText("Cancellation requested. Stopping sequential processing.`n")
                        throw "Processing cancelled by user."
                    }

                    $logTextBox.AppendText("Processing file (sequentially): $($file.FullName)`n")

                    # Construct arguments for Process-File
                    $processFileArgs = @{
                        inputFile       = $file.FullName
                        outDir          = $outDir
                        inputRoot       = $Global:inputRoot
                        config          = $Global:config
                        ffExePath       = $Global:ffExe
                        ffProbePath     = $Global:ffProbeExe
                        iamfEncoderPath = $Global:iamfEncoderExe
                    }
                    $currentFileResult = $null
                    try {
                        $currentFileResult = Process-File @processFileArgs

                        if ($currentFileResult.Status -eq "SUCCESS") {
                            $logTextBox.AppendText("File COMPLETED (sequential): $($currentFileResult.File)`n")
                        } else {
                            $logTextBox.AppendText("File FAILED (sequential): $($currentFileResult.File): $($currentFileResult.Message)`n")
                        }
                    } catch {
                        $logTextBox.AppendText("File FAILED (sequential) with exception: $($file.FullName): $($_.Exception.Message)`n")
                    }

                    $overallProgressBar.PerformStep()
                    [System.Windows.Forms.Application]::DoEvents() # Keep UI responsive
                }
                $logTextBox.AppendText("All sequential processing finished.`n")
                [System.Windows.Forms.MessageBox]::Show("Transcodage séquentiel terminé pour tous les fichiers!", "Terminé (Séquentiel)", "OK", "Information")
            }

        } catch {
            $logTextBox.AppendText("Error during processing: $($_.Exception.Message)`n")
            if ($_.Exception.Message -notlike "*cancelled by user*") { # Avoid double message box for user cancel
                 [System.Windows.Forms.MessageBox]::Show("Une erreur est survenue: $($_.Exception.Message)", "Erreur de Traitement", "OK", "Error")
            }
        } finally {
            # Re-enable controls
            & $enableSettingsControls $true
            $startButton.Enabled = $true
            $cancelProcessingButton.Enabled = $false
            # Clean up job list if any jobs remain due to unhandled exception before loop completion
            foreach($job in $jobList){ Stop-Job $job; Remove-Job $job }
            $jobList.Clear()
            $overallProgressBar.Value = 0
        }
    }
    $startButton.add_Click($startButtonScriptBlock)

    # Event Handler for Cancel Processing Button
    $cancelProcessingButtonScriptBlock = {
        $logTextBox.AppendText("--- Processing CANCELLATION requested by user ---`n")
        $cancelProcessingButton.Enabled = $false # Prevent multiple clicks & signal cancellation

        $logTextBox.AppendText("Stopping all active jobs...`n")
        foreach ($jobEntry in $jobList) {
            try {
                Stop-Job -Job $jobEntry -PassThru | Out-Null # PassThru to ensure it waits for stop initiation
                $logTextBox.AppendText("Stop signal sent to job: $($jobEntry.Name)`n")
            } catch {
                $logTextBox.AppendText("Error trying to stop job $($jobEntry.Name): $($_.Exception.Message)`n")
            }
        }
        # Give jobs a moment to stop, then remove them
        Start-Sleep -Seconds 1
        foreach ($jobEntry in $jobList) {
            try {
                Remove-Job -Job $jobEntry -Force
                $logTextBox.AppendText("Removed job: $($jobEntry.Name)`n")
            } catch {
                 $logTextBox.AppendText("Error trying to remove job $($jobEntry.Name): $($_.Exception.Message)`n")
            }
        }
        $jobList.Clear()

        $logTextBox.AppendText("Processing cancelled.`n")
        [System.Windows.Forms.MessageBox]::Show("Le traitement a été annulé par l'utilisateur.", "Annulé", "OK", "Warning")

        # Re-enable settings and start button
        & $enableSettingsControls $true
        $startButton.Enabled = $true
        # cancelProcessingButton already disabled at start of this block
        $overallProgressBar.Value = 0 # Reset progress bar
    }
    $cancelProcessingButton.add_Click($cancelProcessingButtonScriptBlock)

    # Event Handler for Close Button
    $closeButton.add_Click({
        if ($jobList.Count -gt 0) {
            $confirmClose = [System.Windows.Forms.MessageBox]::Show("Des tâches sont en cours. Voulez-vous vraiment quitter et annuler les tâches en cours?", "Confirmation de Fermeture", "YesNo", "Warning")
            if ($confirmClose -eq "No") {
                return
            } else {
                # Attempt to cancel jobs before closing
                $cancelProcessingButton.PerformClick() # Trigger cancellation logic
            }
        }
        $form.Close()
    })

    $form.Show()

    # Keep the form responsive
    while ($form.Created -and $form.Visible) {
        Start-Sleep -Milliseconds 50
        [System.Windows.Forms.Application]::DoEvents()
    }
}
#endregion Interface Utilisateur

Export-ModuleMember -Function Show-MainApplicationWindow
