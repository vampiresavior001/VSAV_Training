# Shows a native Windows file dialog AND does the file copy itself.
#
# Kept as a FILE rather than built into the -Command string on the Lua side:
# the command would have to survive Lua quoting, then cmd.exe quoting, then
# PowerShell quoting, and a filter string is full of | and *. A file has none
# of that, and it can be run by hand to separate "the dialog is broken" from
# "the emulator cannot reach it".
#
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File dialog_probe.ps1 save out.txt payload.json
#
# -STA is REQUIRED. Windows Forms dialogs need a single-threaded apartment;
# PowerShell 5.1 is STA by default when interactive but NOT when launched with
# -Command or -File from another process, and without it ShowDialog() throws.
#
# WHY THIS COPIES THE FILE INSTEAD OF JUST RETURNING A PATH.
#
# Lua 5.1 on Windows opens files through the ANSI API, so io.open cannot open a
# UTF-8 path at all - measured, not assumed: the same path handed over as UTF-8
# returned nil and as cp932 opened fine. Handing back a path would therefore
# work only while it stayed ASCII, and would fail the moment anyone saved onto
# a Japanese desktop. Worse, cp932 cannot even spell every path Windows allows.
#
# So Lua never touches the chosen path. It stages the bytes at an ASCII path it
# picked itself, and this script copies to or from the chosen file. The path is
# still reported back, for display only.
#
# $Out is three lines, UTF-8 without a BOM:
#   1  OK | CANCELLED | ERROR: <message>
#   2  the chosen path, or empty
#   3  bytes copied, or 0

param(
  [Parameter(Mandatory = $true)][ValidateSet('save', 'open')][string]$Mode,
  [Parameter(Mandatory = $true)][string]$Out,
  [Parameter(Mandatory = $true)][string]$Payload
)

$ErrorActionPreference = 'Stop'
$status = 'ERROR: never ran'
$path = ''
$size = 0

try {
  Add-Type -AssemblyName System.Windows.Forms

  # An invisible top-most window to own the dialog. Without an owner the
  # dialog can open BEHIND a full-screen emulator, which looks exactly like
  # a freeze - the process is waiting on a click nobody can see.
  $owner = New-Object System.Windows.Forms.Form
  $owner.TopMost = $true
  $owner.ShowInTaskbar = $false
  $owner.Opacity = 0
  $owner.Width = 1
  $owner.Height = 1
  $owner.StartPosition = 'CenterScreen'
  $owner.Show()
  $owner.Activate()

  if ($Mode -eq 'save') {
    $d = New-Object System.Windows.Forms.SaveFileDialog
    $d.FileName = 'action_patterns.json'
    $d.OverwritePrompt = $true
  } else {
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.CheckFileExists = $true
  }

  $d.Title = 'VSAV Training - ' + $Mode
  $d.Filter = 'Action Patterns (*.json)|*.json|All files (*.*)|*.*'
  $d.InitialDirectory = (Get-Location).Path

  $result = $d.ShowDialog($owner)
  $owner.Close()

  if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    # Cancelled. A real answer, not a failure - the caller has to tell "the
    # user said no" apart from "PowerShell never ran", and both otherwise
    # look identical from Lua.
    $status = 'CANCELLED'
  } else {
    $path = $d.FileName
    # -LiteralPath throughout: a chosen name may contain [ ] which PowerShell
    # would otherwise read as a wildcard and fail to find.
    if ($Mode -eq 'save') {
      Copy-Item -LiteralPath $Payload -Destination $path -Force
      $size = (Get-Item -LiteralPath $path).Length
    } else {
      Copy-Item -LiteralPath $path -Destination $Payload -Force
      $size = (Get-Item -LiteralPath $Payload).Length
    }
    $status = 'OK'
  }
} catch {
  $status = 'ERROR: ' + $_.Exception.Message
}

# WriteAllText with an explicit UTF8Encoding($false) - Out-File -Encoding utf8
# on PowerShell 5.1 writes a BOM, and the Lua side would then read three stray
# bytes in front of the status word.
$body = $status + "`n" + $path + "`n" + $size
[System.IO.File]::WriteAllText($Out, $body, (New-Object System.Text.UTF8Encoding($false)))
Write-Output $body
