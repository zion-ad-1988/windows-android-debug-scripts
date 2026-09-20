$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$preset1 = 'com.one.bp_tracker'
$preset2 = 'com.smartreader.simple.pdf'
$preset3 = 'com.smartbar.qrcreator'
$preset4 = 'com.quickscan.qrcode'
$preset5 = 'com.simplescan.qrcode.purple'
$playStorePackage = 'com.android.vending'
$statusMessage = ''

function Set-Status([string]$message) {
    $script:statusMessage = $message
}

function Set-CommandStatus([string]$commandText, [string]$resultText) {
    if (-not $resultText -or -not $resultText.Trim()) {
        $resultText = '(无输出)'
    }
    $script:statusMessage = "命令:`r`n$commandText`r`n`r`n结果:`r`n$resultText"
}

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
            $obj = New-Object PSObject
            Add-Member -InputObject $obj -NotePropertyName Serial -NotePropertyValue $serial
            Add-Member -InputObject $obj -NotePropertyName Model -NotePropertyValue $model
            Add-Member -InputObject $obj -NotePropertyName OS -NotePropertyValue $os
            $result += $obj
        }
    }
    return ,$result
}

function Update-ConsoleTitle($device) {
    if (-not $device) { return }
    $connType = if ($device.Serial -match '^\d+\.\d+\.\d+\.\d+:\d+$') { ' - 无线' } else { ' - 有线' }
    $titleModel = if ($device.Model -and $device.Model -ne 'unknown') { $device.Model } else { $device.Serial }
    $host.UI.RawUI.WindowTitle = "$titleModel$connType"
}

function Select-Device {
    while ($true) {
        Clear-Host
        Write-Host '=============================================='
        Write-Host '正在读取ADB设备...'
        Write-Host '=============================================='
        $devices = Get-Devices
        if ($devices.Count -eq 0) {
            Write-Host '没有可用的ADB设备。'
            continue
        }

        for ($i = 0; $i -lt $devices.Count; $i++) {
            $d = $devices[$i]
            Write-Host ((($i + 1).ToString()) + '. ' + $d.Serial + ' [型号: ' + $d.Model + ' | 安卓: ' + $d.OS + ']')
        }
        Write-Host ''

        if ($devices.Count -eq 1) {
            Write-Host '只检测到1台设备，已自动选择：'
            Update-ConsoleTitle $devices[0]
            return $devices[0]
        }

        $choice = Read-Host ('选设备 (1-' + $devices.Count + ')')
        if ($choice -match '^\d+$') {
            $index = [int]$choice - 1
            if ($index -ge 0 -and $index -lt $devices.Count) {
                Update-ConsoleTitle $devices[$index]
                return $devices[$index]
            }
        }
        Write-Host '输入无效。'
    }
}

