$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms

# 注入 Windows 原生深色窗口标题栏 (DWM) 与独立任务栏 AppID
$dwmCode = @"
using System;
using System.Runtime.InteropServices;
public class DwmTheme {
    [DllImport("dwmapi.dll", PreserveSig = true)]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    [DllImport("shell32.dll", SetLastError = true)]
    public static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);

    public static void EnableDark(IntPtr hwnd) {
        try {
            int dark = 1;
            DwmSetWindowAttribute(hwnd, 20, ref dark, sizeof(int));
            DwmSetWindowAttribute(hwnd, 19, ref dark, sizeof(int));

            // 标题栏背景 = 主窗口背景 #141419 (COLORREF 0x00191914)
            int caption = 0x00191914;
            DwmSetWindowAttribute(hwnd, 35, ref caption, sizeof(int));

            // 标题栏文字 = 暖白主文字 #F4F4EE
            int text = 0x00EEF4F4;
            DwmSetWindowAttribute(hwnd, 36, ref text, sizeof(int));

            // 标题栏边框 = 卡片边框色 #232329 (COLORREF 0x00292323)
            int border = 0x00292323;
            DwmSetWindowAttribute(hwnd, 34, ref border, sizeof(int));
        } catch {}
    }
}
"@
Add-Type -TypeDefinition $dwmCode -ErrorAction SilentlyContinue
$dwmCustomCode = @"
using System;
using System.Runtime.InteropServices;
public class DwmThemeCustom {
    [DllImport("dwmapi.dll", PreserveSig = true)]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    public static void SetTheme(IntPtr hwnd, bool isDark) {
        try {
            int dark = isDark ? 1 : 0;
            DwmSetWindowAttribute(hwnd, 20, ref dark, sizeof(int));
            DwmSetWindowAttribute(hwnd, 19, ref dark, sizeof(int));

            int caption = isDark ? 0x00141914 : 0x00EEF3F5;
            DwmSetWindowAttribute(hwnd, 35, ref caption, sizeof(int));

            int text = isDark ? 0x00EEF4F4 : 0x0020241D;
            DwmSetWindowAttribute(hwnd, 36, ref text, sizeof(int));

            int border = isDark ? 0x00292323 : 0x00D4DDD8;
            DwmSetWindowAttribute(hwnd, 34, ref border, sizeof(int));
        } catch {}
    }
}
"@
Add-Type -TypeDefinition $dwmCustomCode -ErrorAction SilentlyContinue

try {
    [DwmTheme]::SetCurrentProcessExplicitAppUserModelID("Android.Debug.Studio.Pro")
} catch {}

# 初始化应用专属图标 (PhoneApp.ico / PhoneApp.png)
$global:AppIconBitmap = $null
$iconCandidates = @(
    (Join-Path $PSScriptRoot "PhoneApp.ico"),
    (Join-Path $PSScriptRoot "PhoneApp.png"),
    "C:\Users\Administrator\Desktop\PhoneApp.ico",
    "C:\Users\Administrator\Desktop\PhoneApp.png"
)
foreach ($iconCandidate in $iconCandidates) {
    if ($iconCandidate -and (Test-Path $iconCandidate)) {
        try {
            $global:AppIconBitmap = [System.Windows.Media.Imaging.BitmapFrame]::Create([System.Uri]::new($iconCandidate))
            if ($global:AppIconBitmap) { break }
        } catch {}
    }
}


$preset1 = 'com.one.bp_tracker'
$preset2 = 'com.smartreader.simple.pdf'
$preset3 = 'com.smartbar.qrcreator'
$preset4 = 'com.quickscan.qrcode'
$preset5 = 'com.simplescan.qrcode.purple'
$playStorePackage = 'com.android.vending'

# 文件管理器列表类型列矢量图标几何 (WPF Path mini-language, 24 viewBox, 见 visual-spec §7)
$script:IcoGeoFolder = 'M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z'
$script:IcoGeoFile = 'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z M14 2v6h6 M16 13H8 M16 17H8 M10 9H8'
$script:IcoGeoLink = 'M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71 M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71'
$script:IcoGeoImage = 'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z M8.5 11a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z M21 15l-5-5L5 21'

function Invoke-CmdText([string]$commandText) {
    $output = cmd /c $commandText 2>&1 | Out-String
    return [pscustomobject]@{
        Command = $commandText
        Output = $output.TrimEnd()
        ExitCode = $LASTEXITCODE
    }
}

function Get-Devices {
    $result = @()
    $lines = adb devices 2>&1
    foreach ($line in $lines) {
        if ($line -match '^(\S+)\s+device$') {
            $serial = $matches[1]
            $model = (adb -s $serial shell getprop ro.product.model 2>$null | Out-String).Trim()
            $os = (adb -s $serial shell getprop ro.build.version.release 2>$null | Out-String).Trim()
            if (-not $model) { $model = 'unknown' }
            if (-not $os) { $os = 'unknown' }
            $isWifi = ($serial -match '^\d+\.\d+\.\d+\.\d+:\d+$')
            $typeStr = if ($isWifi) { '无线' } else { '有线' }
            $displayName = $model + ' [' + $serial + '] (' + $typeStr + ')'

            $obj = New-Object PSObject
            Add-Member -InputObject $obj -NotePropertyName Serial -NotePropertyValue $serial
            Add-Member -InputObject $obj -NotePropertyName Model -NotePropertyValue $model
            Add-Member -InputObject $obj -NotePropertyName OS -NotePropertyValue $os
            Add-Member -InputObject $obj -NotePropertyName TypeStr -NotePropertyValue $typeStr
            Add-Member -InputObject $obj -NotePropertyName DisplayName -NotePropertyValue $displayName
            $result += $obj
        }
    }
    return ,$result
}

function Get-ForegroundPackage([string]$serial) {
    $lines = if ($serial) { adb -s $serial shell dumpsys window 2>$null } else { adb shell dumpsys window 2>$null }
    foreach ($line in $lines) {
        if ($line -match 'mFocusedApp.*?\s([\w\.]+)/') {
            return $matches[1]
        }
    }
    $lines = if ($serial) { adb -s $serial shell dumpsys activity top 2>$null } else { adb shell dumpsys activity top 2>$null }
    foreach ($line in $lines) {
        if ($line -match '^\s*ACTIVITY\s+([^/\s]+)/') {
            return $matches[1]
        }
    }
    return $null
}

function Get-AppVersion([string]$serial, [string]$pkg) {
    $lines = adb -s $serial shell dumpsys package $pkg 2>$null
    foreach ($line in $lines) {
        if ($line -match 'versionName=(.+)$') {
            return $matches[1].Trim()
        }
    }
    return 'unknown'
}

function Get-DeviceIp([string]$serial) {
    $lines = adb -s $serial shell "ip -o -4 addr show" 2>$null
    foreach ($line in $lines) {
        if ($line -match '\s(wlan\d*|eth\d*|ap\d*)\s+inet\s+(\d+\.\d+\.\d+\.\d+)/') {
            return $matches[2]
        }
    }
    $ifconfigLines = adb -s $serial shell "ifconfig wlan0" 2>$null
    foreach ($line in $ifconfigLines) {
        if ($line -match 'inet\s+addr:\s*(\d+\.\d+\.\d+\.\d+)' -or $line -match 'inet\s+(\d+\.\d+\.\d+\.\d+)') {
            return $matches[1]
        }
    }
    $routeLines = adb -s $serial shell "ip route" 2>$null
    foreach ($line in $routeLines) {
        if ($line -match 'dev\s+(?:wlan\d*|eth\d*)\s+.*src\s+(\d+\.\d+\.\d+\.\d+)') {
            return $matches[1]
        }
        if ($line -match 'src\s+(\d+\.\d+\.\d+\.\d+)\s+dev\s+(?:wlan\d*|eth\d*)') {
            return $matches[1]
        }
    }
    return $null
}

function Get-ScrcpyPath {
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    }

    $candidates = @(
        (Join-Path $scriptDir 'scrcpy\scrcpy.exe'),
        (Join-Path $scriptDir 'scrcpy.exe'),
        'scrcpy.exe'
    )
    foreach ($cand in $candidates) {
        if ($cand -eq 'scrcpy.exe') {
            $cmd = Get-Command $cand -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
        } elseif (Test-Path $cand) {
            return $cand
        }
    }
    return $null
}

function Init-ScrcpyEnv {
    $scrcpyExe = Get-ScrcpyPath
    if (-not $scrcpyExe) { return }

    $baseDir = Split-Path -Parent $scrcpyExe

    $serverPath = Join-Path $baseDir 'scrcpy-server'
    if (Test-Path $serverPath) {
        $env:SCRCPY_SERVER_PATH = $serverPath
    }

    $iconPath = Join-Path $baseDir 'scrcpy.png'
    if (Test-Path $iconPath) {
        $env:SCRCPY_ICON_DIR = $baseDir
    }
}

function Test-IsProcessElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Start-ScrcpyWindowProcess {
    param(
        [Parameter(Mandatory = $true)][string]$ScrcpyPath,
        [Parameter(Mandatory = $true)][string]$Serial,
        [string]$WindowTitle = ''
    )

    $baseDir = Split-Path -Parent $ScrcpyPath
    $adbPath = Join-Path $baseDir 'adb.exe'
    $safeSerial = $Serial -replace '"', '' -replace '[\r\n]', ' '
    if (-not $WindowTitle) { $WindowTitle = $Serial }
    $safeTitle = $WindowTitle -replace '"', '' -replace '[\r\n]', ' '
    $argLine = '--serial="' + $safeSerial + '" --window-title="' + $safeTitle + '"'

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ScrcpyPath
    $psi.Arguments = $argLine
    $psi.WorkingDirectory = $baseDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $isElevated = Test-IsProcessElevated
    if ($isElevated) {
        # Windows UIPI 禁止普通 Explorer 向管理员窗口拖放文件。
        # 通过 Explorer 启动隐藏的 PowerShell 代理，让 scrcpy 回到标准桌面权限。
        try {
            $escapedAdb = $adbPath.Replace("'", "''")
            $escapedBase = $baseDir.Replace("'", "''")
            $escapedExe = $ScrcpyPath.Replace("'", "''")
            $escapedArgs = $argLine.Replace("'", "''")
            $wrapperScript = @'
$ErrorActionPreference = 'Stop'
$env:ADB = '{0}'
$env:PATH = '{1};' + $env:PATH
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = '{2}'
$psi.Arguments = '{3}'
$psi.WorkingDirectory = '{1}'
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
[System.Diagnostics.Process]::Start($psi) | Out-Null
'@ -f $escapedAdb, $escapedBase, $escapedExe, $escapedArgs

            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapperScript))
            $shortcutPath = Join-Path $env:TEMP 'DroidOps-Scrcpy-Mirror.lnk'
            $wsh = New-Object -ComObject WScript.Shell
            $shortcut = $wsh.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $shortcut.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
            $shortcut.WorkingDirectory = $baseDir
            $shortcut.WindowStyle = 7
            $shortcut.Save()

            Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"' + $shortcutPath + '"') | Out-Null
            return [pscustomobject]@{
                Success = $true
                Mode = 'standard-shell'
                Message = '镜像窗口已通过标准桌面权限启动，可直接拖入 APK 安装。'
            }
        } catch {
            # 无法降权时仍启动镜像，并在界面中明确提示拖放限制。
        }
    }

    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        $mode = if ($isElevated) { 'elevated-fallback' } else { 'standard' }
        $message = if ($isElevated) {
            '镜像窗口已启动，但当前为管理员权限；Windows 可能禁止拖入 APK，建议以普通权限启动 testApp_gui.bat。'
        } else {
            '镜像窗口已启动，可直接拖入 APK 安装。'
        }
        return [pscustomobject]@{ Success = $true; Mode = $mode; Message = $message }
    } catch {
        return [pscustomobject]@{ Success = $false; Mode = 'failed'; Message = $_.Exception.Message }
    }
}

