#Requires -Version 5.1
<#
.SYNOPSIS
    Emacs daemon manager with system tray icon.
.DESCRIPTION
    Starts an Emacs daemon (named server "org-seq"), displays a system tray
    icon with status, and provides a right-click menu to open new frames,
    check status, restart, stop, or toggle auto-start on Windows logon.

    Double-click the tray icon to open a new emacsclient frame.
.NOTES
    Designed for the org-seq Emacs PKM configuration on Windows.
    Requires Emacs 30+ (official GNU build).
    No admin rights needed.
.EXAMPLE
    # Run directly:
    powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File emacs-server-tray.ps1

    # Or create a startup shortcut via the tray menu -> "Auto-start".
#>

# ── Configuration ──

$ServerName = "org-seq"
$MutexName  = "Global\org-seq-emacs-tray"
$HealthCheckIntervalMs = 5000
$ShutdownTimeoutMs     = 5000

# ── Assemblies ──

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Single-instance guard ──

$script:Mutex = $null
try {
    $script:Mutex = [System.Threading.Mutex]::new($false, $MutexName)
    if (-not $script:Mutex.WaitOne(0, $false)) {
        # Another instance is already running.  Silently exit.
        $script:Mutex.Dispose()
        exit 0
    }
}
catch [System.Threading.AbandonedMutexException] {
    # Previous instance crashed — we now own the mutex.  Continue.
}

# ── Find Emacs executables ──

function Find-EmacsDir {
    # Check PATH first
    $cmd = Get-Command emacs.exe -ErrorAction SilentlyContinue
    if ($cmd) { return (Split-Path $cmd.Source) }

    # Scan Program Files for official GNU Emacs installs
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs")
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $candidates = Get-ChildItem "$root\Emacs" -Directory -ErrorAction SilentlyContinue |
                      Sort-Object Name -Descending
        foreach ($dir in $candidates) {
            $bin = Join-Path $dir.FullName "bin"
            if (Test-Path (Join-Path $bin "emacs.exe")) { return $bin }
        }
    }
    return $null
}

$script:EmacsBinDir = Find-EmacsDir
if (-not $script:EmacsBinDir) {
    [System.Windows.Forms.MessageBox]::Show(
        "Cannot find emacs.exe.`nAdd Emacs to PATH or install from https://ftp.gnu.org/gnu/emacs/windows/",
        "org-seq: Emacs not found",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
    if ($script:Mutex) { $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose() }
    exit 1
}

$script:EmacsExe      = Join-Path $script:EmacsBinDir "emacs.exe"
# Console client for silent background operations (health checks, eval, kill).
# MUST be the console variant — emacsclientw.exe pops GUI error dialogs on failure.
$script:ClientExe     = Join-Path $script:EmacsBinDir "emacsclient.exe"
# GUI client for opening visible frames (no flash of console window).
$script:ClientGuiExe  = Join-Path $script:EmacsBinDir "emacsclientw.exe"
if (-not (Test-Path $script:ClientGuiExe)) {
    $script:ClientGuiExe = $script:ClientExe
}
$script:ServerAuthFile = (Join-Path $HOME ".emacs.d/server/$ServerName").Replace('\', '/')

# ── State ──

$script:DaemonProcess = $null
$script:DaemonPid     = $null
$script:StartTime     = $null
$script:IsReady       = $false

# ── Icons ──

function Get-EmacsIcon {
    try {
        return [System.Drawing.Icon]::ExtractAssociatedIcon($script:EmacsExe)
    }
    catch {
        return [System.Drawing.SystemIcons]::Application
    }
}

function Get-StoppedIcon {
    # Use a built-in system icon for the stopped state.
    return [System.Drawing.SystemIcons]::Warning
}

$script:IconRunning = Get-EmacsIcon
$script:IconStopped = Get-StoppedIcon

# ── Daemon management ──

function Test-DaemonAlive {
    if ($null -eq $script:DaemonPid) { return $false }
    $proc = Get-Process -Id $script:DaemonPid -ErrorAction SilentlyContinue
    return ($null -ne $proc -and -not $proc.HasExited)
}

function Test-ServerReady {
    if (-not (Test-DaemonAlive)) { return $false }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName  = $script:ClientExe
        $psi.Arguments = "-f `"$script:ServerAuthFile`" -e t"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit(3000) | Out-Null
        if (-not $p.HasExited) { $p.Kill(); return $false }
        return ($p.ExitCode -eq 0)
    }
    catch { return $false }
}

function Start-EmacsDaemon {
    if (Test-DaemonAlive) { return }

    # Check if a server from a previous session is still running.
    # Try to adopt it by querying its PID.
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName  = $script:ClientExe
        $psi.Arguments = "-f `"$script:ServerAuthFile`" -e (emacs-pid)"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit(3000) | Out-Null
        if ($p.ExitCode -eq 0) {
            $pidStr = $p.StandardOutput.ReadToEnd().Trim()
            $adoptPid = [int]$pidStr
            $adoptProc = Get-Process -Id $adoptPid -ErrorAction SilentlyContinue
            if ($adoptProc -and -not $adoptProc.HasExited) {
                $script:DaemonPid     = $adoptPid
                $script:DaemonProcess = $adoptProc
                $script:StartTime     = $adoptProc.StartTime
                $script:IsReady       = $true
                Update-TrayState
                return
            }
        }
    }
    catch { }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName  = $script:EmacsExe
    $psi.Arguments = "--daemon=$ServerName"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    try {
        $script:DaemonProcess = [System.Diagnostics.Process]::Start($psi)
        $script:DaemonPid     = $script:DaemonProcess.Id
        $script:StartTime     = [datetime]::Now
        $script:IsReady       = $false
    }
    catch {
        $script:DaemonProcess = $null
        $script:DaemonPid     = $null
        $script:IsReady       = $false
    }
    Update-TrayState
}

function Stop-EmacsDaemon {
    if (-not (Test-DaemonAlive)) {
        $script:DaemonProcess = $null
        $script:DaemonPid     = $null
        $script:IsReady       = $false
        Update-TrayState
        return
    }

    # Graceful shutdown via elisp
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName  = $script:ClientExe
        $psi.Arguments = "-f `"$script:ServerAuthFile`" -e `"(kill-emacs)`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit($ShutdownTimeoutMs) | Out-Null
    }
    catch { }

    # Wait for exit, then force-kill if needed
    if (Test-DaemonAlive) {
        try { $script:DaemonProcess.WaitForExit(2000) | Out-Null } catch { }
        if (Test-DaemonAlive) {
            try { Stop-Process -Id $script:DaemonPid -Force -ErrorAction SilentlyContinue } catch { }
        }
    }

    $script:DaemonProcess = $null
    $script:DaemonPid     = $null
    $script:IsReady       = $false
    Update-TrayState
}

