# UI.psm1 - Windows Forms UI for ov.ps1

# Import utilities (for Test-IntegerValue, Test-BitrateValue)
Import-Module .\Utils.psm1 -Force
Import-Module .\Setup.psm1 -Force
Import-Module .\Transcoding.psm1 -Force

#region Interface Utilisateur (Windows Forms)
function Show-MainApplicationWindow {
    param(
        [string]$InitialInputDir = "",
        [string]$InitialOutputDir = ""
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    if (-not $Global:config) {
        Write-Error "UI.psm1: \$Global:config is not available. Ensure Config.psm1 is imported before UI.psm1 in the main script."
        return $false
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Paramètres de Transcodage VVC/IAMF"
    $form.Size = New-Object System.Drawing.Size(520, 750)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "Sizable"
    $form.MaximizeBox = $true
    $form.MinimizeBox = $true

    # Initialize Job List for managing running transcode jobs
    $jobList = [System.Collections.Generic.List[System.Management.Automation.Job]]::new()

    $yPos = 10

    # Helper functions
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

    $cbUseAMD = Add-Checkbox "UseAMD" "Utiliser l'accélération AMD (décodage + redim. GPU)" $yPos $Global:config.UseAMD
    $yPos += 30

    $cbGrabIAMFTools = Add-Checkbox "GrabIAMFTools" "Télécharger iamf-tools" $yPos $Global:config.GrabIAMFTools
    $cbGrabIAMFTools.Visible = $false
    $yPos += 30

    $cbUseExternalIAMF = Add-Checkbox "UseExternalIAMF" "Utiliser iamf-encoder.exe (nécessite iamf-tools)" $yPos $Global:config.UseExternalIAMF
    $cbUseExternalIAMF.Enabled = $Global:config.GrabIAMFTools
    $cbUseExternalIAMF.Visible = $false
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

    # --- Path Selection avec boutons Browse ---
    Add-Label "Input Directory:" $yPos
    $inputDirTextBox = New-Object System.Windows.Forms.TextBox
    $inputDirTextBox.Name = "inputDirTextBox"
    $inputDirTextBox.Location = New-Object System.Drawing.Point(150, ([int]$yPos - 3))
    $inputDirTextBox.Width = 250
    $inputDirTextBox.ReadOnly = $true
    $inputDirTextBox.Text = if ($InitialInputDir) { $InitialInputDir } else { "Not selected" }
    $form.Controls.Add($inputDirTextBox)

    $inputBrowseButton = New-Object System.Windows.Forms.Button
    $inputBrowseButton.Text = "Browse..."
    $inputBrowseButton.Location = New-Object System.Drawing.Point(410, ([int]$yPos - 5))
    $inputBrowseButton.Size = New-Object System.Drawing.Size(75, 23)
    $inputBrowseButton.add_Click({
        $selectedPath = Get-Folder -Message "Choisissez le dossier SOURCE contenant les fichiers à transcoder" -InitialDirectory $inputDirTextBox.Text
        if ($selectedPath) {
            $inputDirTextBox.Text = $selectedPath
        }
    })
    $form.Controls.Add($inputBrowseButton)
    $yPos += 30

    Add-Label "Output Directory:" $yPos
    $outputDirTextBox = New-Object System.Windows.Forms.TextBox
    $outputDirTextBox.Name = "outputDirTextBox"
    $outputDirTextBox.Location = New-Object System.Drawing.Point(150, ([int]$yPos - 3))
    $outputDirTextBox.Width = 250
    $outputDirTextBox.ReadOnly = $true
    $outputDirTextBox.Text = if ($InitialOutputDir) { $InitialOutputDir } else { "Not selected" }
    $form.Controls.Add($outputDirTextBox)

    $outputBrowseButton = New-Object System.Windows.Forms.Button
    $outputBrowseButton.Text = "Browse..."
    $outputBrowseButton.Location = New-Object System.Drawing.Point(410, ([int]$yPos - 5))
    $outputBrowseButton.Size = New-Object System.Drawing.Size(75, 23)
    $outputBrowseButton.add_Click({
        $selectedPath = Get-Folder -Message "Choisissez le dossier de DESTINATION pour les fichiers transcodés" -InitialDirectory $outputDirTextBox.Text
        if ($selectedPath) {
            $outputDirTextBox.Text = $selectedPath
        }
    })
    $form.Controls.Add($outputBrowseButton)
    $yPos += 30

    # Progress Bar
    $overallProgressBar = New-Object System.Windows.Forms.ProgressBar
    $overallProgressBar.Name = "overallProgressBar"
    $overallProgressBar.Location = New-Object System.Drawing.Point(10, $yPos)
    $overallProgressBar.Size = New-Object System.Drawing.Size(480, 20)
    $form.Controls.Add($overallProgressBar)
    $yPos += 30

    # Log TextBox
    $logTextBox = New-Object System.Windows.Forms.TextBox
    $logTextBox.Name = "logTextBox"
    $logTextBox.Location = New-Object System.Drawing.Point(10, $yPos)
    $logTextBox.Size = New-Object System.Drawing.Size(480, 150)
    $logTextBox.Multiline = $true
    $logTextBox.ScrollBars = "Vertical"
    $logTextBox.ReadOnly = $true
    $logTextBox.WordWrap = $false
    $form.Controls.Add($logTextBox)
    $yPos += 160

    # --- Action Buttons ---
    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Name = "startButton"
    $startButton.Text = "Start Transcoding"
    $startButton.Width = 120
    $startButton.Location = New-Object System.Drawing.Point(40, $yPos)
    $form.AcceptButton = $startButton
    $form.Controls.Add($startButton)

    $cancelProcessingButton = New-Object System.Windows.Forms.Button
    $cancelProcessingButton.Name = "cancelProcessingButton"
    $cancelProcessingButton.Text = "Cancel Processing"
    $cancelProcessingButton.Width = 120
    $cancelProcessingButton.Location = New-Object System.Drawing.Point(170, [int]$yPos)
    $cancelProcessingButton.Enabled = $false
    $form.Controls.Add($cancelProcessingButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Name = "closeButton"
    $closeButton.Text = "Close"
    $closeButton.Width = 90
    $closeButton.Location = New-Object System.Drawing.Point(300, [int]$yPos)
    $closeButton.DialogResult = "Cancel"
    $form.CancelButton = $closeButton
    $form.Controls.Add($closeButton)

    $form.Height = $yPos + 70

    # Helper function to re-enable settings controls
    $enableSettingsControls = {
        param($enable)
        $form.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] -and $_.Name -ne "logTextBox" } | ForEach-Object { $_.Enabled = $enable }
        $form.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] } | ForEach-Object { $_.Enabled = $enable }
        $form.Controls | Where-Object { $_ -is [System.Windows.Forms.ComboBox] } | ForEach-Object { $_.Enabled = $enable }
        $inputBrowseButton.Enabled = $enable
        $outputBrowseButton.Enabled = $enable
    }

    # Event Handler for Start Button
    $startButtonScriptBlock = {
        # Validation des champs numériques
        if (-not (Test-IntegerValue -Value $tbVvcQP.Text -FieldName "Qualité VVC (QP)" -Min 0 -Max 63)) {
            return
        }
        if (-not (Test-BitrateValue -Value $tbIamfBitrate.Text -FieldName "Débit audio IAMF")) {
            return
        }
        if (-not (Test-IntegerValue -Value $tbTargetVideoHeight.Text -FieldName "Hauteur vidéo cible" -Min 1 -Max 4320)) {
            return
        }
        if (-not (Test-IntegerValue -Value $tbMaxParallelJobs.Text -FieldName "Nombre max de jobs parallèles" -Min 1 -Max 16)) {
            return
        }

        # Validation des dossiers
        $inDir = $inputDirTextBox.Text
        $outDir = $outputDirTextBox.Text
        
        if ($inDir -eq "Not selected" -or [string]::IsNullOrWhiteSpace($inDir) -or -not (Test-Path $inDir)) {
            [System.Windows.Forms.MessageBox]::Show("Veuillez sélectionner un dossier d'entrée valide.", "Erreur", "OK", "Error")
            return
        }
        if ($outDir -eq "Not selected" -or [string]::IsNullOrWhiteSpace($outDir)) {
            [System.Windows.Forms.MessageBox]::Show("Veuillez sélectionner un dossier de sortie valide.", "Erreur", "OK", "Error")
            return
        }
        if ($inDir -eq $outDir) {
            [System.Windows.Forms.MessageBox]::Show("Les dossiers source et destination ne peuvent pas être identiques.", "Erreur", "OK", "Error")
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
        $Global:config.InitialInputDir = $inDir
        $Global:config.InitialOutputDir = $outDir
        Save-UserConfig

        # Disable settings controls and Start button, enable Cancel button
        & $enableSettingsControls $false
        $startButton.Enabled = $false
        $cancelProcessingButton.Enabled = $true
        $logTextBox.Clear()

        try {
            $logTextBox.AppendText("Ensuring ThreadJob module is available...`n")
            Enable-ThreadJob
            $logTextBox.AppendText("ThreadJob module ensured.`n")

            $logTextBox.AppendText("Preparing FFmpeg and IAMF tools...`n")
            Initialize-Tools
            $logTextBox.AppendText("Tools prepared.`n")

            if (-not (Test-Path $outDir)) {
                New-Item -ItemType Directory -Path $outDir -Force | Out-Null
                $logTextBox.AppendText("Created output directory: $outDir`n")
            }

            $logTextBox.AppendText("Discovering files to process...`n")
            $patterns = $Global:config.InputExtensions
            $filesToProcess = @()
            foreach ($patternItem in $patterns) {
                $filesToProcess += Get-ChildItem -Path (Join-Path $inDir "*") -Recurse -File -Include $patternItem
            }
            $filesToProcess = $filesToProcess | Sort-Object FullName | Select-Object -Unique

            if (-not $filesToProcess) {
                $logTextBox.AppendText("No files found matching extensions: $($Global:config.InputExtensions -join ', ') in $inDir`n")
                [System.Windows.Forms.MessageBox]::Show("Aucun fichier correspondant aux extensions $($Global:config.InputExtensions -join ', ') trouvé dans $inDir.", "Aucun Fichier", "OK", "Information")
                throw "No files found."
            }
            $logTextBox.AppendText("Found $($filesToProcess.Count) files to process.`n")

            $overallProgressBar.Maximum = $filesToProcess.Count
            $overallProgressBar.Value = 0
            $Global:inputRoot = $inDir
            $jobList.Clear()

            if (-not $Global:config) {
                [System.Windows.Forms.MessageBox]::Show("Configuration globale non initialisée!", "Erreur", "OK", "Error")
                throw "Global configuration missing"
            }
            $criticalVars = @{
                'ffExe' = $ffExe
                'ffProbeExe' = $ffProbeExe
                'Global:inputRoot' = $Global:inputRoot
            }
            foreach ($varName in $criticalVars.Keys) {
                if (-not $criticalVars[$varName]) {
                    [System.Windows.Forms.MessageBox]::Show("Variable critique non définie: $varName", "Erreur", "OK", "Error")
                    throw "Critical variable missing: $varName"
                }
            }

            if ($Global:config.ThreadJobAvailable) {
                $logTextBox.AppendText("Starting transcoding process using ThreadJob...`n")
                foreach ($file in $filesToProcess) {
                    while ($jobList.Count -ge $Global:config.MaxParallelJobs) {
                        $finishedJob = Wait-Job -Job $jobList -Any -Timeout 1
                        if ($finishedJob) {
                            foreach ($j in $finishedJob) {
                                $jobOutputData = Receive-Job -Job $j -Keep -ErrorAction SilentlyContinue

                                foreach ($infoRecord in $j.ChildJobs[0].Information.ReadAll()) {
                                    $logTextBox.AppendText("INFO ($($j.Name)): $($infoRecord.Message)`n")
                                }
                                foreach ($warnRecord in $j.ChildJobs[0].Warning.ReadAll()) {
                                    $logTextBox.AppendText("WARN ($($j.Name)): $($warnRecord.Message)`n")
                                }
                                foreach ($errRecord in $j.ChildJobs[0].Error.ReadAll()) {
                                    $logTextBox.AppendText("ERROR ($($j.Name) stream): $($errRecord.ToString())`n")
                                }

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
                        if ($cancelProcessingButton.Enabled -eq $false) {
                            throw "Processing cancelled by user during job wait."
                        }
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                    if ($cancelProcessingButton.Enabled -eq $false) {
                        throw "Processing cancelled by user before starting new job."
                    }

                    $jobName = "Transcode_$($file.BaseName)"
                    $jobArguments = $file.FullName, $outDir, $Global:inputRoot, $Global:config, $ffExe, $ffProbeExe, $iamfEncoderExe
                    $job = Start-ThreadJob -Name $jobName -ScriptBlock ${function:Invoke-FileProcessing} -ArgumentList $jobArguments
                    $jobList.Add($job)
                    $logTextBox.AppendText("Job STARTED: $($job.Name)`n")
                }

                $logTextBox.AppendText("Waiting for all remaining jobs to complete...`n")
                while($jobList.Count -gt 0){
                    $finishedJob = Wait-Job -Job $jobList -Any -Timeout 1
                    if ($finishedJob) {
                        foreach ($j in $finishedJob) {
                            $jobOutputData = Receive-Job -Job $j -Keep -ErrorAction SilentlyContinue

                            foreach ($infoRecord in $j.ChildJobs[0].Information.ReadAll()) {
                                $logTextBox.AppendText("INFO ($($j.Name)): $($infoRecord.Message)`n")
                            }
                            foreach ($warnRecord in $j.ChildJobs[0].Warning.ReadAll()) {
                                $logTextBox.AppendText("WARN ($($j.Name)): $($warnRecord.Message)`n")
                            }
                            foreach ($errRecord in $j.ChildJobs[0].Error.ReadAll()) {
                                $logTextBox.AppendText("ERROR ($($j.Name) stream): $($errRecord.ToString())`n")
                            }

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
                    if ($cancelProcessingButton.Enabled -eq $false) {
                        throw "Processing cancelled by user during final wait."
                    }
                    [System.Windows.Forms.Application]::DoEvents()
                }
                $logTextBox.AppendText("All transcoding jobs finished.`n")
                [System.Windows.Forms.MessageBox]::Show("Transcodage terminé pour tous les fichiers!", "Terminé", "OK", "Information")

            } else {
                $logTextBox.AppendText("Starting transcoding process in single-thread mode (ThreadJob module not available)...`n")
                foreach ($file in $filesToProcess) {
                    if ($cancelProcessingButton.Enabled -eq $false) {
                        $logTextBox.AppendText("Cancellation requested. Stopping sequential processing.`n")
                        throw "Processing cancelled by user."
                    }

                    $logTextBox.AppendText("Processing file (sequentially): $($file.FullName)`n")

                    $processFileArgs = @{
                        inputFile       = $file.FullName
                        outDir          = $outDir
                        inputRoot       = $Global:inputRoot
                        config          = $Global:config
                        ffExePath       = $ffExe
                        ffProbePath     = $ffProbeExe
                        iamfEncoderPath = $iamfEncoderExe
                    }
                    $currentFileResult = $null
                    try {
                        $currentFileResult = Invoke-FileProcessing @processFileArgs

                        if ($currentFileResult.Status -eq "SUCCESS") {
                            $logTextBox.AppendText("File COMPLETED (sequential): $($currentFileResult.File)`n")
                        } else {
                            $logTextBox.AppendText("File FAILED (sequential): $($currentFileResult.File): $($currentFileResult.Message)`n")
                        }
                    } catch {
                        $logTextBox.AppendText("File FAILED (sequential) with exception: $($file.FullName): $($_.Exception.Message)`n")
                    }

                    $overallProgressBar.PerformStep()
                    [System.Windows.Forms.Application]::DoEvents()
                }
                $logTextBox.AppendText("All sequential processing finished.`n")
                [System.Windows.Forms.MessageBox]::Show("Transcodage séquentiel terminé pour tous les fichiers!", "Terminé (Séquentiel)", "OK", "Information")
            }

        } catch {
            $logTextBox.AppendText("Error during processing: $($_.Exception.Message)`n")
            if ($_.Exception.Message -notlike "*cancelled by user*") {
                [System.Windows.Forms.MessageBox]::Show("Une erreur est survenue: $($_.Exception.Message)", "Erreur de Traitement", "OK", "Error")
            }
        } finally {
            & $enableSettingsControls $true
            $startButton.Enabled = $true
            $cancelProcessingButton.Enabled = $false
            foreach($job in $jobList){ Stop-Job $job; Remove-Job $job }
            $jobList.Clear()
            $overallProgressBar.Value = 0
        }
    }
    $startButton.add_Click($startButtonScriptBlock)

    # Event Handler for Cancel Processing Button
    $cancelProcessingButtonScriptBlock = {
        $logTextBox.AppendText("--- Processing CANCELLATION requested by user ---`n")
        $cancelProcessingButton.Enabled = $false

        $logTextBox.AppendText("Stopping all active jobs...`n")
        foreach ($jobEntry in $jobList) {
            try {
                Stop-Job -Job $jobEntry -PassThru | Out-Null
                $logTextBox.AppendText("Stop signal sent to job: $($jobEntry.Name)`n")
            } catch {
                $logTextBox.AppendText("Error trying to stop job $($jobEntry.Name): $($_.Exception.Message)`n")
            }
        }
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

        & $enableSettingsControls $true
        $startButton.Enabled = $true
        $overallProgressBar.Value = 0
    }
    $cancelProcessingButton.add_Click($cancelProcessingButtonScriptBlock)

    # Event Handler for Close Button
    $closeButton.add_Click({
        if ($jobList.Count -gt 0) {
            $confirmClose = [System.Windows.Forms.MessageBox]::Show("Des tâches sont en cours. Voulez-vous vraiment quitter et annuler les tâches en cours?", "Confirmation de Fermeture", "YesNo", "Warning")
            if ($confirmClose -eq "No") {
                return
            } else {
                $cancelProcessingButton.PerformClick()
            }
        }
        $form.Close()
    })

    # Persist settings when the window is closed
    $form.add_FormClosing({
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
        if ($inputDirTextBox.Text -ne 'Not selected') { $Global:config.InitialInputDir = $inputDirTextBox.Text }
        if ($outputDirTextBox.Text -ne 'Not selected') { $Global:config.InitialOutputDir = $outputDirTextBox.Text }
        Save-UserConfig
    })

    $form.Show()

    while ($form.Created -and $form.Visible) {
        Start-Sleep -Milliseconds 50
        [System.Windows.Forms.Application]::DoEvents()
    }
}
#endregion Interface Utilisateur

Export-ModuleMember -Function Show-MainApplicationWindow