function TurnOff-DeviceScreen([string]$serial) {
    $scrcpy = Get-ScrcpyPath
    if (-not $scrcpy) {
        return @{ Success = $false; Message = '未找到 scrcpy 执行程序' }
    }

    Init-ScrcpyEnv

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $scrcpy
        $psi.Arguments = '--serial="' + $serial + '" --no-window --no-video --no-audio --turn-screen-off'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = [System.Diagnostics.Process]::Start($psi)

        $readyPattern = '(?:Renderer:|Texture:|\[server\]\s+INFO:\s+Device:|Device display turned off)'
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        while ($sw.ElapsedMilliseconds -lt 6000 -and -not $proc.HasExited) {
            $line = $proc.StandardOutput.ReadLine()
            if ($line -and ($line -match $readyPattern)) {
                break
            }
        }

        return @{ Success = $true; Message = 'scrcpy --turn-screen-off 已下发' }
    } catch {
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

function Set-DeviceTime([string]$serial, [string]$year, [string]$month, [string]$day, [string]$hour, [string]$minute) {
    try {
        $dt = [DateTime]::ParseExact(($year + '-' + $month + '-' + $day + ' ' + $hour + ':' + $minute + ':00'), 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return @{ Success = $false; Message = '时间解析错误' }
    }

    # 方式1：原生系统级 cmd time_detector suggest_network_time (全安卓版本通用，免Root免Shizuku)
    try {
        adb -s $serial shell "cmd time_detector set_auto_detection_enabled true" 2>$null
        adb -s $serial shell "settings put global auto_time 1" 2>$null

        $uptimeStr = (adb -s $serial shell "cat /proc/uptime" 2>$null | Out-String).Trim()
        if ($uptimeStr) {
            $uptimeSec = $uptimeStr.Split(' ')[0]
            $elapsedMillis = [int64]([double]$uptimeSec * 1000)
            $targetEpochMs = [int64](([DateTimeOffset]::new($dt)).ToUnixTimeMilliseconds())

            $res = (adb -s $serial shell "cmd time_detector suggest_network_time --elapsed_realtime $elapsedMillis --unix_epoch_time $targetEpochMs --uncertainty_millis 10" 2>&1 | Out-String).Trim()
            
            adb -s $serial shell "cmd time_detector set_auto_detection_enabled false" 2>$null
            adb -s $serial shell "settings put global auto_time 0" 2>$null

            if ($res -match 'injected') {
                $curDate = (adb -s $serial shell date 2>$null | Out-String).Trim()
                return @{ Success = $true; Message = "时间已成功修改为: $curDate" }
            }
        }
    } catch {}

    # 方式2：Shizuku 广播注入 (备用)
    try {
        $timestampMs = [int64](([DateTimeOffset]::new($dt)).ToUnixTimeSeconds() * 1000)
        adb -s $serial shell "am broadcast -a moe.shizuku.privileged.api.ALARM_SET_TIME --ei time $timestampMs" | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return @{ Success = $true; Message = '时间已通过 Shizuku 成功设置。' }
        }
    } catch {}

    # 方式3：su date 提权 (备用)
    $arg = $month + $day + $hour + $minute + $year + '.00'
    $ret = Invoke-CmdText ('adb -s ' + $serial + ' shell su -c "date ' + $arg + '"')
    if ($ret.ExitCode -eq 0) {
        return @{ Success = $true; Message = '时间已通过 root su 设置。' }
    }

    return @{ Success = $false; Message = '设置时间失败，请检查设备是否支持 time_detector 或具备 root/Shizuku 权限。' }
}

function Parse-LsOutput($rawLines) {
    $items = @()
    foreach ($line in $rawLines) {
        $line = $line.Trim()
        if (-not $line -or $line -like "total *") { continue }
        if ($line -match "^([dlcbsp-][rwxstST-]{9}|\?[?]{9})\s+(\d+|\?)\s+(\S+)\s+(\S+)\s+(\d+|\?)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}|\S+\s+\d+\s+\d+:?\d*)\s+(.+)$") {
            $perms = $matches[1]
            $sizeRaw = $matches[5]
            $date = $matches[6]
            $rawName = $matches[7]

            if ($rawName -eq "." -or $rawName -eq "..") { continue }

            $isDir = $perms.StartsWith("d")
            $isLink = $perms.StartsWith("l")

            $displayName = $rawName
            $targetName = $rawName
            if ($isLink -and $rawName -match "^(.*?)\s*->\s*(.*)$") {
                $displayName = $matches[1] + " ➔ " + $matches[2]
                $targetName = $matches[1]
            }

            $sizeStr = "<文件夹>"
            if (-not $isDir) {
                if ($sizeRaw -match "^\d+$") {
                    $b = [int64]$sizeRaw
                    if ($b -lt 1024) { $sizeStr = "$b B" }
                    elseif ($b -lt 1048576) { $sizeStr = [string]::Format("{0:N1} KB", $b / 1024.0) }
                    elseif ($b -lt 1073741824) { $sizeStr = [string]::Format("{0:N2} MB", $b / 1048576.0) }
                    else { $sizeStr = [string]::Format("{0:N2} GB", $b / 1073741824.0) }
                } else {
                    $sizeStr = $sizeRaw
                }
            }

            $icon = if ($isDir) { $script:IcoGeoFolder } elseif ($isLink) { $script:IcoGeoLink } elseif ($rawName -match '\.(png|jpe?g|gif|bmp|webp|heic)$') { $script:IcoGeoImage } else { $script:IcoGeoFile }
            $items += [pscustomobject]@{
                Icon = $icon
                DisplayName = $displayName
                Name = $targetName
                Size = $sizeStr
                Time = $date
                Perms = $perms
                IsDir = $isDir
                IsLink = $isLink
            }
        }
    }
    return $items
}

$script:fmDevice = $null
$script:fmPath = "/storage/emulated/0/"
$script:fmItems = @()
$script:fmTxtPath = $null
$script:fmListView = $null
$script:fmStatusBar = $null

function Escape-ShellPath([string]$p) {
    return ($p -replace "([ \t&()\[\]{}*?~<>|;`$])", "\`$1")
}

function Push-DeviceFile([string]$serial, [string]$localPath, [string]$remoteDir) {
    if (-not (Test-Path -LiteralPath $localPath)) { return @{ ExitCode = 1; Output = "本地文件不存在" } }
    $cleanDir = $remoteDir.TrimEnd('.', '/').Trim()
    if (-not $cleanDir) { $cleanDir = '/' }
    
    $item = Get-Item -LiteralPath $localPath
    $name = $item.Name
    $remoteDest = if ($cleanDir -eq '/') { '/' + $name } else { $cleanDir + '/' + $name }
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'adb.exe'
    $psi.Arguments = "-s $serial push `"$localPath`" `"$remoteDest`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    $err = $p.StandardError.ReadToEnd()
    $out = $p.StandardOutput.ReadToEnd()
    return @{ ExitCode = $p.ExitCode; Output = ($out + $err).Trim() }
}

function Pull-DeviceFile([string]$serial, [string]$remotePath, [string]$localDestDir) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'adb.exe'
    $psi.Arguments = "-s $serial pull `"$remotePath`" `"$localDestDir`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    $err = $p.StandardError.ReadToEnd()
    $out = $p.StandardOutput.ReadToEnd()
    return @{ ExitCode = $p.ExitCode; Output = ($out + $err).Trim() }
}

function Load-FMDirectory([string]$targetPath) {
    if (-not $script:fmDevice) { return }
    $targetPath = $targetPath.Trim()
    if (-not $targetPath.StartsWith('/')) { $targetPath = '/' + $targetPath }
    if ($targetPath.Length -gt 1 -and -not $targetPath.EndsWith('/')) { $targetPath += '/' }

    if ($script:fmStatusBar) { $script:fmStatusBar.Text = "正在读取: $targetPath ..." }

    $queryPath = if ($targetPath -eq '/') { '/.' } else { $targetPath + '.' }
    $escaped = Escape-ShellPath $queryPath
    $rawLines = adb -s $script:fmDevice.Serial shell ls -la $escaped 2>&1

    $items = Parse-LsOutput $rawLines
    $sorted = $items | Sort-Object @{Expression={ if ($_.IsDir) { 0 } elseif ($_.IsLink) { 1 } else { 2 } }}, Name

    $script:fmPath = $targetPath
    $script:fmItems = $sorted

    if ($script:fmTxtPath) { $script:fmTxtPath.Text = $targetPath }
    if ($script:fmListView) { $script:fmListView.ItemsSource = $sorted }

    $dirCount = ($sorted | Where-Object { $_.IsDir }).Count
    $fileCount = $sorted.Count - $dirCount
    if ($script:fmStatusBar) {
        $script:fmStatusBar.Text = "共 $($sorted.Count) 项 ($dirCount 文件夹, $fileCount 文件) | 当前路径: $targetPath"
    }
}

function Import-DroppedFiles($fileList) {
    if (-not $script:fmDevice) { return }
    if ($fileList -and $fileList.Count -gt 0) {
        $total = $fileList.Count
        if ($script:fmStatusBar) {
            $script:fmStatusBar.Text = "正在拖放导入 $total 个项目到 $($script:fmPath) ..."
        }
        [System.Windows.Forms.Application]::DoEvents()
        $idx = 0
        $success = 0
        $fail = 0
        foreach ($file in $fileList) {
            $idx++
            $baseName = [System.IO.Path]::GetFileName($file)
            if ($script:fmStatusBar) {
                $script:fmStatusBar.Text = "正在导入 ($idx/$total): $baseName ..."
            }
            [System.Windows.Forms.Application]::DoEvents()
            $res = Push-DeviceFile $script:fmDevice.Serial $file $script:fmPath
            if ($res.ExitCode -eq 0) { $success++ } else { $fail++ }
        }
        if ($script:fmStatusBar) {
            $script:fmStatusBar.Text = "拖放导入完成！成功 $success 个，失败 $fail 个"
        }
        Load-FMDirectory $script:fmPath
    }
}

# 危险操作确认弹窗 (规范见 layout-spec §4.3：标题「确认操作」，主按钮 danger 样式 + 动作文案，取消默认聚焦/回车=取消)
function Show-ConfirmDialog([string]$message, [string]$actionText, $owner = $null) {
    $dlgXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="确认操作" SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" Background="{DynamicResource BrushPanelBg}" MinWidth="400"
        FontFamily="Segoe UI, Microsoft YaHei">
    <Window.Resources>
        <!-- 默认动态画刷（如果未继承主窗口则使用默认值） -->
        <SolidColorBrush x:Key="BrushPanelBg" Color="#141419"/>
        <SolidColorBrush x:Key="BrushBtnBg" Color="#1C1C22"/>
        <SolidColorBrush x:Key="BrushBorderSoft" Color="#232329"/>
        <SolidColorBrush x:Key="BrushBorderStrong" Color="#34343E"/>
        <SolidColorBrush x:Key="BrushTextPrimary" Color="#F4F4EE"/>
        <SolidColorBrush x:Key="BrushTextSecondary" Color="#A8A89E"/>
        <SolidColorBrush x:Key="BrushSignal" Color="#FF6B2C"/>
        <SolidColorBrush x:Key="BrushDangerBg" Color="#B32331"/>

        <Style TargetType="Button">
            <Setter Property="MinWidth" Value="88"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="1" CornerRadius="5" Padding="12,0,12,0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{Binding Tag, RelativeSource={RelativeSource AncestorType=Button}}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
            <TextBlock Text="⚠" FontSize="13" Foreground="{DynamicResource BrushSignal}" Margin="0,0,8,0" VerticalAlignment="Center"/>
            <TextBlock Text="确认操作" FontFamily="Consolas" FontSize="12" FontWeight="Bold" Foreground="{DynamicResource BrushTextPrimary}" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock Grid.Row="1" Name="TxtMsg" FontSize="12" Foreground="{DynamicResource BrushTextSecondary}" TextWrapping="Wrap" MaxWidth="420" Margin="0,0,0,20"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="BtnAction" Tag="#D92A3C" Background="{DynamicResource BrushDangerBg}" Foreground="#FFFFFF" BorderBrush="{DynamicResource BrushDangerBg}" Margin="0,0,8,0"/>
            <Button Name="BtnCancel" Tag="{DynamicResource BrushBorderStrong}" Content="取消" IsDefault="True" IsCancel="True" Background="{DynamicResource BrushBtnBg}" Foreground="{DynamicResource BrushTextPrimary}" BorderBrush="{DynamicResource BrushBorderSoft}"/>
        </StackPanel>
    </Grid>
</Window>
'@
    $dlgReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($dlgXaml))
    $dlg = [System.Windows.Markup.XamlReader]::Load($dlgReader)
    if ($script:CurrentTheme -and $script:ThemePalette -and $script:ThemePalette.ContainsKey($script:CurrentTheme)) {
        $pal = $script:ThemePalette[$script:CurrentTheme]
        foreach ($k in $pal.Keys) {
            $c = [System.Windows.Media.ColorConverter]::ConvertFromString($pal[$k])
            $b = New-Object System.Windows.Media.SolidColorBrush($c)
            $b.Freeze()
            $dlg.Resources.Remove($k)
            $dlg.Resources.Add($k, $b)
        }
    }
    if ($owner) { $dlg.Owner = $owner }
    $dlg.FindName('TxtMsg').Text = $message
    $btnAction = $dlg.FindName('BtnAction')
    $btnAction.Content = $actionText
    $btnAction.Add_Click({ $dlg.DialogResult = $true; $dlg.Close() })
    $result = $dlg.ShowDialog()
    return ($result -eq $true)
}