function Open-NewFrame {
    if (-not $script:IsReady) {
        $script:NotifyIcon.ShowBalloonTip(
            2000, "org-seq", "Server is not ready yet. Please wait...",
            [System.Windows.Forms.ToolTipIcon]::Warning)
        return
    }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName  = $script:ClientGuiExe
        $psi.Arguments = "-c -n -f `"$script:ServerAuthFile`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    }
    catch {
        $script:NotifyIcon.ShowBalloonTip(
            3000, "org-seq", "Failed to open frame: $_",
            [System.Windows.Forms.ToolTipIcon]::Error)
    }
}

# ── Tray UI ──

function Update-TrayState {
    $alive = Test-DaemonAlive
    if ($alive) {
        $script:NotifyIcon.Icon = $script:IconRunning
        if ($script:IsReady) {
            $script:NotifyIcon.Text = "org-seq: Emacs server running (PID $($script:DaemonPid))"
        }
        else {
            $script:NotifyIcon.Text = "org-seq: Emacs server starting..."
        }
    }
    else {
        $script:NotifyIcon.Icon = $script:IconStopped
        $script:NotifyIcon.Text = "org-seq: Emacs server stopped"
        $script:IsReady = $false
    }
}

function Show-StatusBalloon {
    $alive = Test-DaemonAlive
    if ($alive) {
        $uptime = [datetime]::Now - $script:StartTime
        $uptimeStr = "{0}h {1}m" -f [int]$uptime.TotalHours, $uptime.Minutes
        $msg = "Status: Running`nPID: $($script:DaemonPid)`nUptime: $uptimeStr`nServer: $ServerName"
        if (-not $script:IsReady) { $msg += "`n(still initializing...)" }
        $script:NotifyIcon.ShowBalloonTip(
            5000, "org-seq Emacs Server", $msg,
            [System.Windows.Forms.ToolTipIcon]::Info)
    }
    else {
        $script:NotifyIcon.ShowBalloonTip(
            3000, "org-seq Emacs Server", "Status: Stopped",
            [System.Windows.Forms.ToolTipIcon]::Warning)
    }
}

# ── Auto-start (shell:startup shortcut) ──

