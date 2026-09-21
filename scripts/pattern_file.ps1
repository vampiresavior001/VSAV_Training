# Opens a native Windows file dialog and does the copy itself, for the Action
# Pattern Library's Export and Import.
#
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File pattern_file.ps1 save stage.json
#
# -STA is REQUIRED. Windows Forms dialogs need a single-threaded apartment, and
# PowerShell 5.1 is STA when interactive but NOT when launched with -File from
# another process; without it ShowDialog() throws.
#
# WHY THIS COPIES THE FILE INSTEAD OF RETURNING A PATH.
#
# Lua 5.1 on Windows opens files through the ANSI API, so io.open cannot open a
# UTF-8 path at all - measured 2026-09-16: the same path as UTF-8 returned nil
# and as cp932 opened fine, and cp932 cannot spell every path Windows allows.
# So Lua never touches the chosen path. It stages the bytes at an ASCII path of
# its own and this script copies to or from the chosen file.
#
# THE EMULATOR IS FROZEN THE WHOLE TIME THIS IS OPEN - measured 6.6s to 39s on
# the probe. The Lua side puts a notice on screen one frame before calling.
#
# Output is fenced by markers, not line numbers: Lua runs this with 2>&1, so
# the banner and anything on stderr arrive on the same stream and neither of
# them is between the two markers.
#
#   VSAV_PATTERN_BEGIN
#   OK | CANCELLED | ERROR: <message>
#   <bytes copied>
#   <the folder of the chosen file, empty for CANCELLED / ERROR>
#   VSAV_PATTERN_END

param(
  [Parameter(Mandatory = $true)][ValidateSet('save', 'open')][string]$Mode,
  [Parameter(Mandatory = $true)][string]$Payload,
  # The character the library belongs to, so the suggested file name says whose
  # patterns these are. A library is per character and a folder full of files
  # all called the same thing is a folder nobody can use.
  [string]$Who = '',
  # The whole suggested file name, ready to use. The single-pattern export
  # passes one that carries the pattern's own name, because a folder of
  # one-pattern files all called the same thing is the same dead end. Empty
  # means "build it from $Who as before".
  [string]$Suggest = '',
  # Where the dialog opens. Lua saves the folder the player last accepted a
  # file in and hands it back here; a fresh process forgets everything on its
  # own (RestoreDirectory would remember inside this process only, and the
  # process lives for exactly one dialog). Invalid or empty falls back to the
  # process location, which is what the tool did before this existed.
  [string]$RememberDir = ''
)

$ErrorActionPreference = 'Stop'
$status = 'ERROR: never ran'
$size = 0
$dir = ''

try {
  Add-Type -AssemblyName System.Windows.Forms

  # An invisible top-most window to own the dialog. Without an owner it can
  # open BEHIND a full-screen emulator, which looks exactly like a freeze -
  # the process is waiting on a click nobody can see.
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
    if ($Suggest -ne '') {
      $d.FileName = $Suggest
    } elseif ($Who -ne '') {
      $d.FileName = 'vsav_action_patterns(' + $Who + ').json'
    } else {
      $d.FileName = 'vsav_action_patterns.json'
    }
    $d.OverwritePrompt = $true
  } else {
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.CheckFileExists = $true
  }

  $d.Title = 'VSAV Training - Action Patterns - ' + $Mode
  $d.Filter = 'Action Patterns (*.json)|*.json|All files (*.*)|*.*'
  # Last folder the player accepted, not the process location. A directory
  # that has since been deleted makes ShowDialog fall back on its own, so no
  # existence test is needed here.
  if ($RememberDir -ne '') {
    $d.InitialDirectory = $RememberDir
  } else {
    $d.InitialDirectory = (Get-Location).Path
  }

  $result = $d.ShowDialog($owner)
  $owner.Close()

  if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    # A real answer, not a failure. The caller has to tell "the player said no"
    # apart from "PowerShell never ran", and both look the same otherwise.
    $status = 'CANCELLED'
  } else {
    # -LiteralPath throughout: a chosen name may contain [ ] which PowerShell
    # would otherwise read as a wildcard and fail to find.
    if ($Mode -eq 'save') {
      Copy-Item -LiteralPath $Payload -Destination $d.FileName -Force
      $size = (Get-Item -LiteralPath $d.FileName).Length
    } else {
      Copy-Item -LiteralPath $d.FileName -Destination $Payload -Force
      $size = (Get-Item -LiteralPath $Payload).Length
    }
    $status = 'OK'
    $dir = Split-Path -Parent $d.FileName
  }
} catch {
  $status = 'ERROR: ' + $_.Exception.Message
}

Write-Output 'VSAV_PATTERN_BEGIN'
Write-Output $status
Write-Output $size
Write-Output $dir
Write-Output 'VSAV_PATTERN_END'