function Show-FileManagerWindow($dev) {
    if (-not $dev) {
        Log "请先选择设备！"
        return
    }

    $script:fmDevice = $dev
    $script:fmPath = "/storage/emulated/0/"

    $explorerXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$($dev.Model) · 远程文件管理器 [$($dev.TypeStr)]" Height="720" Width="1040"
        MinWidth="920" MinHeight="560"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource BrushWindowBg}"
        FontFamily="Segoe UI, Microsoft YaHei">
    <Window.Resources>
        <!-- 动态画刷定义 -->
        <SolidColorBrush x:Key="BrushWindowBg" Color="#0B0B0E"/>
        <SolidColorBrush x:Key="BrushPanelBg" Color="#141419"/>
        <SolidColorBrush x:Key="BrushInputBg" Color="#1C1C22"/>
        <SolidColorBrush x:Key="BrushBorderSoft" Color="#232329"/>
        <SolidColorBrush x:Key="BrushBorderStrong" Color="#34343E"/>
        <SolidColorBrush x:Key="BrushTextPrimary" Color="#F4F4EE"/>
        <SolidColorBrush x:Key="BrushTextSecondary" Color="#A8A89E"/>
        <SolidColorBrush x:Key="BrushTextMuted" Color="#6E6E66"/>
        <SolidColorBrush x:Key="BrushBtnBg" Color="#1C1C22"/>
        <SolidColorBrush x:Key="BrushBtnHoverBg" Color="#24242D"/>
        <SolidColorBrush x:Key="BrushSignal" Color="#FF6B2C"/>
        <SolidColorBrush x:Key="BrushSignalHover" Color="#FF8552"/>
        <SolidColorBrush x:Key="BrushSignalText" Color="#1A0D06"/>
        <SolidColorBrush x:Key="BrushGoBg" Color="#0F7B54"/>
        <SolidColorBrush x:Key="BrushGoHover" Color="#12A06C"/>
        <SolidColorBrush x:Key="BrushDangerBg" Color="#B32331"/>
        <SolidColorBrush x:Key="BrushDangerHover" Color="#D92A3C"/>
        <SolidColorBrush x:Key="BrushItemHoverBg" Color="#2A1A12"/>
        <SolidColorBrush x:Key="BrushItemHoverText" Color="#FFB08A"/>
        <SolidColorBrush x:Key="BrushTerminalBg" Color="#08080A"/>
        <SolidColorBrush x:Key="BrushTerminalText" Color="#D8D8CE"/>

        <!-- FIELD DECK 图标几何 -->
        <Geometry x:Key="IcoBack">M19 12H5 M12 19l-7-7 7-7</Geometry>
        <Geometry x:Key="IcoRefresh">M23 4v6h-6 M1 20v-6h6 M3.51 9a9 9 0 0 1 14.85-3.36L23 10 M1 14l4.64 4.36A9 9 0 0 0 20.49 15</Geometry>
        <Geometry x:Key="IcoHome">M3 10.5L12 3l9 7.5V20a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z M9 22V12h6v10</Geometry>
        <Geometry x:Key="IcoFileText">M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z M14 2v6h6 M16 13H8 M16 17H8 M10 9H8</Geometry>
        <Geometry x:Key="IcoDownloadDir">M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z M12 10v6 M9 13.5l3 3 3-3</Geometry>
        <Geometry x:Key="IcoCamera">M4 7h3l2-3h6l2 3h3a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1z M12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8z</Geometry>
        <Geometry x:Key="IcoImage">M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z M8.5 11a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z M21 15l-5-5L5 21</Geometry>
        <Geometry x:Key="IcoRoot">M22 12H2 M5.45 5.11L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z M6 16h.01 M10 16h.01</Geometry>
        <Geometry x:Key="IcoGo">M5 12h14 M12 5l7 7-7 7</Geometry>
        <Geometry x:Key="IcoUpload">M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4 M17 8l-5-5-5 5 M12 3v12</Geometry>
        <Geometry x:Key="IcoDownload">M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4 M7 10l5 5 5-5 M12 15V3</Geometry>
        <Geometry x:Key="IcoFolderPlus">M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z M12 10v6 M9 13h6</Geometry>
        <Geometry x:Key="IcoPencil">M17 3a2.83 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5z</Geometry>
        <Geometry x:Key="IcoLink">M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71 M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71</Geometry>
        <Geometry x:Key="IcoTrash">M3 6h18 M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2 M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6 M10 11v6 M14 11v6</Geometry>

        <Style x:Key="SilkLabel" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="FontSize" Value="9"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextMuted}"/>
        </Style>

        <Style x:Key="IcoPath" TargetType="Path">
            <Setter Property="Fill" Value="Transparent"/>
            <Setter Property="Stroke" Value="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
            <Setter Property="StrokeThickness" Value="2"/>
            <Setter Property="StrokeStartLineCap" Value="Round"/>
            <Setter Property="StrokeEndLineCap" Value="Round"/>
            <Setter Property="StrokeLineJoin" Value="Round"/>
        </Style>

        <!-- 方形图标按钮 -->
        <Style x:Key="IconSquare" TargetType="Button">
            <Setter Property="Width" Value="32"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="Background" Value="{DynamicResource BrushBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextSecondary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderSoft}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushBtnHoverBg}"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushBorderStrong}"/>
                                <Setter Property="Foreground" Value="{DynamicResource BrushSignal}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushPanelBg}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Places 目录轨按钮 -->
        <Style x:Key="PlaceButton" TargetType="Button">
            <Setter Property="Height" Value="34"/>
            <Setter Property="Margin" Value="0,1,0,1"/>
            <Setter Property="Padding" Value="12,0"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextSecondary}"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" CornerRadius="5" Padding="{TemplateBinding Padding}" Margin="6,0,6,0">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushBtnHoverBg}"/>
                                <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushBorderSoft}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 抬升工具按钮 -->
        <Style x:Key="RaisedButton" TargetType="Button">
            <Setter Property="Height" Value="32"/>
            <Setter Property="Padding" Value="12,0"/>
            <Setter Property="Margin" Value="0,0,6,0"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Background" Value="{DynamicResource BrushBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderSoft}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushBtnHoverBg}"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushBorderStrong}"/>
                                <Setter Property="Foreground" Value="{DynamicResource BrushSignal}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 信号橙主按钮 -->
        <Style x:Key="SignalButton" TargetType="Button" BasedOn="{StaticResource RaisedButton}">
            <Setter Property="Background" Value="{DynamicResource BrushSignal}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushSignalText}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushSignal}"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushSignalHover}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushSignal}"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 薄荷绿成功按钮 -->
        <Style x:Key="GoButton" TargetType="Button" BasedOn="{StaticResource RaisedButton}">
            <Setter Property="Background" Value="{DynamicResource BrushGoBg}"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushGoBg}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushGoHover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 胭脂红危险按钮 -->
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource RaisedButton}">
            <Setter Property="Background" Value="{DynamicResource BrushDangerBg}"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushDangerBg}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushDangerHover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 嵌入输入框 -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource BrushInputBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderSoft}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CaretBrush" Value="{DynamicResource BrushSignal}"/>
            <Setter Property="Padding" Value="10,0"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="SelectionBrush" Value="{DynamicResource BrushBorderStrong}"/>
        </Style>

        <Style TargetType="{x:Type GridViewColumnHeader}">
            <Setter Property="Background" Value="{DynamicResource BrushPanelBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextMuted}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderSoft}"/>
            <Setter Property="BorderThickness" Value="0,0,1,1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="FontSize" Value="9"/>
            <Setter Property="FontWeight" Value="Bold"/>
        </Style>
    </Window.Resources>

    <Grid Margin="14">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- 地址栏 -->
        <Border Grid.Row="0" Background="{DynamicResource BrushPanelBg}" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="1" CornerRadius="6" Padding="8" Margin="0,0,0,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Button Grid.Column="0" Name="NavUp" Style="{StaticResource IconSquare}" ToolTip="返回上级目录">
                    <Viewbox Width="15" Height="15"><Path Data="{StaticResource IcoBack}" Style="{StaticResource IcoPath}"/></Viewbox>
                </Button>
                <Button Grid.Column="1" Name="NavRefresh" Style="{StaticResource IconSquare}" Margin="6,0,0,0" ToolTip="重新读取当前目录">
                    <Viewbox Width="15" Height="15"><Path Data="{StaticResource IcoRefresh}" Style="{StaticResource IcoPath}"/></Viewbox>
                </Button>
                <TextBox Grid.Column="2" Name="TxtCurrentPath" Height="32" Margin="10,0" VerticalContentAlignment="Center" FontFamily="Consolas" FontSize="12.5" ToolTip="当前远程路径，编辑后回车前往"/>
                <Button Grid.Column="3" Name="BtnGoPath" Style="{StaticResource SignalButton}" Width="70" Height="32" Margin="0,0,10,0" ToolTip="前往输入的路径">
                    <StackPanel Orientation="Horizontal">
                        <Viewbox Width="14" Height="14" Margin="0,0,5,0"><Path Data="{StaticResource IcoGo}" Style="{StaticResource IcoPath}"/></Viewbox>
                        <TextBlock Text="前往"/>
                    </StackPanel>
                </Button>
                <TextBox Grid.Column="4" Name="TxtSearch" Width="180" Height="32" VerticalContentAlignment="Center" FontSize="12" ToolTip="输入关键字实时筛选当前目录"/>
            </Grid>
        </Border>

        <!-- 主体：Places 轨 + 文件列表 -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="176"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="{DynamicResource BrushPanelBg}" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="1" CornerRadius="6">
                <StackPanel Margin="0,8">
                    <TextBlock Text="PLACES" Style="{StaticResource SilkLabel}" Margin="18,4,0,8"/>
                    <Button Name="NavSdcard" Style="{StaticResource PlaceButton}">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="15" Height="15" Margin="0,0,9,0"><Path Data="{StaticResource IcoHome}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="内部存储"/>
                        </StackPanel>
                    </Button>
                    <Button Name="NavDocuments" Style="{StaticResource PlaceButton}">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="15" Height="15" Margin="0,0,9,0"><Path Data="{StaticResource IcoFileText}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="文档 Documents"/>
                        </StackPanel>
                    </Button>
                    <Button Name="NavDownload" Style="{StaticResource PlaceButton}">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="15" Height="15" Margin="0,0,9,0"><Path Data="{StaticResource IcoDownloadDir}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="下载 Download"/>
                        </StackPanel>
                    </Button>
                    <Button Name="NavDCIM" Style="{StaticResource PlaceButton}">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="15" Height="15" Margin="0,0,9,0"><Path Data="{StaticResource IcoCamera}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="相册 DCIM"/>
                        </StackPanel>
                    </Button>
                    <Button Name="NavPictures" Style="{StaticResource PlaceButton}">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="15" Height="15" Margin="0,0,9,0"><Path Data="{StaticResource IcoImage}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="图片 Pictures"/>
                        </StackPanel>
                    </Button>
                    <Border Height="1" Background="{DynamicResource BrushBorderSoft}" Margin="14,12,14,10"/>
                    <Button Name="NavRoot" Style="{StaticResource PlaceButton}" ToolTip="跳转系统根目录（需设备权限）">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="15" Height="15" Margin="0,0,9,0"><Path Data="{StaticResource IcoRoot}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="系统根目录 /"/>
                        </StackPanel>
                    </Button>
                </StackPanel>
            </Border>

            <Border Grid.Column="1" Background="{DynamicResource BrushTerminalBg}" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="1" CornerRadius="6" Margin="10,0,0,0">
                <ListView Name="ListViewFiles" Background="Transparent" BorderThickness="0" FontSize="12" Foreground="{DynamicResource BrushTerminalText}" SelectionMode="Extended" AllowDrop="True">
                    <ListView.ItemContainerStyle>
                        <Style TargetType="{x:Type ListViewItem}">
                            <Setter Property="Foreground" Value="{DynamicResource BrushTerminalText}"/>
                            <Setter Property="Background" Value="Transparent"/>
                            <Setter Property="Padding" Value="6,4"/>
                            <Setter Property="BorderThickness" Value="0"/>
                            <Style.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter Property="Background" Value="{DynamicResource BrushItemHoverBg}"/>
                                </Trigger>
                                <Trigger Property="IsSelected" Value="True">
                                    <Setter Property="Background" Value="{DynamicResource BrushItemSelectedBg}"/>
                                    <Setter Property="Foreground" Value="{DynamicResource BrushItemSelectedText}"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </ListView.ItemContainerStyle>
                    <ListView.View>
                        <GridView>
                            <GridViewColumn Width="44">
                                <GridViewColumn.CellTemplate>
                                    <DataTemplate>
                                        <Viewbox Width="15" Height="15" HorizontalAlignment="Center">
                                            <Path Data="{Binding Icon}" Fill="Transparent" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=ListViewItem}}" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                                        </Viewbox>
                                    </DataTemplate>
                                </GridViewColumn.CellTemplate>
                            </GridViewColumn>
                            <GridViewColumn Header="名称" Width="380" DisplayMemberBinding="{Binding DisplayName}"/>
                            <GridViewColumn Header="大小" Width="110" DisplayMemberBinding="{Binding Size}"/>
                            <GridViewColumn Header="修改时间" Width="160" DisplayMemberBinding="{Binding Time}"/>
                            <GridViewColumn Header="权限" Width="140" DisplayMemberBinding="{Binding Perms}"/>
                        </GridView>
                    </ListView.View>
                </ListView>
            </Border>
        </Grid>

        <!-- 操作栏 -->
        <Border Grid.Row="2" Background="{DynamicResource BrushPanelBg}" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="1" CornerRadius="6" Padding="8,6" Margin="0,10,0,0">
            <DockPanel LastChildFill="False">
                <Button DockPanel.Dock="Right" Name="BtnDelete" Style="{StaticResource DangerButton}" Margin="6,0,0,0" ToolTip="删除选中的文件或文件夹（不可恢复）">
                    <StackPanel Orientation="Horizontal">
                        <Viewbox Width="14" Height="14" Margin="0,0,6,0"><Path Data="{StaticResource IcoTrash}" Style="{StaticResource IcoPath}"/></Viewbox>
                        <TextBlock Text="删除选中项"/>
                    </StackPanel>
                </Button>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Button Name="BtnUpload" Style="{StaticResource GoButton}" ToolTip="选择电脑文件上传到当前目录（多选）">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,6,0"><Path Data="{StaticResource IcoUpload}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="上传到设备"/>
                        </StackPanel>
                    </Button>
                    <Button Name="BtnDownload" Style="{StaticResource SignalButton}" ToolTip="批量导出选中项到电脑">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,6,0"><Path Data="{StaticResource IcoDownload}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="导出到电脑"/>
                        </StackPanel>
                    </Button>
                    <Border Width="1" Height="18" Background="{DynamicResource BrushBorderSoft}" Margin="6,0,12,0" VerticalAlignment="Center"/>
                    <Button Name="BtnNewFolder" Style="{StaticResource RaisedButton}" ToolTip="在当前目录新建文件夹">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,6,0"><Path Data="{StaticResource IcoFolderPlus}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="新建文件夹"/>
                        </StackPanel>
                    </Button>
                    <Button Name="BtnRename" Style="{StaticResource RaisedButton}" ToolTip="重命名选中项">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,6,0"><Path Data="{StaticResource IcoPencil}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="重命名"/>
                        </StackPanel>
                    </Button>
                    <Button Name="BtnCopyPath" Style="{StaticResource RaisedButton}" ToolTip="复制选中项（或当前目录）的完整路径">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,6,0"><Path Data="{StaticResource IcoLink}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="复制路径"/>
                        </StackPanel>
                    </Button>
                    <TextBlock Text="拖放文件即导入 · 列表多选可批量导出" FontSize="11" Foreground="{DynamicResource BrushTextMuted}" VerticalAlignment="Center" Margin="10,0,0,0"/>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- 状态栏 -->
        <Border Grid.Row="3" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="0,1,0,0" Margin="0,10,0,0" Padding="4,6">
            <TextBlock Name="TxtStatusBar" Text="正在读取目录..." FontFamily="Consolas" FontSize="10" Foreground="{DynamicResource BrushTextSecondary}" VerticalAlignment="Center"/>
        </Border>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($explorerXaml))
    $explorerWin = [System.Windows.Markup.XamlReader]::Load($reader)
    if ($script:CurrentTheme -and $script:ThemePalette -and $script:ThemePalette.ContainsKey($script:CurrentTheme)) {
        $palFm = $script:ThemePalette[$script:CurrentTheme]
        foreach ($k in $palFm.Keys) {
            $c = [System.Windows.Media.ColorConverter]::ConvertFromString($palFm[$k])
            $b = New-Object System.Windows.Media.SolidColorBrush($c)
            $b.Freeze()
            $explorerWin.Resources.Remove($k)
            $explorerWin.Resources.Add($k, $b)
        }
    }

    if ($global:AppIconBitmap) {
        try { $explorerWin.Icon = $global:AppIconBitmap } catch {}
    }

    $explorerWin.Add_SourceInitialized({
        try {
            $helper = New-Object System.Windows.Interop.WindowInteropHelper($explorerWin)
            [DwmTheme]::EnableDark($helper.Handle)
        } catch {}
    })


    $navUp = $explorerWin.FindName('NavUp')
    $navRefresh = $explorerWin.FindName('NavRefresh')
    $navSdcard = $explorerWin.FindName('NavSdcard')
    $navDocuments = $explorerWin.FindName('NavDocuments')
    $navDownload = $explorerWin.FindName('NavDownload')
    $navDCIM = $explorerWin.FindName('NavDCIM')
    $navPictures = $explorerWin.FindName('NavPictures')
    $navRoot = $explorerWin.FindName('NavRoot')

    $btnGoPath = $explorerWin.FindName('BtnGoPath')
    $txtSearch = $explorerWin.FindName('TxtSearch')

    $btnUpload = $explorerWin.FindName('BtnUpload')
    $btnDownload = $explorerWin.FindName('BtnDownload')
    $btnNewFolder = $explorerWin.FindName('BtnNewFolder')
    $btnRename = $explorerWin.FindName('BtnRename')
    $btnDelete = $explorerWin.FindName('BtnDelete')
    $btnCopyPath = $explorerWin.FindName('BtnCopyPath')

    $script:fmTxtPath = $explorerWin.FindName('TxtCurrentPath')
    $script:fmListView = $explorerWin.FindName('ListViewFiles')
    $script:fmStatusBar = $explorerWin.FindName('TxtStatusBar')

    $navUp.Add_Click({
        if ($script:fmPath -eq '/' -or $script:fmPath -eq '') { return }
        $trimmed = $script:fmPath.TrimEnd('/')
        $idx = $trimmed.LastIndexOf('/')
        $parent = if ($idx -le 0) { '/' } else { $trimmed.Substring(0, $idx + 1) }
        Load-FMDirectory $parent
    })

    $navRefresh.Add_Click({
        Load-FMDirectory $script:fmPath
    })

    $navSdcard.Add_Click({ Load-FMDirectory "/storage/emulated/0/" })
    $navDocuments.Add_Click({ Load-FMDirectory "/storage/emulated/0/Documents/" })
    $navDownload.Add_Click({ Load-FMDirectory "/storage/emulated/0/Download/" })
    $navDCIM.Add_Click({ Load-FMDirectory "/storage/emulated/0/DCIM/" })
    $navPictures.Add_Click({ Load-FMDirectory "/storage/emulated/0/Pictures/" })
    $navRoot.Add_Click({ Load-FMDirectory "/" })

    $btnGoPath.Add_Click({
        Load-FMDirectory $script:fmTxtPath.Text
    })

    $script:fmTxtPath.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
            Load-FMDirectory $script:fmTxtPath.Text
        }
    })

    $txtSearch.Add_TextChanged({
        $q = $txtSearch.Text.Trim()
        if (-not $q) {
            $script:fmListView.ItemsSource = $script:fmItems
        } else {
            $filtered = $script:fmItems | Where-Object { $_.Name -like "*$q*" -or $_.DisplayName -like "*$q*" }
            $script:fmListView.ItemsSource = $filtered
        }
    })

    # 支持 Ctrl+A 全选
    $script:fmListView.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::A -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
            $script:fmListView.SelectAll()
        }
    })

    # 处理电脑文件拖放导入
    $script:fmListView.Add_DragOver({
        param($s, $e)
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $e.Effects = [System.Windows.DragDropEffects]::Copy
            $e.Handled = $true
        }
    })

    $script:fmListView.Add_Drop({
        param($s, $e)
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
            Import-DroppedFiles $files
        }
    })

    $explorerWin.AllowDrop = $true
    $explorerWin.Add_DragOver({
        param($s, $e)
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $e.Effects = [System.Windows.DragDropEffects]::Copy
            $e.Handled = $true
        }
    })
    $explorerWin.Add_Drop({
        param($s, $e)
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
            Import-DroppedFiles $files
        }
    })

    # 支持从手机文件列表拖拽导出到电脑
    $script:dragStartPos = $null
    $script:fmListView.Add_PreviewMouseLeftButtonDown({
        param($s, $e)
        $script:dragStartPos = $e.GetPosition($null)
    })

    $script:fmListView.Add_MouseMove({
        param($s, $e)
        if ($e.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed -and $script:dragStartPos) {
            $pos = $e.GetPosition($null)
            $diff = $script:dragStartPos - $pos
            if ([Math]::Abs($diff.X) -gt 6 -or [Math]::Abs($diff.Y) -gt 6) {
                $selected = @($script:fmListView.SelectedItems)
                if ($selected.Count -gt 0) {
                    $script:dragStartPos = $null
                    $cacheDir = Join-Path $env:TEMP ('adb_drag_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
                    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
                    $pulledFiles = @()
                    $script:fmStatusBar.Text = "正在准备拖拽导出 $($selected.Count) 项..."
                    [System.Windows.Forms.Application]::DoEvents()
                    foreach ($sel in $selected) {
                        $cleanDir = $script:fmPath.TrimEnd('.', '/').Trim()
                        if (-not $cleanDir) { $cleanDir = '/' }
                        $remoteP = if ($cleanDir -eq '/') { '/' + $sel.Name } else { $cleanDir + '/' + $sel.Name }
                        $res = Pull-DeviceFile $script:fmDevice.Serial $remoteP $cacheDir
                        $localTarget = Join-Path $cacheDir $sel.Name
                        if (Test-Path -LiteralPath $localTarget) {
                            $pulledFiles += $localTarget
                        }
                    }
                    if ($pulledFiles.Count -gt 0) {
                        $script:fmStatusBar.Text = "请拖放到桌面或电脑文件夹松开完成导出..."
                        $dataObj = New-Object System.Windows.DataObject
                        $dataObj.SetData([System.Windows.DataFormats]::FileDrop, [string[]]$pulledFiles)
                        [System.Windows.DragDrop]::DoDragDrop($script:fmListView, $dataObj, [System.Windows.DragDropEffects]::Copy) | Out-Null
                        $script:fmStatusBar.Text = "拖拽导出完成 (共 $($pulledFiles.Count) 项)"
                    }
                }
            }
        }
    })

    $script:fmListView.Add_MouseDoubleClick({
        $sel = $script:fmListView.SelectedItem
        if (-not $sel) { return }
        if ($sel.IsDir -or $sel.IsLink) {
            $sub = if ($script:fmPath -eq '/') { '/' + $sel.Name + '/' } else { $script:fmPath.TrimEnd('/') + '/' + $sel.Name + '/' }
            Load-FMDirectory $sub
        } else {
            $cleanDir = $script:fmPath.TrimEnd('.', '/').Trim()
            if (-not $cleanDir) { $cleanDir = '/' }
            $remoteFile = if ($cleanDir -eq '/') { '/' + $sel.Name } else { $cleanDir + '/' + $sel.Name }
            $tempDir = Join-Path $env:TEMP 'adb_preview'
            if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
            $localFile = Join-Path $tempDir $sel.Name
            $script:fmStatusBar.Text = "正在下载预览: $($sel.Name) ..."
            [System.Windows.Forms.Application]::DoEvents()
            $res = Pull-DeviceFile $script:fmDevice.Serial $remoteFile $tempDir
            if ($res.ExitCode -eq 0 -and (Test-Path -LiteralPath $localFile)) {
                Start-Process $localFile
                $script:fmStatusBar.Text = "已打开文件预览: $($sel.Name)"
            } else {
                $script:fmStatusBar.Text = "下载文件失败。"
            }
        }
    })

    $btnUpload.Add_Click({
        $ofd = New-Object Microsoft.Win32.OpenFileDialog
        $ofd.Multiselect = $true
        $ofd.Title = "选择要上传到手机的文件 (支持按住 Ctrl/Shift 多选)"
        if ($ofd.ShowDialog() -eq $true) {
            $files = $ofd.FileNames
            $total = $files.Count
            $script:fmStatusBar.Text = "正在上传 $total 个文件到 $($script:fmPath) ..."
            [System.Windows.Forms.Application]::DoEvents()
            $idx = 0
            $success = 0
            $fail = 0
            foreach ($fn in $files) {
                $idx++
                $baseName = [System.IO.Path]::GetFileName($fn)
                $script:fmStatusBar.Text = "上传中 ($idx/$total): $baseName ..."
                [System.Windows.Forms.Application]::DoEvents()
                $res = Push-DeviceFile $script:fmDevice.Serial $fn $script:fmPath
                if ($res.ExitCode -eq 0) { $success++ } else { $fail++ }
            }
            $script:fmStatusBar.Text = "上传完成！成功 $success 个，失败 $fail 个"
            Load-FMDirectory $script:fmPath
        }
    })

    $btnDownload.Add_Click({
        $selectedItems = @($script:fmListView.SelectedItems)
        if ($selectedItems.Count -eq 0) {
            [System.Windows.MessageBox]::Show("请先在列表中选择要导出的文件或文件夹（支持按住 Ctrl / Shift 多选）！", "提示", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }

        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "选择导出到电脑的目标文件夹 (共 $($selectedItems.Count) 项)"
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $destDir = $fbd.SelectedPath
            $total = $selectedItems.Count
            $script:fmStatusBar.Text = "正在导出 $total 项到 $destDir ..."
            [System.Windows.Forms.Application]::DoEvents()
            
            $successCount = 0
            $failCount = 0
            foreach ($sel in $selectedItems) {
                $cleanDir = $script:fmPath.TrimEnd('.', '/').Trim()
                if (-not $cleanDir) { $cleanDir = '/' }
                $remotePath = if ($cleanDir -eq '/') { '/' + $sel.Name } else { $cleanDir + '/' + $sel.Name }

                $res = Pull-DeviceFile $script:fmDevice.Serial $remotePath $destDir
                if ($res.ExitCode -eq 0) {
                    $successCount++
                } else {
                    $failCount++
                }
                $script:fmStatusBar.Text = "导出进度: $($successCount + $failCount)/$total ($($sel.Name))"
                [System.Windows.Forms.Application]::DoEvents()
            }
            $msg = "导出完成！成功: $successCount, 失败: $failCount`r`n保存路径: $destDir"
            $script:fmStatusBar.Text = $msg
            [System.Windows.MessageBox]::Show($msg, "导出结果", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    })

    $btnNewFolder.Add_Click({
        $name = [Microsoft.VisualBasic.Interaction]::InputBox("请输入新文件夹名称：", "新建文件夹", "新建文件夹")
        $name = $name.Trim()
        if ($name) {
            $newPath = if ($script:fmPath -eq '/') { '/' + $name } else { $script:fmPath.TrimEnd('/') + '/' + $name }
            adb -s $script:fmDevice.Serial shell mkdir -p (Escape-ShellPath $newPath) | Out-Null
            Load-FMDirectory $script:fmPath
        }
    })

    $btnRename.Add_Click({
        $sel = $script:fmListView.SelectedItem
        if (-not $sel) {
            [System.Windows.MessageBox]::Show("请先选择要重命名的项！", "提示", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }
        $newName = [Microsoft.VisualBasic.Interaction]::InputBox("请输入新名称：", "重命名", $sel.Name)
        $newName = $newName.Trim()
        if ($newName -and $newName -ne $sel.Name) {
            $oldP = if ($script:fmPath -eq '/') { '/' + $sel.Name } else { $script:fmPath.TrimEnd('/') + '/' + $sel.Name }
            $newP = if ($script:fmPath -eq '/') { '/' + $newName } else { $script:fmPath.TrimEnd('/') + '/' + $newName }
            adb -s $script:fmDevice.Serial shell mv (Escape-ShellPath $oldP) (Escape-ShellPath $newP) | Out-Null
            Load-FMDirectory $script:fmPath
        }
    })

    $btnDelete.Add_Click({
        $selected = @($script:fmListView.SelectedItems)
        if ($selected.Count -eq 0) {
            [System.Windows.MessageBox]::Show("请先选择要删除的项！", "提示", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }
        $names = ($selected | Select-Object -First 3 | ForEach-Object { $_.Name }) -join '、'
        $msg = "将删除 $($selected.Count) 项: $names"
        if ($selected.Count -gt 3) { $msg += " 等" }
        $msg += "`n此操作不可恢复！"
        if (Show-ConfirmDialog -message $msg -actionText ('删除 ' + $selected.Count + ' 项') -owner $explorerWin) {
            foreach ($sel in $selected) {
                $targetP = if ($script:fmPath -eq '/') { '/' + $sel.Name } else { $script:fmPath.TrimEnd('/') + '/' + $sel.Name }
                adb -s $script:fmDevice.Serial shell rm -rf (Escape-ShellPath $targetP) | Out-Null
            }
            Load-FMDirectory $script:fmPath
        }
    })

    $btnCopyPath.Add_Click({
        $sel = $script:fmListView.SelectedItem
        $p = if (-not $sel) { $script:fmPath } else { if ($script:fmPath -eq '/') { '/' + $sel.Name } else { $script:fmPath.TrimEnd('/') + '/' + $sel.Name } }
        [System.Windows.Clipboard]::SetText($p)
        $script:fmStatusBar.Text = "已复制路径: $p"
    })

    Load-FMDirectory "/storage/emulated/0/"
    $explorerWin.Show()
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DroidOps · Android 调试工作台" Height="900" Width="1440" MinHeight="820" MinWidth="1280"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource BrushWindowBg}"
        FontFamily="Microsoft YaHei UI, Segoe UI" UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Window.Resources>
        <!-- 浅色工业精密风：暖灰表面、墨绿文字、单一工业橙强调色 -->
        <SolidColorBrush x:Key="BrushWindowBg" Color="#F2F3EF"/>
        <SolidColorBrush x:Key="BrushPanelBg" Color="#FBFCF9"/>
        <SolidColorBrush x:Key="BrushPanelHeaderBg" Color="#F5F6F2"/>
        <SolidColorBrush x:Key="BrushInputBg" Color="#FDFEFB"/>
        <SolidColorBrush x:Key="BrushInputHoverBg" Color="#F0F2EC"/>
        <SolidColorBrush x:Key="BrushDropdownBg" Color="#FDFEFB"/>
        <SolidColorBrush x:Key="BrushBorderSoft" Color="#D8DDD4"/>
        <SolidColorBrush x:Key="BrushBorderStrong" Color="#B8C1B4"/>
        <SolidColorBrush x:Key="BrushTextPrimary" Color="#20261F"/>
        <SolidColorBrush x:Key="BrushTextSecondary" Color="#4E5A4C"/>
        <SolidColorBrush x:Key="BrushTextMuted" Color="#6E786A"/>
        <SolidColorBrush x:Key="BrushBtnBg" Color="#F4F6F1"/>
        <SolidColorBrush x:Key="BrushBtnHoverBg" Color="#E9EDE5"/>
        <SolidColorBrush x:Key="BrushSignal" Color="#B84A24"/>
        <SolidColorBrush x:Key="BrushSignalHover" Color="#963B1C"/>
        <SolidColorBrush x:Key="BrushSignalText" Color="#FFFDF8"/>
        <SolidColorBrush x:Key="BrushGoBg" Color="#276A4D"/>
        <SolidColorBrush x:Key="BrushGoHover" Color="#1E563D"/>
        <SolidColorBrush x:Key="BrushDangerBg" Color="#A63B36"/>
        <SolidColorBrush x:Key="BrushDangerHover" Color="#87302C"/>
        <SolidColorBrush x:Key="BrushItemHoverBg" Color="#F6E8DF"/>
        <SolidColorBrush x:Key="BrushItemHoverText" Color="#8E371B"/>
        <SolidColorBrush x:Key="BrushItemSelectedBg" Color="#EFDCCF"/>
        <SolidColorBrush x:Key="BrushItemSelectedText" Color="#853316"/>
        <SolidColorBrush x:Key="BrushTerminalBg" Color="#20261F"/>
        <SolidColorBrush x:Key="BrushTerminalText" Color="#E6EADF"/>

        <!-- 矢量图标几何集合（24 网格） -->
        <Geometry x:Key="IcoRefresh">M23 4v6h-6 M1 20v-6h6 M3.51 9a9 9 0 0 1 14.85-3.36L23 10 M1 14l4.64 4.36A9 9 0 0 0 20.49 15</Geometry>
        <Geometry x:Key="IcoCrosshair">M12 7a5 5 0 1 1 0 10 5 5 0 1 1 0-10 M12 2v3 M12 19v3 M2 12h3 M19 12h3</Geometry>
        <Geometry x:Key="IcoLaunch">M7 17L17 7 M8 7h9v9</Geometry>
        <Geometry x:Key="IcoEraser">M7 21L2.7 16.7a2.4 2.4 0 0 1 0-3.4l9.6-9.6a2.4 2.4 0 0 1 3.4 0l5.6 5.6a2.4 2.4 0 0 1 0 3.4L13 21 M22 21H7 M5 11l9 9</Geometry>
        <Geometry x:Key="IcoFlame">M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.07-2.14-.22-4.05 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.15.43-2.29 1-3a2.5 2.5 0 0 0 2.5 2.5z</Geometry>
        <Geometry x:Key="IcoSnow">M12 2v20 M3.34 7l17.32 10 M20.66 7L3.34 17</Geometry>
        <Geometry x:Key="IcoStopOct">M7.86 2h8.28L22 7.86v8.28L15.86 22H7.86L2 15.86V7.86z M9.5 9.5h5v5h-5z</Geometry>
        <Geometry x:Key="IcoTrash">M3 6h18 M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2 M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6 M10 11v6 M14 11v6</Geometry>
        <Geometry x:Key="IcoFolder">M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z</Geometry>
        <Geometry x:Key="IcoMonitor">M4 4h16a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z M8 20h8 M12 16v4</Geometry>
        <Geometry x:Key="IcoMoon">M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z</Geometry>
        <Geometry x:Key="IcoWifi">M5 12.55a11 11 0 0 1 14.08 0 M1.42 9a16 16 0 0 1 21.16 0 M8.53 16.11a6 6 0 0 1 6.95 0 M12 20h.01</Geometry>
        <Geometry x:Key="IcoClockReset">M3 3v5h5 M3.05 13A9 9 0 1 0 6 5.3L3 8 M12 7v5l4 2</Geometry>
        <Geometry x:Key="IcoClock">M12 22a10 10 0 1 1 0-20 10 10 0 0 1 0 20z M12 6v6l4 2</Geometry>
        <Geometry x:Key="IcoCalendar">M8 2v4 M16 2v4 M3 8h18 M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z</Geometry>
        <Geometry x:Key="IcoFileText">M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z M14 2v6h6 M16 13H8 M16 17H8 M10 9H8</Geometry>
        <Geometry x:Key="IcoGlobe">M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20 M2 12h20 M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z</Geometry>
        <Geometry x:Key="IcoBag">M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z M3 6h18 M16 10a4 4 0 0 1-8 0</Geometry>
        <Geometry x:Key="IcoDatabase">M12 8c4.97 0 9-1.34 9-3s-4.03-3-9-3-9 1.34-9 3 4.03 3 9 3z M21 12c0 1.66-4.03 3-9 3s-9-1.34-9-3 M3 5v14c0 1.66 4.03 3 9 3s9-1.34 9-3V5</Geometry>
        <Geometry x:Key="IcoLink">M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71 M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71</Geometry>
        <Geometry x:Key="IcoAlert">M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z M12 9v4 M12 17h.01</Geometry>
        <Geometry x:Key="IcoCopy">M9 9h11a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V10a1 1 0 0 1 1-1z M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1</Geometry>
        <Geometry x:Key="IcoClear">M4 17l6-6-6-6 M12 19h8</Geometry>
        <Geometry x:Key="IcoSun">M12 2v2 M12 20v2 M4.93 4.93l1.41 1.41 M17.66 17.66l1.41 1.41 M2 12h2 M20 12h2 M6.34 17.66l-1.41 1.41 M19.07 4.93l-1.41 1.41 M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10z</Geometry>
        <Geometry x:Key="IcoMoonTheme">M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z</Geometry>
        <Geometry x:Key="IcoInstall">M12 2v13 M7 9.5l5 5.5 5-5.5 M4 20h16</Geometry>

        <!-- 工业丝印标签：只用于分区与字段说明，不用于正文 -->
        <Style x:Key="SilkLabel" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="FontSize" Value="9.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextMuted}"/>
        </Style>

        <Style x:Key="FieldLabel" TargetType="TextBlock">
            <Setter Property="FontSize" Value="10.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextSecondary}"/>
            <Setter Property="Margin" Value="1,0,0,5"/>
        </Style>

        <Style x:Key="SectionTitle" TargetType="TextBlock">
            <Setter Property="FontSize" Value="13.5"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>

        <Style x:Key="SectionHint" TargetType="TextBlock">
            <Setter Property="FontSize" Value="10"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextMuted}"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
        </Style>

        <!-- 图标 Path 统一绑定 -->
        <Style x:Key="IcoPath" TargetType="Path">
            <Setter Property="Fill" Value="Transparent"/>
            <Setter Property="Stroke" Value="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
            <Setter Property="StrokeThickness" Value="2"/>
            <Setter Property="StrokeStartLineCap" Value="Round"/>
            <Setter Property="StrokeEndLineCap" Value="Round"/>
            <Setter Property="StrokeLineJoin" Value="Round"/>
        </Style>

        <!-- ═════════ 彻底防反白的 ComboBox 控件模板 ═════════ -->
        <ControlTemplate x:Key="FlatComboBoxToggleButton" TargetType="{x:Type ToggleButton}">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition />
                    <ColumnDefinition Width="28" />
                </Grid.ColumnDefinitions>
                <Border x:Name="Border" Grid.ColumnSpan="2" CornerRadius="5"
                        Background="{DynamicResource BrushInputBg}"
                        BorderBrush="{DynamicResource BrushBorderSoft}"
                        BorderThickness="1" />
                <Path x:Name="Arrow" Grid.Column="1" Fill="{DynamicResource BrushTextSecondary}"
                      HorizontalAlignment="Center" VerticalAlignment="Center"
                      Data="M 0 0 L 4 4 L 8 0 Z"/>
            </Grid>
            <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource BrushSignal}"/>
                    <Setter TargetName="Border" Property="Background" Value="{DynamicResource BrushInputHoverBg}"/>
                    <Setter TargetName="Arrow" Property="Fill" Value="{DynamicResource BrushSignal}"/>
                </Trigger>
                <Trigger Property="IsChecked" Value="True">
                    <Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource BrushSignal}"/>
                </Trigger>
            </ControlTemplate.Triggers>
        </ControlTemplate>

        <Style TargetType="{x:Type ComboBox}">
            <Setter Property="Height" Value="34"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="Background" Value="{DynamicResource BrushInputBg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderSoft}"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ComboBox}">
                        <Grid>
                            <ToggleButton x:Name="ToggleButton" Template="{StaticResource FlatComboBoxToggleButton}"
                                          Focusable="False"
                                          IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                          ClickMode="Press"/>
                            <ContentPresenter x:Name="ContentSite" IsHitTestVisible="False"
                                              Content="{TemplateBinding SelectionBoxItem}"
                                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                              Margin="10,0,30,0" VerticalAlignment="Center" HorizontalAlignment="Left">
                                <TextBlock.Foreground>
                                    <DynamicResource ResourceKey="BrushTextPrimary"/>
                                </TextBlock.Foreground>
                            </ContentPresenter>
                            <Popup x:Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                <Grid x:Name="DropDown" SnapsToDevicePixels="True" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="300">
                                    <Border x:Name="DropDownBorder" Background="{DynamicResource BrushDropdownBg}"
                                            BorderBrush="{DynamicResource BrushBorderStrong}" BorderThickness="1" CornerRadius="6"
                                            Margin="0,4,0,6">
                                        <ScrollViewer Margin="4,4,4,4" SnapsToDevicePixels="True">
                                            <StackPanel IsItemsHost="True" />
                                        </ScrollViewer>
                                    </Border>
                                </Grid>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="{x:Type ComboBoxItem}">
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ComboBoxItem}">
                        <Border x:Name="ItemBorder" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" CornerRadius="4" Margin="2,1">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="{DynamicResource BrushItemHoverBg}"/>
                                <Setter Property="Foreground" Value="{DynamicResource BrushItemHoverText}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="{DynamicResource BrushItemSelectedBg}"/>
                                <Setter Property="Foreground" Value="{DynamicResource BrushItemSelectedText}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 输入框：字段标签始终位于输入框上方，键盘焦点清晰可见 -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource BrushInputBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderSoft}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CaretBrush" Value="{DynamicResource BrushSignal}"/>
            <Setter Property="Padding" Value="10,0"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="SelectionBrush" Value="{DynamicResource BrushBorderStrong}"/>
            <Style.Triggers>
                <Trigger Property="IsKeyboardFocused" Value="True">
                    <Setter Property="BorderBrush" Value="{DynamicResource BrushSignal}"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Opacity" Value="0.5"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- 方形小图标按钮 -->
        <Style x:Key="IconSquare" TargetType="Button">
            <Setter Property="Width" Value="34"/>
            <Setter Property="Height" Value="34"/>
            <Setter Property="Background" Value="{DynamicResource BrushBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextSecondary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderSoft}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushBtnHoverBg}"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushBorderStrong}"/>
                                <Setter Property="Foreground" Value="{DynamicResource BrushSignal}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushPanelBg}"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushSignal}"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 顶部皮肤切换按钮 -->
        <Style x:Key="HeaderThemeButton" TargetType="Button">
            <Setter Property="Height" Value="34"/>
            <Setter Property="Padding" Value="12,0"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Background" Value="{DynamicResource BrushBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderSoft}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushBtnHoverBg}"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushSignal}"/>
                                <Setter Property="Foreground" Value="{DynamicResource BrushSignal}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 信号橙主按钮 -->
        <Style x:Key="SignalButton" TargetType="Button">
            <Setter Property="Height" Value="34"/>
            <Setter Property="Padding" Value="14,0"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Background" Value="{DynamicResource BrushSignal}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushSignalText}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushSignalHover}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushSignalHover}"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushTextPrimary}"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 绿色高亮主打按键 -->
        <Style x:Key="HighlightGoButton" TargetType="Button">
            <Setter Property="Height" Value="36"/>
            <Setter Property="Margin" Value="0,2,0,3"/>
            <Setter Property="Padding" Value="10,0"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Background" Value="{DynamicResource BrushGoBg}"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushGoHover}"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushTextPrimary}"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 橙色高亮主打按键 -->
        <Style x:Key="HighlightSignalButton" TargetType="Button">
            <Setter Property="Height" Value="36"/>
            <Setter Property="Margin" Value="0,2,0,3"/>
            <Setter Property="Padding" Value="10,0"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Background" Value="{DynamicResource BrushSignal}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushSignalText}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushSignalHover}"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushTextPrimary}"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 模块操作行按钮（扁平微抬升） -->
        <Style x:Key="FlatCmdButton" TargetType="Button">
            <Setter Property="Height" Value="34"/>
            <Setter Property="Margin" Value="0,2,0,2"/>
            <Setter Property="Padding" Value="10,0"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="Background" Value="{DynamicResource BrushBtnBg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderSoft}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushBtnHoverBg}"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushBorderStrong}"/>
                                <Setter Property="Foreground" Value="{DynamicResource BrushSignal}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushPanelBg}"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushSignal}"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 危险操作行按钮（暗红/浅红警示） -->
        <Style x:Key="DangerCmdButton" TargetType="Button" BasedOn="{StaticResource FlatCmdButton}">
            <Setter Property="Foreground" Value="{DynamicResource BrushDangerBg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderSoft}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushDangerHover}"/>
                                <Setter Property="Foreground" Value="#FFFDF8"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushDangerBg}"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 预设目标按钮（双行展示） -->
        <Style x:Key="PresetButton" TargetType="Button">
            <Setter Property="Height" Value="42"/>
            <Setter Property="Margin" Value="0,2,0,2"/>
            <Setter Property="Padding" Value="10,0"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="Background" Value="{DynamicResource BrushBtnBg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderSoft}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushBtnHoverBg}"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushSignal}"/>
                                <Setter Property="Foreground" Value="{DynamicResource BrushSignal}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BrushPanelBg}"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{DynamicResource BrushSignal}"/>
                                <Setter TargetName="border" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- 日志区分割条 -->
        <Style TargetType="GridSplitter">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Height" Value="6"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource BrushSignal}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*" MinHeight="390"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="200" MinHeight="150"/>
        </Grid.RowDefinitions>

        <!-- Row 0: 品牌、设备与目标。所有常用上下文始终可见。 -->
        <Border Grid.Row="0" Background="{DynamicResource BrushPanelBg}" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="0,0,0,1" Padding="20,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="64"/>
                    <RowDefinition Height="86"/>
                </Grid.RowDefinitions>

                <DockPanel Grid.Row="0" LastChildFill="True">
                    <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" VerticalAlignment="Center">
                        <Border Background="{DynamicResource BrushItemSelectedBg}" CornerRadius="4" Padding="8,4" Margin="0,0,12,0">
                            <TextBlock Text="LOCAL / ADB" Style="{StaticResource SilkLabel}" Foreground="{DynamicResource BrushItemSelectedText}"/>
                        </Border>
                        <Button Name="BtnToggleTheme" Style="{StaticResource HeaderThemeButton}" ToolTip="切换浅色 / 深色主题">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="14" Height="14" Margin="0,0,7,0">
                                    <Path Name="IcoThemePath" Data="{StaticResource IcoMoonTheme}" Style="{StaticResource IcoPath}"/>
                                </Viewbox>
                                <TextBlock Name="TxtThemeBtn" Text="深色模式"/>
                            </StackPanel>
                        </Button>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Border Width="36" Height="36" Background="{DynamicResource BrushSignal}" CornerRadius="7">
                            <TextBlock Text="D" FontFamily="Segoe UI" FontSize="19" FontWeight="Bold" Foreground="{DynamicResource BrushSignalText}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
                            <TextBlock Text="DroidOps" FontFamily="Segoe UI" FontSize="20" FontWeight="Bold" Foreground="{DynamicResource BrushTextPrimary}"/>
                            <TextBlock Text="ANDROID DEBUG WORKSPACE" Style="{StaticResource SilkLabel}" Margin="0,1,0,0"/>
                        </StackPanel>
                        <Border Width="1" Height="26" Background="{DynamicResource BrushBorderSoft}" Margin="18,0"/>
                        <TextBlock Text="调试工作台" FontSize="12.5" Foreground="{DynamicResource BrushTextSecondary}" VerticalAlignment="Center"/>
                    </StackPanel>
                </DockPanel>

                <Grid Grid.Row="1" Margin="0,0,0,16">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="1.08*"/>
                        <ColumnDefinition Width="1.22*"/>
                        <ColumnDefinition Width="150"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" Margin="0,0,16,0">
                        <DockPanel Margin="0,0,0,6">
                            <TextBlock Text="01  连接设备" Style="{StaticResource FieldLabel}"/>
                            <TextBlock Name="TxtDeviceStatus" Text="正在检测…" Style="{StaticResource SilkLabel}" HorizontalAlignment="Right"/>
                        </DockPanel>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <ComboBox Name="CmbDevices" Grid.Column="0" Height="36" ToolTip="选择已连接的 ADB 设备"/>
                            <Button Name="BtnRefreshDevices" Grid.Column="1" Style="{StaticResource IconSquare}" Width="36" Height="36" Margin="8,0,0,0" ToolTip="刷新设备列表" AutomationProperties.Name="刷新设备列表">
                                <Viewbox Width="15" Height="15"><Path Data="{StaticResource IcoRefresh}" Style="{StaticResource IcoPath}"/></Viewbox>
                            </Button>
                        </Grid>
                    </StackPanel>

                    <StackPanel Grid.Column="1" Margin="0,0,16,0">
                        <TextBlock Text="02  目标应用包名" Style="{StaticResource FieldLabel}"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox Name="TxtPackage" Grid.Column="0" Height="36" VerticalContentAlignment="Center" ToolTip="输入应用包名，按 Enter 直接打开"/>
                            <Button Name="BtnRefreshForeground" Grid.Column="1" Style="{StaticResource IconSquare}" Width="36" Height="36" Margin="8,0,0,0" ToolTip="获取当前前台应用包名" AutomationProperties.Name="获取前台应用包名">
                                <Viewbox Width="15" Height="15"><Path Data="{StaticResource IcoCrosshair}" Style="{StaticResource IcoPath}"/></Viewbox>
                            </Button>
                        </Grid>
                    </StackPanel>

                    <StackPanel Grid.Column="2">
                        <TextBlock Text="03  快捷操作" Style="{StaticResource FieldLabel}"/>
                        <Button Name="BtnOpenApp" Style="{StaticResource SignalButton}" Height="36" HorizontalContentAlignment="Center" ToolTip="在所选设备上打开目标应用">
                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                                <Viewbox Width="14" Height="14" Margin="0,0,7,0"><Path Data="{StaticResource IcoLaunch}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="打开应用"/>
                            </StackPanel>
                        </Button>
                    </StackPanel>
                </Grid>
            </Grid>
        </Border>

        <!-- Row 1: 全功能平铺看板。无选项卡、折叠面板或二级菜单。 -->
        <Grid Grid.Row="1" Margin="20,14,20,14">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- 列 1: 应用管理；危险操作集中隔离。 -->
            <Border Grid.Column="0" Background="{DynamicResource BrushPanelBg}" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,0,6,0">
                <StackPanel>
                    <DockPanel Margin="1,0,1,4">
                        <Border Background="{DynamicResource BrushSignal}" CornerRadius="3" Padding="6,2" Margin="0,0,9,0">
                            <TextBlock Text="01" FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource BrushSignalText}"/>
                        </Border>
                        <TextBlock Text="应用管理" Style="{StaticResource SectionTitle}"/>
                        <TextBlock Text="APP" Style="{StaticResource SilkLabel}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </DockPanel>
                    <TextBlock Text="安装、统计调试与进程控制" Style="{StaticResource SectionHint}" Margin="1,0,0,10"/>
                    <Border Height="1" Background="{DynamicResource BrushBorderSoft}" Margin="0,0,0,10"/>

                    <Button Name="BtnInstallApk" Style="{StaticResource HighlightGoButton}" ToolTip="选择一个或多个 APK / XAPK 安装包">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,8,0"><Path Data="{StaticResource IcoInstall}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="安装 APK / XAPK"/>
                        </StackPanel>
                    </Button>
                    <Grid Margin="0,1,0,1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button Grid.Column="0" Name="BtnEnableFirebase" Style="{StaticResource FlatCmdButton}" Margin="0,2,3,2" ToolTip="开启 Firebase Analytics 统计调试">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,6,0"><Path Data="{StaticResource IcoFlame}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="开启统计调试"/>
                            </StackPanel>
                        </Button>
                        <Button Grid.Column="1" Name="BtnDisableFirebase" Style="{StaticResource FlatCmdButton}" Margin="3,2,0,2" ToolTip="关闭 Firebase Analytics 统计调试">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,6,0"><Path Data="{StaticResource IcoSnow}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="关闭统计调试"/>
                            </StackPanel>
                        </Button>
                    </Grid>

                    <DockPanel Margin="1,16,1,6">
                        <TextBlock Text="危险操作" FontSize="10.5" FontWeight="SemiBold" Foreground="{DynamicResource BrushDangerBg}"/>
                        <TextBlock Text="执行前需确认" Style="{StaticResource SilkLabel}" HorizontalAlignment="Right"/>
                    </DockPanel>
                    <Border Height="1" Background="{DynamicResource BrushBorderSoft}" Margin="0,0,0,7"/>

                    <Button Name="BtnClearApp" Style="{StaticResource DangerCmdButton}" ToolTip="清空目标应用的全部数据，执行前需要确认">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,8,0"><Path Data="{StaticResource IcoEraser}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="清空应用数据"/>
                        </StackPanel>
                    </Button>
                    <Grid Margin="0,1,0,1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button Grid.Column="0" Name="BtnKillApp" Style="{StaticResource DangerCmdButton}" Margin="0,2,3,2" ToolTip="强制结束目标应用进程">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,6,0"><Path Data="{StaticResource IcoStopOct}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="结束进程"/>
                            </StackPanel>
                        </Button>
                        <Button Grid.Column="1" Name="BtnUninstallApp" Style="{StaticResource DangerCmdButton}" Margin="3,2,0,2" ToolTip="卸载目标应用及其数据">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,6,0"><Path Data="{StaticResource IcoTrash}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="卸载应用"/>
                            </StackPanel>
                        </Button>
                    </Grid>
                </StackPanel>
            </Border>

            <!-- 列 2: 预设直接平铺，单击仅填入目标包名。 -->
            <Border Grid.Column="1" Background="{DynamicResource BrushPanelBg}" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="1" CornerRadius="8" Padding="14" Margin="6,0">
                <StackPanel>
                    <DockPanel Margin="1,0,1,4">
                        <Border Background="{DynamicResource BrushSignal}" CornerRadius="3" Padding="6,2" Margin="0,0,9,0">
                            <TextBlock Text="02" FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource BrushSignalText}"/>
                        </Border>
                        <TextBlock Text="应用预设" Style="{StaticResource SectionTitle}"/>
                        <TextBlock Text="PRESETS" Style="{StaticResource SilkLabel}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </DockPanel>
                    <TextBlock Text="单击填入目标，不会立即启动" Style="{StaticResource SectionHint}" Margin="1,0,0,10"/>
                    <Border Height="1" Background="{DynamicResource BrushBorderSoft}" Margin="0,0,0,8"/>

                    <Button Name="BtnPreset1" Style="{StaticResource PresetButton}" ToolTip="填入 com.one.bp_tracker">
                        <StackPanel>
                            <TextBlock Text="血压计" FontSize="11.5" FontWeight="SemiBold"/>
                            <TextBlock Text="com.one.bp_tracker" FontFamily="Consolas" FontSize="9" Foreground="{DynamicResource BrushTextMuted}" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Button>
                    <Button Name="BtnPreset2" Style="{StaticResource PresetButton}" ToolTip="填入 com.smartreader.simple.pdf">
                        <StackPanel>
                            <TextBlock Text="PDF 阅读器" FontSize="11.5" FontWeight="SemiBold"/>
                            <TextBlock Text="com.smartreader.simple.pdf" FontFamily="Consolas" FontSize="9" Foreground="{DynamicResource BrushTextMuted}" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Button>
                    <Button Name="BtnPreset3" Style="{StaticResource PresetButton}" ToolTip="填入 com.smartbar.qrcreator">
                        <StackPanel>
                            <TextBlock Text="橙色 QR" FontSize="11.5" FontWeight="SemiBold"/>
                            <TextBlock Text="com.smartbar.qrcreator" FontFamily="Consolas" FontSize="9" Foreground="{DynamicResource BrushTextMuted}" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Button>
                    <Button Name="BtnPreset4" Style="{StaticResource PresetButton}" ToolTip="填入 com.quickscan.qrcode">
                        <StackPanel>
                            <TextBlock Text="绿色 QR" FontSize="11.5" FontWeight="SemiBold"/>
                            <TextBlock Text="com.quickscan.qrcode" FontFamily="Consolas" FontSize="9" Foreground="{DynamicResource BrushTextMuted}" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Button>
                    <Button Name="BtnPreset5" Style="{StaticResource PresetButton}" ToolTip="填入 com.simplescan.qrcode.purple">
                        <StackPanel>
                            <TextBlock Text="紫色 QR" FontSize="11.5" FontWeight="SemiBold"/>
                            <TextBlock Text="com.simplescan.qrcode.purple" FontFamily="Consolas" FontSize="9" Foreground="{DynamicResource BrushTextMuted}" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Button>
                    <TextBlock Text="包名可在顶部继续编辑，回车即可打开。" Style="{StaticResource SectionHint}" Margin="2,10,0,0"/>
                </StackPanel>
            </Border>

            <!-- 列 3: 屏幕、文件与无线连接参数全部直接可见。 -->
            <Border Grid.Column="2" Background="{DynamicResource BrushPanelBg}" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="1" CornerRadius="8" Padding="14" Margin="6,0">
                <StackPanel>
                    <DockPanel Margin="1,0,1,4">
                        <Border Background="{DynamicResource BrushSignal}" CornerRadius="3" Padding="6,2" Margin="0,0,9,0">
                            <TextBlock Text="03" FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource BrushSignalText}"/>
                        </Border>
                        <TextBlock Text="设备与连接" Style="{StaticResource SectionTitle}"/>
                        <TextBlock Text="DEVICE" Style="{StaticResource SilkLabel}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </DockPanel>
                    <TextBlock Text="文件、镜像、屏幕与无线调试" Style="{StaticResource SectionHint}" Margin="1,0,0,10"/>
                    <Border Height="1" Background="{DynamicResource BrushBorderSoft}" Margin="0,0,0,10"/>

                    <Button Name="BtnOpenFileManager" Style="{StaticResource HighlightGoButton}" ToolTip="打开远程文件管理器，支持拖放导入与批量导出">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,8,0"><Path Data="{StaticResource IcoFolder}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="远程文件管理"/>
                        </StackPanel>
                    </Button>
                    <Button Name="BtnStartMirror" Style="{StaticResource HighlightSignalButton}" ToolTip="通过 Scrcpy 启动屏幕镜像；可直接拖入 .apk 文件安装">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,8,0"><Path Data="{StaticResource IcoMonitor}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="启动屏幕镜像"/>
                        </StackPanel>
                    </Button>
                    <Grid Margin="0,1,0,1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button Grid.Column="0" Name="BtnTurnOffCurrent" Style="{StaticResource FlatCmdButton}" Margin="0,2,3,2" ToolTip="熄灭当前设备屏幕并保持调试控制">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,6,0"><Path Data="{StaticResource IcoMoon}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="熄灭当前屏"/>
                            </StackPanel>
                        </Button>
                        <Button Grid.Column="1" Name="BtnTurnOffAll" Style="{StaticResource FlatCmdButton}" Margin="3,2,0,2" ToolTip="熄灭所有已连接设备的屏幕">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,6,0"><Path Data="{StaticResource IcoMoon}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="熄灭所有屏"/>
                            </StackPanel>
                        </Button>
                    </Grid>

                    <Border Height="1" Background="{DynamicResource BrushBorderSoft}" Margin="0,12,0,10"/>
                    <Grid Margin="0,0,0,7">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="2*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0" Margin="0,0,5,0">
                            <TextBlock Text="无线 IP（留空自动获取）" Style="{StaticResource FieldLabel}"/>
                            <TextBox Name="TxtWirelessIp" Height="34" VerticalContentAlignment="Center" ToolTip="设备 IP；留空时自动读取当前设备 IP"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1" Margin="5,0,0,0">
                            <TextBlock Text="端口" Style="{StaticResource FieldLabel}"/>
                            <TextBox Name="TxtWirelessPort" Text="5555" Height="34" VerticalContentAlignment="Center" ToolTip="无线调试端口，默认 5555"/>
                        </StackPanel>
                    </Grid>
                    <Button Name="BtnEnableWireless" Style="{StaticResource FlatCmdButton}" ToolTip="设置无线调试端口并连接指定设备">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,8,0"><Path Data="{StaticResource IcoWifi}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="开启并连接无线调试"/>
                        </StackPanel>
                    </Button>
                </StackPanel>
            </Border>

            <!-- 列 4: 日期、时间、日志、商店和网址均无需弹窗输入。 -->
            <Border Grid.Column="3" Background="{DynamicResource BrushPanelBg}" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="1" CornerRadius="8" Padding="14" Margin="6,0,0,0">
                <StackPanel>
                    <DockPanel Margin="1,0,1,4">
                        <Border Background="{DynamicResource BrushSignal}" CornerRadius="3" Padding="6,2" Margin="0,0,9,0">
                            <TextBlock Text="04" FontFamily="Consolas" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource BrushSignalText}"/>
                        </Border>
                        <TextBlock Text="时间与工具" Style="{StaticResource SectionTitle}"/>
                        <TextBlock Text="TOOLS" Style="{StaticResource SilkLabel}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </DockPanel>
                    <TextBlock Text="时间校准、日志、商店与网页" Style="{StaticResource SectionHint}" Margin="1,0,0,10"/>
                    <Border Height="1" Background="{DynamicResource BrushBorderSoft}" Margin="0,0,0,9"/>

                    <Button Name="BtnRestoreAutoTime" Style="{StaticResource FlatCmdButton}" ToolTip="恢复网络自动时间并对齐主机时间">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,8,0"><Path Data="{StaticResource IcoClockReset}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="恢复网络自动时间"/>
                        </StackPanel>
                    </Button>

                    <Grid Margin="0,6,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1.35*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0" Margin="0,0,5,0">
                            <TextBlock Text="日期（YYYY-MM-DD）" Style="{StaticResource FieldLabel}"/>
                            <TextBox Name="TxtDeviceDate" Height="32" VerticalContentAlignment="Center" FontFamily="Consolas" ToolTip="完整日期，用于修改设备完整时间"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1" Margin="5,0,0,0">
                            <TextBlock Text="时间（HH:mm）" Style="{StaticResource FieldLabel}"/>
                            <TextBox Name="TxtDeviceTime" Height="32" VerticalContentAlignment="Center" FontFamily="Consolas" ToolTip="24 小时制时间，例如 14:30"/>
                        </StackPanel>
                    </Grid>
                    <Grid Margin="0,1,0,1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button Grid.Column="0" Name="BtnSetTodayTime" Style="{StaticResource FlatCmdButton}" Margin="0,2,3,2" ToolTip="保留设备当前日期，仅修改为上方时间">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,5,0"><Path Data="{StaticResource IcoClock}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="修改当天时间"/>
                            </StackPanel>
                        </Button>
                        <Button Grid.Column="1" Name="BtnSetFullTime" Style="{StaticResource FlatCmdButton}" Margin="3,2,0,2" ToolTip="按上方日期和时间修改设备完整时间">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,5,0"><Path Data="{StaticResource IcoCalendar}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="修改完整时间"/>
                            </StackPanel>
                        </Button>
                    </Grid>

                    <Grid Margin="0,1,0,1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button Grid.Column="0" Name="BtnAppLog" Style="{StaticResource FlatCmdButton}" Margin="0,2,3,2" ToolTip="采集目标应用的 PID 专属日志">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,5,0"><Path Data="{StaticResource IcoFileText}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="应用日志"/>
                            </StackPanel>
                        </Button>
                        <Button Grid.Column="1" Name="BtnGlobalLog" Style="{StaticResource FlatCmdButton}" Margin="3,2,0,2" ToolTip="采集系统全局 Logcat 日志">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,5,0"><Path Data="{StaticResource IcoGlobe}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="全局日志"/>
                            </StackPanel>
                        </Button>
                    </Grid>

                    <Grid Margin="0,1,0,1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button Grid.Column="0" Name="BtnOpenPlayStore" Style="{StaticResource FlatCmdButton}" Margin="0,2,3,2" ToolTip="在设备上打开 Play 商店">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,5,0"><Path Data="{StaticResource IcoBag}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="打开 Play"/>
                            </StackPanel>
                        </Button>
                        <Button Grid.Column="1" Name="BtnClearPlayCache" Style="{StaticResource FlatCmdButton}" Margin="3,2,0,2" ToolTip="清除 Play 商店缓存">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,5,0"><Path Data="{StaticResource IcoDatabase}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="清 Play 缓存"/>
                            </StackPanel>
                        </Button>
                    </Grid>

                    <TextBlock Text="网页链接" Style="{StaticResource FieldLabel}" Margin="1,7,0,5"/>
                    <Grid Margin="0,0,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox Grid.Column="0" Name="TxtBrowserUrl" Text="https://" Height="34" VerticalContentAlignment="Center" ToolTip="输入要在设备浏览器中打开的网址"/>
                        <Button Grid.Column="1" Name="BtnOpenBrowserUrl" Style="{StaticResource FlatCmdButton}" Height="34" Margin="6,0,0,0" ToolTip="在设备默认浏览器中打开上方链接">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,5,0"><Path Data="{StaticResource IcoLink}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="打开链接"/>
                            </StackPanel>
                        </Button>
                    </Grid>
                    <Button Name="BtnClearPlayData" Style="{StaticResource DangerCmdButton}" ToolTip="清除 Play 商店全部应用数据，执行前需要确认">
                        <StackPanel Orientation="Horizontal">
                            <Viewbox Width="14" Height="14" Margin="0,0,8,0"><Path Data="{StaticResource IcoAlert}" Style="{StaticResource IcoPath}"/></Viewbox>
                            <TextBlock Text="清除 Play 商店数据"/>
                        </StackPanel>
                    </Button>
                </StackPanel>
            </Border>
        </Grid>

        <!-- ═══════════════ Row 2: 可拖拽分割条 ═══════════════ -->
        <GridSplitter Grid.Row="2" HorizontalAlignment="Stretch" ResizeDirection="Rows"/>

        <!-- Row 3: 集中反馈区，所有命令结果统一显示。 -->
        <Border Grid.Row="3" Background="{DynamicResource BrushPanelBg}" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="0,1,0,0">
            <Grid Margin="20,9,20,14">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <DockPanel Grid.Row="0" Margin="0,0,0,8">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Border Width="4" Height="16" Background="{DynamicResource BrushSignal}" CornerRadius="2" Margin="0,0,8,0"/>
                        <TextBlock Text="运行日志" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource BrushTextPrimary}" VerticalAlignment="Center"/>
                        <TextBlock Text="操作结果与错误信息集中反馈" Style="{StaticResource SectionHint}" Margin="12,0,0,0" VerticalAlignment="Center"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" DockPanel.Dock="Right">
                        <Button Name="BtnCopyLog" Style="{StaticResource HeaderThemeButton}" Height="30" Margin="0,0,8,0" ToolTip="复制全部运行日志">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,6,0"><Path Data="{StaticResource IcoCopy}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="复制日志"/>
                            </StackPanel>
                        </Button>
                        <Button Name="BtnClearLog" Style="{StaticResource HeaderThemeButton}" Height="30" ToolTip="清空当前日志显示">
                            <StackPanel Orientation="Horizontal">
                                <Viewbox Width="13" Height="13" Margin="0,0,6,0"><Path Data="{StaticResource IcoClear}" Style="{StaticResource IcoPath}"/></Viewbox>
                                <TextBlock Text="清空日志"/>
                            </StackPanel>
                        </Button>
                    </StackPanel>
                </DockPanel>
                <Border Grid.Row="1" Background="{DynamicResource BrushTerminalBg}" BorderBrush="{DynamicResource BrushBorderSoft}" BorderThickness="1" CornerRadius="6">
                    <TextBox Name="TxtLog" Background="Transparent" Foreground="{DynamicResource BrushTerminalText}"
                             FontFamily="Cascadia Mono, Consolas" FontSize="11.5"
                             BorderThickness="0" Padding="12,9" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                             IsReadOnly="True" AutomationProperties.Name="运行日志输出"/>
                </Border>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml.OuterXml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# 设置主窗口及任务栏图标