function Get-ForegroundPackage([string]$serial) {
    # 优先使用你设备生效的 mFocusedApp（最稳定）
    $lines = if ($serial) { adb -s $serial shell dumpsys window 2>$null } else { adb shell dumpsys window 2>$null }
    foreach ($line in $lines) {
        # 正则精准匹配 mFocusedApp 并提取包名
        if ($line -match 'mFocusedApp.*?\s([\w\.]+)/') {
            return $matches[1]
        }
    }

    # 兜底兼容：通用前台Activity匹配（全安卓版本）
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

function Choose-Package {
    while ($true) {
        Clear-Host
        Write-Host '=============================================='
        Write-Host '选择包名'
        Write-Host '=============================================='
        Write-Host ('1. 血压计：' + $preset1)
        Write-Host ('2. PDF：' + $preset2)
        Write-Host ('3. 橙色QR：' + $preset3)
        Write-Host ('4. 绿色QR：' + $preset4)
        Write-Host ('5. 紫色QR：' + $preset5)
        Write-Host '6. 手动输入'
        Write-Host '=============================================='
        $choice = Read-Host '请输入 (1-6)'
        
        if ($choice -eq '1') { return $preset1 }
        if ($choice -eq '2') { return $preset2 }
        if ($choice -eq '3') { return $preset3 }
        if ($choice -eq '4') { return $preset4 }
        if ($choice -eq '5') { return $preset5 }
        
        if ($choice -eq '6') {
            $manual = Read-Host '输入包名'
            if ($manual) { return $manual }
            Write-Host '包名不能为空。'
            continue
        }
        Write-Host '输入无效。'
    }
}

function Set-DeviceTime([string]$serial, [string]$year, [string]$month, [string]$day, [string]$hour, [string]$minute) {
    try {
        $dt = [DateTime]::ParseExact(($year + '-' + $month + '-' + $day + ' ' + $hour + ':' + $minute + ':00'), 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return @{ Success = $false; Message = '时间解析错误' }
    }

    # 方式1：原生系统级 cmd time_detector suggest_network_time (Android 8+，免Root免Shizuku，全版本通用)
    try {
        adb -s $serial shell "cmd time_detector set_auto_detection_enabled true" 2>$null
        adb -s $serial shell "settings put global auto_time 1" 2>$null

        $uptimeStr = (adb -s $serial shell "cat /proc/uptime" 2>$null | Out-String).Trim()
        if ($uptimeStr) {
            $uptimeSec = $uptimeStr.Split(' ')[0]
            $elapsedMillis = [int64]([double]$uptimeSec * 1000)
            $targetEpochMs = [int64](([DateTimeOffset]::new($dt)).ToUnixTimeMilliseconds())

            $res = (adb -s $serial shell "cmd time_detector suggest_network_time --elapsed_realtime $elapsedMillis --unix_epoch_time $targetEpochMs --uncertainty_millis 10" 2>&1 | Out-String).Trim()
            
            # 锁定时间防止自动同步
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

function Set-Full-Time([string]$serial) {
    $t = Read-Host '输入时间 (YYYYMMDDHHMM)'
    if ($t -notmatch '^\d{12}$') {
        Set-Status '格式错误。'
        return
    }
    $year = $t.Substring(0,4)
    $month = $t.Substring(4,2)
    $day = $t.Substring(6,2)
    $hour = $t.Substring(8,2)
    $minute = $t.Substring(10,2)

    $res = Set-DeviceTime -serial $serial -year $year -month $month -day $day -hour $hour -minute $minute
    Set-CommandStatus "修改完整时间 ($t)" $res.Message
}

function Set-Today-Time([string]$serial) {
    $t = Read-Host '输入时间 (HHMM)'
    if ($t -notmatch '^\d{4}$') {
        Set-Status '格式错误。'
        return
    }
    $hour = $t.Substring(0,2)
    $minute = $t.Substring(2,2)
    $md = (adb -s $serial shell date +%m%d 2>$null | Out-String).Trim()
    $year = (adb -s $serial shell date +%Y 2>$null | Out-String).Trim()
    if ($md.Length -ne 4 -or -not $year) {
        Set-Status '获取设备日期失败。'
        return
    }
    $month = $md.Substring(0,2)
    $day = $md.Substring(2,2)

    $res = Set-DeviceTime -serial $serial -year $year -month $month -day $day -hour $hour -minute $minute
    Set-CommandStatus "修改当天时间 ($t)" $res.Message
}

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

function Reset-AutoTime([string]$serial) {
    $res = Restore-AutoTime $serial
    Set-CommandStatus "恢复自动时间" $res.Message
}

function Start-Logcat([string]$serial, [string]$model, [string]$os, [string]$pkg, [string]$version) {
    $pidResult = (adb -s $serial shell pidof -s $pkg 2>$null | Out-String).Trim()
    if (-not $pidResult -or $pidResult -match '\s') {
        Set-Status "获取PID失败，请确保应用正在运行。"
        return
    }
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $logDir = 'E:\workspace\data\log'
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $fileName = "$model-$os-$pkg-$version-$timestamp.txt"
    $logPath = Join-Path $logDir $fileName
    $windowTitle = if ($model -and $model -ne 'unknown') { "$model - APP日志" } else { "$serial - APP日志" }
    $logCmd = "adb -s $serial logcat -c && adb -s $serial logcat --pid=$pidResult -v time > `"$logPath`""
    Start-Process cmd -ArgumentList "/k", "title $windowTitle & echo 日志正在写入: $logPath & echo 按 Ctrl+C 停止日志采集... & $logCmd"
    Set-CommandStatus "logcat --pid=$pidResult" "日志采集已在新窗口启动，文件: $logPath"
}

function Start-GlobalLogcat([string]$serial, [string]$model, [string]$os, [string]$pkg, [string]$version) {
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $logDir = 'E:\workspace\data\log'
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $fileName = "$model-$os-$pkg-$version-$timestamp-logcat.txt"
    $logPath = Join-Path $logDir $fileName
    $windowTitle = if ($model -and $model -ne 'unknown') { "$model - 全局日志" } else { "$serial - 全局日志" }
    $logCmd = "adb -s $serial logcat -c && adb -s $serial logcat -v time > `"$logPath`""
    Start-Process cmd -ArgumentList "/k", "title $windowTitle & echo 全局日志正在写入: $logPath & echo 按 Ctrl+C 停止日志采集... & $logCmd"
    Set-CommandStatus "logcat" "全局日志采集已在新窗口启动，文件: $logPath"
}

function Clear-PlayStoreCache([string]$serial) {
    $cmd = 'adb -s ' + $serial + ' shell pm trim-caches 16G'
    $ret = Invoke-CmdText $cmd
    if ($ret.ExitCode -eq 0) {
        Set-CommandStatus $ret.Command $ret.Output
        return
    }

    $cmd = 'rm -rf /data/data/com.android.vending/cache/* /data/user/0/com.android.vending/cache/* /cache/*com.android.vending*'
    $ret = Invoke-CmdText ('adb -s ' + $serial + ' shell su -c "' + $cmd + '"')
    Set-CommandStatus $ret.Command $ret.Output
}

function Clear-PlayStoreData([string]$serial) {
    $cmd = 'adb -s ' + $serial + ' shell pm clear ' + $playStorePackage
    $ret = Invoke-CmdText $cmd
    Set-CommandStatus $ret.Command $ret.Output
}

function Open-PlayStore([string]$serial) {
    $cmd = 'adb -s ' + $serial + ' shell monkey -p ' + $playStorePackage + ' -c android.intent.category.LAUNCHER 1'
    $ret = Invoke-CmdText $cmd
    Set-CommandStatus $ret.Command $ret.Output
}

function Open-UrlInDefaultBrowser([string]$serial) {
    $url = (Read-Host '输入要打开的链接').Trim()
    if (-not $url) {
        Set-Status '链接不能为空。'
        return
    }
    if ($url -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $url = 'https://' + $url
    }
    $cmd = 'adb -s ' + $serial + ' shell am start -a android.intent.action.VIEW -d "' + $url + '"'
    $ret = Invoke-CmdText $cmd
    Set-CommandStatus $ret.Command $ret.Output
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

function Enable-WirelessDebug([string]$serial) {
    $ip = Get-DeviceIp $serial
    if (-not $ip) {
        $ip = (Read-Host '未能自动获取设备IP，请输入设备IP (如 192.168.x.x)').Trim()
        if (-not $ip) {
            Set-Status '未输入设备IP，已取消。'
            return
        }
    }

    $tcpipResult = (adb -s $serial tcpip 5555 2>&1 | Out-String).TrimEnd()
    Start-Sleep -Seconds 1
    $target = "$ip`:5555"
    $connectResult = (adb connect $target 2>&1 | Out-String).TrimEnd()

    $outputMsg = "1. 设置无线端口 (5555):`r`n   adb -s $serial tcpip 5555`r`n   $tcpipResult`r`n`r`n2. 连接无线调试设备:`r`n   adb connect $target`r`n   $connectResult`r`n`r`n提示: 当前操作设备未更换，已将 $target 挂载至 ADB，可在选项 6 中选择切换。"
    Set-Status $outputMsg
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

    # 优先使用与 scrcpy 处于同目录或内置相对目录的 scrcpy-server 和图标资源
    $serverPath = Join-Path $baseDir 'scrcpy-server'
    if (Test-Path $serverPath) {
        $env:SCRCPY_SERVER_PATH = $serverPath
    }

    $iconPath = Join-Path $baseDir 'scrcpy.png'
    if (Test-Path $iconPath) {
        $env:SCRCPY_ICON_DIR = $baseDir
    }
}

function TurnOff-DeviceScreen([string]$serial) {
    # 按照 Escrcpy helper 规范调用：
    # window.$preload.scrcpy.helper(device.id, '--turn-screen-off')
    # 即底层执行：scrcpy --serial="<serial>" --no-window --no-video --no-audio --turn-screen-off
    $scrcpy = Get-ScrcpyPath
    if (-not $scrcpy) {
        return @{ Success = $false; Message = '未找到 scrcpy 执行程序' }
    }

    Init-ScrcpyEnv

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $scrcpy
        $psi.Arguments = "--serial=`"$serial`" --no-window --no-video --no-audio --turn-screen-off"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = [System.Diagnostics.Process]::Start($psi)

        # 参照 Escrcpy resolveOnReady 监听机制：匹配到 ready 标记即代表指令下发成功
        $readyPattern = "(?:Renderer:|Texture:|\[server\]\s+INFO:\s+Device:|Device display turned off)"
        $isReady = $false
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        while ($sw.ElapsedMilliseconds -lt 6000 -and -not $proc.HasExited) {
            $line = $proc.StandardOutput.ReadLine()
            if ($line -and ($line -match $readyPattern)) {
                $isReady = $true
                break
            }
        }

        return @{ Success = $true; Message = "命令: scrcpy --serial=`"$serial`" --no-window --no-video --no-audio --turn-screen-off (已下发执行)" }
    } catch {
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

function TurnOff-CurrentScreen([string]$serial) {
    $res = TurnOff-DeviceScreen $serial
    if ($res.Success) {
        Set-CommandStatus "关闭屏幕 [$serial]" ("成功执行 Escrcpy 灭屏保持控制:`r`n" + $res.Message)
    } else {
        Set-CommandStatus "关闭屏幕 [$serial]" ("执行失败:`r`n" + $res.Message)
    }
}

function TurnOff-AllScreens {
    $devices = Get-Devices
    if ($devices.Count -eq 0) {
        Set-Status '没有已连接的设备。'
        return
    }

    $results = @()
    foreach ($d in $devices) {
        $res = TurnOff-DeviceScreen $d.Serial
        $results += "$($d.Serial): $(if ($res.Success) { '已下发灭屏' } else { '失败 - ' + $res.Message })"
    }

    $msg = "已执行所有设备的关闭屏幕保持控制:`r`n" + ($results -join "`r`n")
    Set-CommandStatus '关闭所有已连接设备屏幕' $msg
}

function Start-DeviceMirror([string]$serial, [string]$model) {
    # 迁移自 Escrcpy "shortcut.operation.mirror" (开始镜像):
    # window.$preload.scrcpy.mirror(deviceId, { title: deviceStore.getLabel(deviceId, 'mirror'), ... })
    # 手机镜像窗口标题命名为手机设备型号
    $scrcpy = Get-ScrcpyPath
    if (-not $scrcpy) {
        Set-Status '未找到 scrcpy 执行程序。'
        return
    }

    Init-ScrcpyEnv

    $title = if ($model -and $model -ne 'unknown') { $model } else { $serial }
    $argList = "--serial=`"$serial`" --window-title=`"$title`""

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $scrcpy
        $psi.Arguments = $argList
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        [System.Diagnostics.Process]::Start($psi) | Out-Null
        Set-CommandStatus "开始镜像 [$serial]" "镜像窗口已在前台启动（后台命令静默运行）:`r`nscrcpy $argList"
    } catch {
        Set-CommandStatus "开始镜像 [$serial]" ("启动镜像失败:`r`n" + $_.Exception.Message)
    }
}

$device = Select-Device
$package = Get-ForegroundPackage $device.Serial
if (-not $package) {
    Write-Host '获取前台包名失败。'
    exit 1
}

while ($true) {
    $version = Get-AppVersion $device.Serial $package
    Set-Content -Path (Join-Path $PSScriptRoot 'current_app.txt') -Value $package -Encoding UTF8

    Clear-Host
    if ($statusMessage) {
        Write-Host $statusMessage
        Write-Host '=============================================='
    }
    Write-Host '=============================================='
    Write-Host ('设备: ' + $device.Serial + ' [型号: ' + $device.Model + ' | 安卓: ' + $device.OS + ']')
    Write-Host ('应用: ' + $package + ' [版本: ' + $version + ']')
    Write-Host '=============================================='
    Write-Host '1. 清空应用数据'
    Write-Host '2. 打开应用'
    Write-Host '3. 刷新前台应用'
    Write-Host '4. 选择预设包名'
    Write-Host '5. 卸载当前应用'
    Write-Host '6. 重新选择设备'
    Write-Host '7. 开启Firebase调试'
    Write-Host '8. 关闭Firebase调试'
    Write-Host '9. 杀死当前应用'
    Write-Host '10. 设置当天时间 (HHMM)'
    Write-Host '11. 开启日志调试'
    Write-Host '12. 全局日志调试'
    Write-Host '13. 清除Play Store缓存'
    Write-Host '14. 清除Play Store应用数据'
    Write-Host '15. 打开Play Store'
    Write-Host '16. 默认浏览器打开链接'
    Write-Host '17. 设置完整时间 (YYYYMMDDHHMM)'
    Write-Host '18. 开启无线调试并连接 (端口5555)'
    Write-Host '19. 关闭当前手机屏幕 (保持调试)'
    Write-Host '20. 关闭所有手机屏幕 (保持调试)'
    Write-Host '21. 开始镜像当前手机 (Start Mirroring)'
    Write-Host '22. 恢复为网络自动时间'
    Write-Host '=============================================='

    $menu = Read-Host '请输入功能 (1-22)'

    if ($menu -eq '1') {
        $cmd = 'adb -s ' + $device.Serial + ' shell pm clear ' + $package
        $ret = Invoke-CmdText $cmd
        Set-CommandStatus $ret.Command $ret.Output
    } elseif ($menu -eq '2') {
        $cmd = 'adb -s ' + $device.Serial + ' shell monkey -p ' + $package + ' -c android.intent.category.LAUNCHER 1'
        $ret = Invoke-CmdText $cmd
        Set-CommandStatus $ret.Command $ret.Output
    } elseif ($menu -eq '3') {
        $newPkg = Get-ForegroundPackage $device.Serial
        if ($newPkg) {
            $package = $newPkg
            Set-CommandStatus '读取当前前台应用' ('当前包名: ' + $package)
        } else {
            Set-CommandStatus '读取当前前台应用' '获取前台包名失败。'
        }
    } elseif ($menu -eq '4') {
        $package = Choose-Package
        Set-CommandStatus '选择预设包名' ('已切换到: ' + $package)
    } elseif ($menu -eq '5') {
        $cmd = 'adb -s ' + $device.Serial + ' uninstall ' + $package
        $ret = Invoke-CmdText $cmd
        if ($ret.ExitCode -eq 0) {
            $newPkg = Get-ForegroundPackage $device.Serial
            if ($newPkg) { $package = $newPkg }
            Set-CommandStatus $ret.Command $ret.Output
        } else {
            Set-CommandStatus $ret.Command $ret.Output
        }
    } elseif ($menu -eq '6') {
        $device = Select-Device
        Update-ConsoleTitle $device
        $newPkg = Get-ForegroundPackage $device.Serial
        if ($newPkg) {
            $package = $newPkg
            Set-CommandStatus '重新选择设备' ('已切换设备: ' + $device.Serial)
        } else {
            Set-CommandStatus '重新选择设备' '获取前台包名失败。'
        }
    } elseif ($menu -eq '7') {
        $cmd = 'adb -s ' + $device.Serial + ' shell setprop debug.firebase.analytics.app ' + $package
        $ret = Invoke-CmdText $cmd
        Set-CommandStatus $ret.Command $ret.Output
    } elseif ($menu -eq '8') {
        $cmd = 'adb -s ' + $device.Serial + ' shell setprop debug.firebase.analytics.app .none.'
        $ret = Invoke-CmdText $cmd
        Set-CommandStatus $ret.Command $ret.Output
    } elseif ($menu -eq '9') {
        $cmd = 'adb -s ' + $device.Serial + ' shell am force-stop ' + $package
        $ret = Invoke-CmdText $cmd
        Set-CommandStatus $ret.Command $ret.Output
    } elseif ($menu -eq '10') {
        $statusMessage = ''
        Set-Today-Time $device.Serial
    } elseif ($menu -eq '11') {
        $statusMessage = ''
        Start-Logcat $device.Serial $device.Model $device.OS $package $version
    } elseif ($menu -eq '12') {
        $statusMessage = ''
        Start-GlobalLogcat $device.Serial $device.Model $device.OS $package $version
    } elseif ($menu -eq '13') {
        $statusMessage = ''
        Clear-PlayStoreCache $device.Serial
    } elseif ($menu -eq '14') {
        $statusMessage = ''
        Clear-PlayStoreData $device.Serial
    } elseif ($menu -eq '15') {
        $statusMessage = ''
        Open-PlayStore $device.Serial
    } elseif ($menu -eq '16') {
        $statusMessage = ''
        Open-UrlInDefaultBrowser $device.Serial
    } elseif ($menu -eq '17') {
        $statusMessage = ''
        Set-Full-Time $device.Serial
    } elseif ($menu -eq '18') {
        $statusMessage = ''
        Enable-WirelessDebug $device.Serial
    } elseif ($menu -eq '19') {
        $statusMessage = ''
        TurnOff-CurrentScreen $device.Serial
    } elseif ($menu -eq '20') {
        $statusMessage = ''
        TurnOff-AllScreens
    } elseif ($menu -eq '21') {
        $statusMessage = ''
        Start-DeviceMirror $device.Serial $device.Model
    } elseif ($menu -eq '22') {
        $statusMessage = ''
        Reset-AutoTime $device.Serial
    } else {
        Set-Status '输入无效。'
    }
}
