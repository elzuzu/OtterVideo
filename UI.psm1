# UI.psm1 - Windows Forms UI for ov.ps1

# Import utilities (for Validate-Integer, Validate-Bitrate)
Import-Module .\Utils.psm1 -Force

#region Interface Utilisateur (Windows Forms)
function Show-SettingsForm {
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
    $form.Size = New-Object System.Drawing.Size(500, 600)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

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
        $textbox.Location = New-Object System.Drawing.Point(250, $y - 3)
        $textbox.Text = $text
        $textbox.Width = $width
        $form.Controls.Add($textbox)
        return $textbox
    }

    function Add-ComboBox($name, $y, $items, $selectedItem, $width = 200) {
        $combobox = New-Object System.Windows.Forms.ComboBox
        $combobox.Name = $name
        $combobox.Location = New-Object System.Drawing.Point(250, $y - 3)
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

    # Boutons OK et Annuler
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point(150, $yPos)
    $okButton.DialogResult = "OK"
    $form.AcceptButton = $okButton
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Annuler"
    $cancelButton.Location = New-Object System.Drawing.Point(260, $yPos)
    $cancelButton.DialogResult = "Cancel"
    $form.CancelButton = $cancelButton
    $form.Controls.Add($cancelButton)

    $form.Height = $yPos + 100
    $result = $form.ShowDialog()

    if ($result -eq "OK") {
        # Validation des champs numériques using functions from Utils.psm1
        if (-not (Validate-Integer -Value $tbVvcQP.Text -FieldName "Qualité VVC (QP)" -Min 0 -Max 63)) { return $false }
        if (-not (Validate-Bitrate -Value $tbIamfBitrate.Text -FieldName "Débit audio IAMF")) { return $false }
        if (-not (Validate-Integer -Value $tbTargetVideoHeight.Text -FieldName "Hauteur vidéo cible" -Min 1 -Max 4320)) { return $false }
        if (-not (Validate-Integer -Value $tbMaxParallelJobs.Text -FieldName "Nombre max de jobs parallèles" -Min 1 -Max 16)) { return $false }

        # Updating $Global:config with new values
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
        return $true
    } else {
        return $false # Annulé
    }
}
#endregion Interface Utilisateur

Export-ModuleMember -Function Show-SettingsForm