if ($global:AppIconBitmap) {
    try { $window.Icon = $global:AppIconBitmap } catch {}
}

# 主窗口默认使用浅色原生标题栏，主题切换时同步更新
$window.Add_SourceInitialized({
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
        [DwmThemeCustom]::SetTheme($helper.Handle, $false)
    } catch {}
})


# 获取 UI 控件
$cmbDevices = $window.FindName('CmbDevices')
$btnRefreshDevices = $window.FindName('BtnRefreshDevices')
$txtPackage = $window.FindName('TxtPackage')
$btnRefreshForeground = $window.FindName('BtnRefreshForeground')
$btnOpenApp = $window.FindName('BtnOpenApp')
$txtLog = $window.FindName('TxtLog')
$btnClearLog = $window.FindName('BtnClearLog')

$btnInstallApk = $window.FindName('BtnInstallApk')
$btnClearApp = $window.FindName('BtnClearApp')
$btnKillApp = $window.FindName('BtnKillApp')
$btnUninstallApp = $window.FindName('BtnUninstallApp')

$btnPreset1 = $window.FindName('BtnPreset1')
$btnPreset2 = $window.FindName('BtnPreset2')
$btnPreset3 = $window.FindName('BtnPreset3')
$btnPreset4 = $window.FindName('BtnPreset4')
$btnPreset5 = $window.FindName('BtnPreset5')