function Get-StartupShortcutPath {
    $startupDir = [System.Environment]::GetFolderPath("Startup")
    return Join-Path $startupDir "org-seq Emacs Server.lnk"
}

function Test-AutoStartEnabled {
    return (Test-Path (Get-StartupShortcutPath))
}

function Set-AutoStart {
    param([bool]$Enable)

    $lnkPath = Get-StartupShortcutPath
    if ($Enable) {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($lnkPath)
        $shortcut.TargetPath   = "powershell.exe"
        $scriptPath = $PSCommandPath
        $shortcut.Arguments    = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
        $shortcut.WorkingDirectory = Split-Path $scriptPath
        $shortcut.WindowStyle  = 7  # Minimized
        $shortcut.Description  = "org-seq Emacs daemon with system tray icon"
        # Use Emacs icon for the shortcut
        $shortcut.IconLocation = "$($script:EmacsExe),0"
        $shortcut.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
    }
    else {
        if (Test-Path $lnkPath) { Remove-Item $lnkPath -Force }
    }
}

# ── Build tray application ──

$script:AppContext = [System.Windows.Forms.ApplicationContext]::new()
$script:NotifyIcon = [System.Windows.Forms.NotifyIcon]::new()
$script:NotifyIcon.Icon    = $script:IconStopped
$script:NotifyIcon.Text    = "org-seq: starting..."
$script:NotifyIcon.Visible = $true

# Context menu
$menu = [System.Windows.Forms.ContextMenuStrip]::new()

$itemNewFrame = [System.Windows.Forms.ToolStripMenuItem]::new("New Frame")
$itemNewFrame.Font = [System.Drawing.Font]::new($itemNewFrame.Font, [System.Drawing.FontStyle]::Bold)
$itemNewFrame.Add_Click({ Open-NewFrame })
$menu.Items.Add($itemNewFrame) | Out-Null

$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

$itemStatus = [System.Windows.Forms.ToolStripMenuItem]::new("Server Status")
$itemStatus.Add_Click({ Show-StatusBalloon })
$menu.Items.Add($itemStatus) | Out-Null

$itemRestart = [System.Windows.Forms.ToolStripMenuItem]::new("Restart Server")
$itemRestart.Add_Click({
    Stop-EmacsDaemon
    Start-Sleep -Milliseconds 500
    Start-EmacsDaemon
})
$menu.Items.Add($itemRestart) | Out-Null

$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

$script:itemAutoStart = [System.Windows.Forms.ToolStripMenuItem]::new("Auto-start on login")
$script:itemAutoStart.Checked = Test-AutoStartEnabled
$script:itemAutoStart.Add_Click({
    $newState = -not (Test-AutoStartEnabled)
    Set-AutoStart -Enable $newState
    $script:itemAutoStart.Checked = $newState
    $verb = if ($newState) { "enabled" } else { "disabled" }
    $script:NotifyIcon.ShowBalloonTip(
        2000, "org-seq", "Auto-start $verb.",
        [System.Windows.Forms.ToolTipIcon]::Info)
})
$menu.Items.Add($script:itemAutoStart) | Out-Null

$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new()) | Out-Null

$itemQuit = [System.Windows.Forms.ToolStripMenuItem]::new("Stop Server && Quit")
$itemQuit.Add_Click({
    Stop-EmacsDaemon
    $script:AppContext.ExitThread()
})
$menu.Items.Add($itemQuit) | Out-Null

$script:NotifyIcon.ContextMenuStrip = $menu

# Double-click = New Frame
$script:NotifyIcon.Add_DoubleClick({ Open-NewFrame })

# Health check timer
$script:Timer = [System.Windows.Forms.Timer]::new()
$script:Timer.Interval = $HealthCheckIntervalMs
$script:Timer.Add_Tick({
    $alive = Test-DaemonAlive
    if ($alive -and -not $script:IsReady) {
        # Check if server is actually accepting connections now
        $script:IsReady = Test-ServerReady
    }
    elseif (-not $alive) {
        $script:IsReady = $false
    }
    Update-TrayState
})
$script:Timer.Start()

# ── Start daemon and run ──

Start-EmacsDaemon

try {
    [System.Windows.Forms.Application]::Run($script:AppContext)
}
finally {
    $script:Timer.Stop()
    $script:Timer.Dispose()
    $script:NotifyIcon.Visible = $false
    $script:NotifyIcon.Dispose()
    if ($script:Mutex) {
        try { $script:Mutex.ReleaseMutex() } catch { }
        $script:Mutex.Dispose()
    }
}
