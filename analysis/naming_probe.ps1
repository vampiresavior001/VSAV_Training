# A one-line text entry window, for naming an Action Pattern.
#
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File naming_probe.ps1 new out.txt ""
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File naming_probe.ps1 rename out.txt "old name"
#
# A hand-built Form rather than Microsoft.VisualBasic's InputBox: the InputBox
# cannot be made top-most, and a window that opens behind a full-screen
# emulator is indistinguishable from a hang. This one is owned, top-most, and
# pre-selects its text so renaming is one keystroke rather than a backspace
# marathon.
#
# -STA is REQUIRED, as for any Windows Forms dialog launched from -File.
#
# $Out is three lines, UTF-8 without a BOM:
#   1  OK | CANCELLED | ERROR: <message>
#   2  the text typed, or empty
#   3  its length IN BYTES, which is not its length in characters once the
#      user types Japanese - the difference is the whole question downstream

param(
  [Parameter(Mandatory = $true)][ValidateSet('new', 'rename')][string]$Mode,
  [Parameter(Mandatory = $true)][string]$Out,
  [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Initial
)

$ErrorActionPreference = 'Stop'
$status = 'ERROR: never ran'
$text = ''

try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $form = New-Object System.Windows.Forms.Form
  $form.Text = if ($Mode -eq 'rename') { 'Rename Action Pattern' } else { 'Name Action Pattern' }
  $form.FormBorderStyle = 'FixedDialog'
  $form.StartPosition = 'CenterScreen'
  $form.TopMost = $true
  $form.MinimizeBox = $false
  $form.MaximizeBox = $false
  $form.ClientSize = New-Object System.Drawing.Size(380, 110)

  $label = New-Object System.Windows.Forms.Label
  $label.Text = 'Pattern name:'
  $label.SetBounds(12, 14, 356, 18)
  $form.Controls.Add($label)

  $box = New-Object System.Windows.Forms.TextBox
  $box.Text = $Initial
  $box.SetBounds(12, 36, 356, 24)
  $box.MaxLength = 64
  $form.Controls.Add($box)

  $ok = New-Object System.Windows.Forms.Button
  $ok.Text = 'OK'
  $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $ok.SetBounds(200, 72, 80, 26)
  $form.Controls.Add($ok)

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = 'Cancel'
  $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $cancel.SetBounds(288, 72, 80, 26)
  $form.Controls.Add($cancel)

  # Enter accepts, Escape cancels. Without these the only way out is the mouse,
  # and the point of the window is that the keyboard is faster.
  $form.AcceptButton = $ok
  $form.CancelButton = $cancel

  $form.Add_Shown({
    $form.Activate()
    $box.Focus()
    $box.SelectAll()
  })

  $result = $form.ShowDialog()
  if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $text = $box.Text
    $status = 'OK'
  } else {
    $status = 'CANCELLED'
  }
  $form.Dispose()
} catch {
  $status = 'ERROR: ' + $_.Exception.Message
}

$bytes = [System.Text.Encoding]::UTF8.GetByteCount($text)
$body = $status + "`n" + $text + "`n" + $bytes
[System.IO.File]::WriteAllText($Out, $body, (New-Object System.Text.UTF8Encoding($false)))
Write-Output $body