$btnOpenFileManager = $window.FindName('BtnOpenFileManager')
$btnStartMirror = $window.FindName('BtnStartMirror')
$btnTurnOffCurrent = $window.FindName('BtnTurnOffCurrent')
$btnTurnOffAll = $window.FindName('BtnTurnOffAll')
$btnEnableWireless = $window.FindName('BtnEnableWireless')
$btnEnableFirebase = $window.FindName('BtnEnableFirebase')
$btnDisableFirebase = $window.FindName('BtnDisableFirebase')

$btnAppLog = $window.FindName('BtnAppLog')
$btnGlobalLog = $window.FindName('BtnGlobalLog')
$btnSetTodayTime = $window.FindName('BtnSetTodayTime')
$btnSetFullTime = $window.FindName('BtnSetFullTime')
$btnRestoreAutoTime = $window.FindName('BtnRestoreAutoTime')
$btnOpenPlayStore = $window.FindName('BtnOpenPlayStore')
$btnClearPlayCache = $window.FindName('BtnClearPlayCache')
$btnClearPlayData = $window.FindName('BtnClearPlayData')
$btnOpenBrowserUrl = $window.FindName('BtnOpenBrowserUrl')

# 平铺参数控件：所有输入直接位于主窗口，不再依赖二级输入弹窗
$txtDeviceStatus = $window.FindName('TxtDeviceStatus')
$txtWirelessIp = $window.FindName('TxtWirelessIp')
$txtWirelessPort = $window.FindName('TxtWirelessPort')
$txtDeviceDate = $window.FindName('TxtDeviceDate')
$txtDeviceTime = $window.FindName('TxtDeviceTime')
$txtBrowserUrl = $window.FindName('TxtBrowserUrl')
$txtDeviceDate.Text = (Get-Date).ToString('yyyy-MM-dd')
$txtDeviceTime.Text = (Get-Date).ToString('HH:mm')

function Log([string]$msg) {
    $time = (Get-Date).ToString('HH:mm:ss')
    $txtLog.AppendText('[' + $time + '] ' + $msg + [Environment]::NewLine)
    $txtLog.ScrollToEnd()
}

function Get-CurrentSelectedDevice {
    return $cmbDevices.SelectedItem
}

function Refresh-DeviceList {
    $currentSerial = if ($cmbDevices.SelectedItem) { $cmbDevices.SelectedItem.Serial } else { $null }
    $devices = Get-Devices
    $cmbDevices.ItemsSource = $devices
    $cmbDevices.DisplayMemberPath = 'DisplayName'

    if ($devices.Count -gt 0) {
        $found = $null
        if ($currentSerial) {
            $found = $devices | Where-Object { $_.Serial -eq $currentSerial } | Select-Object -First 1
        }
        if ($found) {
            $cmbDevices.SelectedItem = $found
        } else {
            $cmbDevices.SelectedIndex = 0
        }
        $txtDeviceStatus.Text = ($devices.Count.ToString() + ' 台设备在线')
        Log ('已检测到 ' + $devices.Count + ' 台设备。')
    } else {
        $txtDeviceStatus.Text = '未检测到设备'
        $window.Title = 'DroidOps · Android 调试工作台'
        Log '未检测到已连接的 ADB 设备。'
    }
}

function Refresh-ForegroundApp {
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) {
        Log '请先选择设备！'
        return
    }
    $pkg = Get-ForegroundPackage $dev.Serial
    if ($pkg) {
        $txtPackage.Text = $pkg
        $ver = Get-AppVersion $dev.Serial $pkg
        Log ('已获取前台包名: ' + $pkg + ' (版本: ' + $ver + ')')
    } else {
        Log '未能获取当前设备前台包名。'
    }
}

# 绑定事件
$btnClearLog.Add_Click({ $txtLog.Clear() })

$btnCopyLog = $window.FindName('BtnCopyLog')
if ($btnCopyLog) {
    $btnCopyLog.Add_Click({
        if ($txtLog.Text) {
            [System.Windows.Clipboard]::SetText($txtLog.Text)
            Log '控制台日志已复制到系统剪贴板。'
        }
    })
}


$btnRefreshDevices.Add_Click({
    Refresh-DeviceList
})

$cmbDevices.Add_SelectionChanged({
    $dev = Get-CurrentSelectedDevice
    if ($dev) {
        $window.Title = $dev.Model + ' · ' + $dev.TypeStr + ' | DroidOps'
        $txtDeviceStatus.Text = $dev.TypeStr + ' · 已连接'
        Refresh-ForegroundApp
    }
})

$btnRefreshForeground.Add_Click({
    Refresh-ForegroundApp
})

# 包名输入框回车等效点击「打开应用」
$txtPackage.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        $btnOpenApp.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    }
})

$btnOpenApp.Add_Click({
    $dev = Get-CurrentSelectedDevice
    $pkg = $txtPackage.Text.Trim()
    if (-not $dev -or -not $pkg) { Log '请确保已选设备和有效包名！'; return }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell monkey -p ' + $pkg + ' -c android.intent.category.LAUNCHER 1')
    Log ('打开应用 ' + $pkg + ' -> ' + $ret.Output)
})

# ═══ 本地应用安装 (OpenFileDialog 多选 + ADB install) ═══
if ($btnInstallApk) {
    $btnInstallApk.Add_Click({
        $dev = Get-CurrentSelectedDevice
        if (-not $dev) {
            Log '请先选择设备！'
            return
        }

        $ofd = New-Object Microsoft.Win32.OpenFileDialog
        $ofd.Title = '选择要安装到设备的应用安装包 (支持多选批量安装)'
        $ofd.Filter = 'Android 安装包 (*.apk;*.xapk;*.apks)|*.apk;*.xapk;*.apks|所有文件 (*.*)|*.*'
        $ofd.Multiselect = $true

        if ($ofd.ShowDialog() -eq $true) {
            $files = $ofd.FileNames
            $total = $files.Count
            Log ('开始执行安装任务 (共 ' + $total + ' 个文件)...')

            foreach ($file in $files) {
                $baseName = [System.IO.Path]::GetFileName($file)
                Log ('正在向设备 [' + $dev.Model + '] 安装: ' + $baseName + ' ...')
                [System.Windows.Forms.Application]::DoEvents()

                # -r: 允许覆盖现有应用, -d: 允许降级安装, -t: 允许测试包安装
                $cmd = 'adb -s ' + $dev.Serial + ' install -r -d -t "' + $file + '"'
                $ret = Invoke-CmdText $cmd
                if ($ret.ExitCode -eq 0 -and ($ret.Output -match 'Success')) {
                    Log ('[安装成功] ' + $baseName)
                } else {
                    Log ('[安装反馈] ' + $baseName + ' -> ' + $ret.Output)
                }
            }
            Log '全部安装任务处理完毕。'
            Refresh-ForegroundApp
        }
    })
}

$btnClearApp.Add_Click({
    $dev = Get-CurrentSelectedDevice
    $pkg = $txtPackage.Text.Trim()
    if (-not $dev -or -not $pkg) { Log '请确保已选设备和有效包名！'; return }
    if (-not (Show-ConfirmDialog -message ('清空「' + $pkg + '」的全部应用数据，应用将恢复初始状态。') -actionText '清空数据' -owner $window)) { return }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell pm clear ' + $pkg)
    Log ('清空应用数据 -> ' + $ret.Output)
})

$btnKillApp.Add_Click({
    $dev = Get-CurrentSelectedDevice
    $pkg = $txtPackage.Text.Trim()
    if (-not $dev -or -not $pkg) { Log '请确保已选设备和有效包名！'; return }
    if (-not (Show-ConfirmDialog -message ('将强制结束「' + $pkg + '」的进程，应用未保存数据将丢失。') -actionText '结束进程' -owner $window)) { return }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell am force-stop ' + $pkg)
    Log ('杀死应用 -> ' + $ret.Output)
})

$btnUninstallApp.Add_Click({
    $dev = Get-CurrentSelectedDevice
    $pkg = $txtPackage.Text.Trim()
    if (-not $dev -or -not $pkg) { Log '请确保已选设备和有效包名！'; return }
    if (Show-ConfirmDialog -message ('将从设备 ' + $dev.Model + ' 卸载「' + $pkg + '」，应用及其数据将被移除。') -actionText '确认卸载' -owner $window) {
        $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' uninstall ' + $pkg)
        Log ('卸载应用 -> ' + $ret.Output)
        Refresh-ForegroundApp
    }
})

$btnPreset1.Add_Click({ $txtPackage.Text = $preset1; Log ('切换为预设: ' + $preset1) })
$btnPreset2.Add_Click({ $txtPackage.Text = $preset2; Log ('切换为预设: ' + $preset2) })
$btnPreset3.Add_Click({ $txtPackage.Text = $preset3; Log ('切换为预设: ' + $preset3) })
$btnPreset4.Add_Click({ $txtPackage.Text = $preset4; Log ('切换为预设: ' + $preset4) })
$btnPreset5.Add_Click({ $txtPackage.Text = $preset5; Log ('切换为预设: ' + $preset5) })

$btnOpenFileManager.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log "请先选择设备！"; return }
    Log ("正在打开文件管理器: " + $dev.DisplayName)
    Show-FileManagerWindow $dev
})

$btnStartMirror.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    $scrcpy = Get-ScrcpyPath
    if (-not $scrcpy) { Log '未找到 scrcpy 执行文件！'; return }
    Init-ScrcpyEnv
    $title = if ($dev.Model -and $dev.Model -ne 'unknown') { $dev.Model } else { $dev.Serial }
    $launch = Start-ScrcpyWindowProcess -ScrcpyPath $scrcpy -Serial $dev.Serial -WindowTitle $title
    if ($launch.Success) {
        Log ('手机镜像窗口已启动 (设备: ' + $title + ')')
        Log $launch.Message
    } else {
        Log ('启动镜像失败: ' + $launch.Message)
    }
})

$btnTurnOffCurrent.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    $res = TurnOff-DeviceScreen $dev.Serial
    if ($res.Success) {
        Log ('已熄灭设备屏幕 (保持调试控制): ' + $dev.DisplayName)
    } else {
        Log ('熄屏失败: ' + $res.Message)
    }
})

$btnTurnOffAll.Add_Click({
    $devices = Get-Devices
    if ($devices.Count -eq 0) { Log '未检测到已连接的设备！'; return }
    foreach ($d in $devices) {
        $res = TurnOff-DeviceScreen $d.Serial
        $statusStr = if ($res.Success) { '已熄屏保持控制' } else { '失败 - ' + $res.Message }
        Log ('[' + $d.Serial + ']: ' + $statusStr)
    }
})

$btnEnableWireless.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }

    $ip = $txtWirelessIp.Text.Trim()
    if (-not $ip) {
        $ip = Get-DeviceIp $dev.Serial
        if ($ip) { $txtWirelessIp.Text = $ip }
    }
    if (-not $ip) {
        Log '未能自动获取设备 IP，请直接在“无线 IP”输入框中填写后重试。'
        return
    }
    $parsedIp = $null
    if (-not [System.Net.IPAddress]::TryParse($ip, [ref]$parsedIp)) {
        Log '无线 IP 格式不正确，请输入例如 192.168.1.100 的地址。'
        return
    }

    $port = $txtWirelessPort.Text.Trim()
    $portNumber = 0
    if (-not [int]::TryParse($port, [ref]$portNumber) -or $portNumber -lt 1 -or $portNumber -gt 65535) {
        Log '无线调试端口不正确，请输入 1–65535 之间的数字。'
        return
    }

    $tcpipRes = (adb -s $dev.Serial tcpip $portNumber 2>&1 | Out-String).TrimEnd()
    Start-Sleep -Seconds 1
    $target = $ip + ':' + $portNumber
    $connectRes = (adb connect $target 2>&1 | Out-String).TrimEnd()
    Log ('设置端口 ' + $portNumber + ': ' + $tcpipRes)
    Log ('连接无线设备 ' + $target + ': ' + $connectRes)
    Refresh-DeviceList
})

$btnEnableFirebase.Add_Click({
    $dev = Get-CurrentSelectedDevice
    $pkg = $txtPackage.Text.Trim()
    if (-not $dev -or -not $pkg) { Log '请确保已选设备和有效包名！'; return }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell setprop debug.firebase.analytics.app ' + $pkg)
    Log ('开启 Firebase 调试 -> ' + $ret.Output)
})

$btnDisableFirebase.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell setprop debug.firebase.analytics.app .none.')
    Log ('关闭 Firebase 调试 -> ' + $ret.Output)
})

$btnAppLog.Add_Click({
    $dev = Get-CurrentSelectedDevice
    $pkg = $txtPackage.Text.Trim()
    if (-not $dev -or -not $pkg) { Log '请确保已选设备和有效包名！'; return }
    $pidResult = (adb -s $dev.Serial shell pidof -s $pkg 2>$null | Out-String).Trim()
    if (-not $pidResult -or $pidResult -match '\s') {
        Log '获取应用PID失败，请确保该应用正在运行！'
        return
    }
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $logDir = 'E:\workspace\data\log'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $ver = Get-AppVersion $dev.Serial $pkg
    $fileName = $dev.Model + '-' + $dev.OS + '-' + $pkg + '-' + $ver + '-' + $timestamp + '.txt'
    $logPath = Join-Path $logDir $fileName
    $windowTitle = if ($dev.Model -and $dev.Model -ne 'unknown') { $dev.Model + ' - APP日志' } else { $dev.Serial + ' - APP日志' }
    $logCmd = 'adb -s ' + $dev.Serial + ' logcat -c && adb -s ' + $dev.Serial + ' logcat --pid=' + $pidResult + ' -v time > "' + $logPath + '"'
    Start-Process cmd -ArgumentList '/k', ('title ' + $windowTitle + ' & echo 日志正在写入: ' + $logPath + ' & echo 按 Ctrl+C 停止日志采集... & ' + $logCmd)
    Log ('应用日志采集已在新窗口启动: ' + $logPath)
})

$btnGlobalLog.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $logDir = 'E:\workspace\data\log'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $pkg = $txtPackage.Text.Trim()
    $ver = if ($pkg) { Get-AppVersion $dev.Serial $pkg } else { 'unknown' }
    $fileName = $dev.Model + '-' + $dev.OS + '-' + $pkg + '-' + $ver + '-' + $timestamp + '-logcat.txt'
    $logPath = Join-Path $logDir $fileName
    $windowTitle = if ($dev.Model -and $dev.Model -ne 'unknown') { $dev.Model + ' - 全局日志' } else { $dev.Serial + ' - 全局日志' }
    $logCmd = 'adb -s ' + $dev.Serial + ' logcat -c && adb -s ' + $dev.Serial + ' logcat -v time > "' + $logPath + '"'
    Start-Process cmd -ArgumentList '/k', ('title ' + $windowTitle + ' & echo 全局日志正在写入: ' + $logPath + ' & echo 按 Ctrl+C 停止日志采集... & ' + $logCmd)
    Log ('全局日志采集已在新窗口启动: ' + $logPath)
})

$btnSetTodayTime.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    $t = $txtDeviceTime.Text.Trim()
    if ($t -notmatch '^(?:[01]\d|2[0-3]):[0-5]\d$') {
        Log '时间格式不正确，请在主窗口使用 HH:mm 格式，例如 14:30。'
        return
    }

    $hour = $t.Substring(0,2)
    $minute = $t.Substring(3,2)
    $md = (adb -s $dev.Serial shell date +%m%d 2>$null | Out-String).Trim()
    $year = (adb -s $dev.Serial shell date +%Y 2>$null | Out-String).Trim()
    if ($md.Length -ne 4 -or -not $year) { Log '获取设备日期失败。'; return }
    $month = $md.Substring(0,2)
    $day = $md.Substring(2,2)

    $res = Set-DeviceTime -serial $dev.Serial -year $year -month $month -day $day -hour $hour -minute $minute
    Log $res.Message
})

$btnSetFullTime.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    $dateText = $txtDeviceDate.Text.Trim()
    $timeText = $txtDeviceTime.Text.Trim()
    if ($dateText -notmatch '^\d{4}-\d{2}-\d{2}$' -or $timeText -notmatch '^(?:[01]\d|2[0-3]):[0-5]\d$') {
        Log '日期或时间格式不正确，请使用 YYYY-MM-DD 与 HH:mm 格式。'
        return
    }

    try {
        $dt = [DateTime]::ParseExact(($dateText + ' ' + $timeText), 'yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        Log '日期无效，请检查月份、日期与时间后重试。'
        return
    }

    $res = Set-DeviceTime -serial $dev.Serial -year $dt.ToString('yyyy') -month $dt.ToString('MM') -day $dt.ToString('dd') -hour $dt.ToString('HH') -minute $dt.ToString('mm')
    Log $res.Message
})

function Restore-AutoTime([string]$serial) {
    # 1. 开启系统网络与基站自动确定时间/时区
    adb -s $serial shell "cmd time_detector set_auto_detection_enabled true" 2>$null
    adb -s $serial shell "settings put global auto_time 1" 2>$null
    adb -s $serial shell "settings put global auto_time_zone 1" 2>$null

    # 2. 清理先前注入的手动时间缓存
    adb -s $serial shell "cmd time_detector clear_system_clock_network_time" 2>$null
    adb -s $serial shell "cmd time_detector clear_network_time" 2>$null

    # 3. 立即将电脑主机的当前精确时间通过 suggest_network_time 注入设备，实现秒级校准同步
    try {
        $uptimeStr = (adb -s $serial shell "cat /proc/uptime" 2>$null | Out-String).Trim()
        if ($uptimeStr) {
            $uptimeSec = $uptimeStr.Split(' ')[0]
            $elapsedMillis = [int64]([double]$uptimeSec * 1000)
            $nowEpochMs = [int64](([DateTimeOffset]::UtcNow).ToUnixTimeMilliseconds())
            adb -s $serial shell "cmd time_detector suggest_network_time --elapsed_realtime $elapsedMillis --unix_epoch_time $nowEpochMs --uncertainty_millis 10" 2>$null
        }
    } catch {}

    Start-Sleep -Milliseconds 600
    $curDate = (adb -s $serial shell date 2>$null | Out-String).Trim()
    return @{ Success = $true; Message = "已成功校准恢复为网络真实时间，并开启系统自动确定时间！`r`n当前设备时间: $curDate" }
}

$btnRestoreAutoTime.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    $res = Restore-AutoTime $dev.Serial
    Log $res.Message
})

$btnOpenPlayStore.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell monkey -p ' + $playStorePackage + ' -c android.intent.category.LAUNCHER 1')
    Log ('打开 Play Store -> ' + $ret.Output)
})

$btnClearPlayCache.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell pm trim-caches 16G')
    if ($ret.ExitCode -eq 0) {
        Log '清除 Play Store 缓存成功。'
    } else {
        $ret2 = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell su -c "rm -rf /data/data/com.android.vending/cache/* /data/user/0/com.android.vending/cache/* /cache/*com.android.vending*"')
        Log ('su 清除 Play Store 缓存 -> ' + $ret2.Output)
    }
})

$btnClearPlayData.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    if (-not (Show-ConfirmDialog -message '将清除 Play Store 全部应用数据，需重新登录 Google 账号。' -actionText '清除数据' -owner $window)) { return }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell pm clear ' + $playStorePackage)
    Log ('清除 Play Store 应用数据 -> ' + $ret.Output)
})

$btnOpenBrowserUrl.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    $url = $txtBrowserUrl.Text.Trim()
    if (-not $url -or $url -eq 'https://' -or $url -eq 'http://') {
        Log '请先在主窗口“网页链接”输入框中填写网址。'
        return
    }
    if ($url -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $url = 'https://' + $url }
    $uri = $null
    if (-not [System.Uri]::TryCreate($url, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https')) {
        Log '网址格式不正确，目前支持 http 与 https 链接。'
        return
    }
    $txtBrowserUrl.Text = $uri.AbsoluteUri
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell am start -a android.intent.action.VIEW -d "' + $uri.AbsoluteUri + '"')
    Log ('浏览器打开链接 -> ' + $ret.Output)
})

# ═══ 双主题调色板：默认浅色工业风，可切换深色 ═══
$script:CurrentTheme = 'light'
$script:ThemePalette = @{
    dark = @{
        BrushWindowBg       = '#111410'
        BrushPanelBg        = '#191D18'
        BrushPanelHeaderBg  = '#1E231D'
        BrushInputBg        = '#22281F'
        BrushInputHoverBg   = '#2A3127'
        BrushDropdownBg     = '#1D221C'
        BrushBorderSoft     = '#323A2F'
        BrushBorderStrong   = '#4A5645'
        BrushTextPrimary    = '#ECEFE7'
        BrushTextSecondary  = '#B2BAAC'
        BrushTextMuted      = '#899381'
        BrushBtnBg          = '#22281F'
        BrushBtnHoverBg     = '#2A3127'
        BrushSignal         = '#D16A3C'
        BrushSignalHover    = '#E07B4D'
        BrushSignalText     = '#17130F'
        BrushGoBg           = '#2F7D57'
        BrushGoHover        = '#3B9167'
        BrushDangerBg       = '#D36B63'
        BrushDangerHover    = '#B94B45'
        BrushItemHoverBg    = '#38271E'
        BrushItemHoverText  = '#F0A17D'
        BrushItemSelectedBg = '#463024'
        BrushItemSelectedText = '#F0A17D'
        BrushTerminalBg     = '#0D100C'
        BrushTerminalText   = '#DCE3D6'
    }
    light = @{
        BrushWindowBg       = '#F2F3EF'
        BrushPanelBg        = '#FBFCF9'
        BrushPanelHeaderBg  = '#F5F6F2'
        BrushInputBg        = '#FDFEFB'
        BrushInputHoverBg   = '#F0F2EC'
        BrushDropdownBg     = '#FDFEFB'
        BrushBorderSoft     = '#D8DDD4'
        BrushBorderStrong   = '#B8C1B4'
        BrushTextPrimary    = '#20261F'
        BrushTextSecondary  = '#4E5A4C'
        BrushTextMuted      = '#6E786A'
        BrushBtnBg          = '#F4F6F1'
        BrushBtnHoverBg     = '#E9EDE5'
        BrushSignal         = '#B84A24'
        BrushSignalHover    = '#963B1C'
        BrushSignalText     = '#FFFDF8'
        BrushGoBg           = '#276A4D'
        BrushGoHover        = '#1E563D'
        BrushDangerBg       = '#A63B36'
        BrushDangerHover    = '#87302C'
        BrushItemHoverBg    = '#F6E8DF'
        BrushItemHoverText  = '#8E371B'
        BrushItemSelectedBg = '#EFDCCF'
        BrushItemSelectedText = '#853316'
        BrushTerminalBg     = '#20261F'
        BrushTerminalText   = '#E6EADF'
    }
}

function Apply-AppTheme([string]$themeName) {
    $script:CurrentTheme = $themeName
    $isDark = ($themeName -eq 'dark')
    $palette = $script:ThemePalette[$themeName]

    foreach ($key in $palette.Keys) {
        $c = [System.Windows.Media.ColorConverter]::ConvertFromString($palette[$key])
        $brush = New-Object System.Windows.Media.SolidColorBrush($c)
        $brush.Freeze()
        $window.Resources.Remove($key)
        $window.Resources.Add($key, $brush)
    }

    $txtThemeBtn = $window.FindName('TxtThemeBtn')
    $icoThemePath = $window.FindName('IcoThemePath')
    if ($txtThemeBtn) {
        if ($isDark) {
            $txtThemeBtn.Text = '浅色模式'
        } else {
            $txtThemeBtn.Text = '深色模式'
        }
    }
    if ($icoThemePath) {
        if ($isDark) {
            $icoThemePath.Data = [System.Windows.Media.Geometry]::Parse('M12 2v2 M12 20v2 M4.93 4.93l1.41 1.41 M17.66 17.66l1.41 1.41 M2 12h2 M20 12h2 M6.34 17.66l-1.41 1.41 M19.07 4.93l-1.41 1.41 M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10z')
        } else {
            $icoThemePath.Data = [System.Windows.Media.Geometry]::Parse('M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z')
        }
    }

    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
        if ([bool]([System.Type]::GetType('DwmThemeCustom'))) {
            [DwmThemeCustom]::SetTheme($helper.Handle, $isDark)
        } elseif ([bool]([System.Type]::GetType('DwmTheme'))) {
            if ($isDark) { [DwmTheme]::EnableDark($helper.Handle) }
        }
    } catch {}
}

$btnToggleTheme = $window.FindName('BtnToggleTheme')
if ($btnToggleTheme) {
    $btnToggleTheme.Add_Click({
        $next = 'light'
        $label = '浅色模式 (Light)'
        if ($script:CurrentTheme -ne 'dark') {
            $next = 'dark'
            $label = '深色模式 (Dark)'
        }
        Apply-AppTheme $next
        Log ('已切换界面主题为: ' + $label)
    })
}

# 初始化加载
if (Test-IsProcessElevated) {
    Log '当前工具以管理员权限运行；镜像窗口将自动通过标准桌面权限启动，以保留 APK 拖放安装。'
}
Refresh-DeviceList
$window.ShowDialog() | Out-Null
