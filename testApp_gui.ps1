$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms

$preset1 = 'com.one.bp_tracker'
$preset2 = 'com.smartreader.simple.pdf'
$preset3 = 'com.smartbar.qrcreator'
$preset4 = 'com.quickscan.qrcode'
$preset5 = 'com.simplescan.qrcode.purple'
$playStorePackage = 'com.android.vending'

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

            $icon = if ($isDir) { "📁" } elseif ($isLink) { "🔗" } else { "📄" }
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
        Title="$($dev.Model) - 文件管理器 [$($dev.TypeStr)]" Height="680" Width="960"
        WindowStartupLocation="CenterScreen" Background="#F8FAFC"
        FontFamily="Segoe UI, Microsoft YaHei">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="Margin" Value="2"/>
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="Foreground" Value="#1E293B"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="8,0,8,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" 
                                BorderBrush="{TemplateBinding BorderBrush}" 
                                BorderThickness="{TemplateBinding BorderThickness}" 
                                CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#E2E8F0"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#CBD5E1"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- 快捷路径导航栏 -->
        <WrapPanel Grid.Row="0" Margin="0,0,0,6">
            <Button Name="NavUp" Content="⬅ 返回上级"/>
            <Button Name="NavRefresh" Content="🔄 刷新目录"/>
            <Button Name="NavSdcard" Content="🏠 内部存储 (/storage/emulated/0)"/>
            <Button Name="NavDocuments" Content="📄 文档 (Documents)"/>
            <Button Name="NavDownload" Content="📥 下载 (Download)"/>
            <Button Name="NavDCIM" Content="📷 相册 (DCIM)"/>
            <Button Name="NavPictures" Content="🖼 图片 (Pictures)"/>
            <Button Name="NavRoot" Content="📁 系统根目录 (/)"/>
        </WrapPanel>

        <!-- 路径输入栏与搜索筛选 -->
        <Grid Grid.Row="1" Margin="0,0,0,6">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="200"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="当前路径：" VerticalAlignment="Center" FontWeight="SemiBold" Margin="0,0,4,0" Foreground="#334155"/>
            <TextBox Grid.Column="1" Name="TxtCurrentPath" Height="30" VerticalContentAlignment="Center" Padding="6,0,6,0" FontSize="13" BorderBrush="#CBD5E1"/>
            <Button Grid.Column="2" Name="BtnGoPath" Content="前往" Width="55" Margin="4,0,8,0" Background="#2563EB" Foreground="#FFFFFF" BorderBrush="#1D4ED8"/>
            <TextBox Grid.Column="3" Name="TxtSearch" Height="30" VerticalContentAlignment="Center" Padding="6,0,6,0" FontSize="12" BorderBrush="#CBD5E1" ToolTip="输入关键字实时筛选当前目录"/>
        </Grid>

        <!-- 文件操作工具栏 -->
        <WrapPanel Grid.Row="2" Margin="0,0,0,6">
            <Button Name="BtnUpload" Content="📤 上传多选文件" Background="#F0FDF4" Foreground="#166534" BorderBrush="#BBF7D0"/>
            <Button Name="BtnDownload" Content="📥 批量导出到电脑" Background="#EFF6FF" Foreground="#1E40AF" BorderBrush="#BFDBFE"/>
            <Button Name="BtnNewFolder" Content="➕ 新建文件夹"/>
            <Button Name="BtnRename" Content="✏ 重命名"/>
            <Button Name="BtnDelete" Content="🗑 删除选中项" Background="#FEF2F2" Foreground="#991B1B" BorderBrush="#FECACA"/>
            <Button Name="BtnCopyPath" Content="📋 复制完整路径"/>
            <TextBlock Text="💡 支持电脑文件直接拖入导入，支持选中项拖出导出，支持 Ctrl/Shift/Ctrl+A 多选" FontSize="11" VerticalAlignment="Center" Margin="10,0,0,0" Foreground="#64748B"/>
        </WrapPanel>

        <!-- 文件列表 -->
        <ListView Grid.Row="3" Name="ListViewFiles" Background="#FFFFFF" BorderBrush="#CBD5E1" FontSize="12" SelectionMode="Extended" AllowDrop="True">
            <ListView.View>
                <GridView>
                    <GridViewColumn Header="类型" Width="50" DisplayMemberBinding="{Binding Icon}"/>
                    <GridViewColumn Header="名称" Width="400" DisplayMemberBinding="{Binding DisplayName}"/>
                    <GridViewColumn Header="大小" Width="120" DisplayMemberBinding="{Binding Size}"/>
                    <GridViewColumn Header="修改时间" Width="160" DisplayMemberBinding="{Binding Time}"/>
                    <GridViewColumn Header="权限" Width="140" DisplayMemberBinding="{Binding Perms}"/>
                </GridView>
            </ListView.View>
        </ListView>

        <!-- 底部状态栏 -->
        <Border Grid.Row="4" Background="#E2E8F0" CornerRadius="4" Padding="10,6,10,6" Margin="0,6,0,0">
            <TextBlock Name="TxtStatusBar" Text="正在读取目录..." FontSize="12" Foreground="#475569"/>
        </Border>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($explorerXaml))
    $explorerWin = [System.Windows.Markup.XamlReader]::Load($reader)

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
        $sel = $script:fmListView.SelectedItem
        if (-not $sel) {
            [System.Windows.MessageBox]::Show("请先选择要删除的项！", "提示", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }
        $cfm = [System.Windows.MessageBox]::Show("确定要删除「$($sel.Name)」吗？`n此操作不可恢复！", "删除确认", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($cfm -eq [System.Windows.MessageBoxResult]::Yes) {
            $targetP = if ($script:fmPath -eq '/') { '/' + $sel.Name } else { $script:fmPath.TrimEnd('/') + '/' + $sel.Name }
            adb -s $script:fmDevice.Serial shell rm -rf (Escape-ShellPath $targetP) | Out-Null
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
        Title="Android 设备调试与控制控制台" Height="780" Width="1020"
        WindowStartupLocation="CenterScreen" Background="#F1F5F9"
        FontFamily="Segoe UI, Microsoft YaHei">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Height" Value="38"/>
            <Setter Property="Margin" Value="4,4,4,4"/>
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="Foreground" Value="#1E293B"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" 
                                BorderBrush="{TemplateBinding BorderBrush}" 
                                BorderThickness="{TemplateBinding BorderThickness}" 
                                CornerRadius="6" Padding="10,0,10,0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#E2E8F0"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#94A3B8"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#CBD5E1"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#2563EB"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#1D4ED8"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" 
                                BorderBrush="{TemplateBinding BorderBrush}" 
                                BorderThickness="{TemplateBinding BorderThickness}" 
                                CornerRadius="6" Padding="10,0,10,0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#1D4ED8"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#1E40AF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#EF4444"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#DC2626"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" 
                                BorderBrush="{TemplateBinding BorderBrush}" 
                                BorderThickness="{TemplateBinding BorderThickness}" 
                                CornerRadius="6" Padding="10,0,10,0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#DC2626"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#B91C1C"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="180"/>
        </Grid.RowDefinitions>

        <!-- 顶部设备信息与切换栏 -->
        <Border Grid.Row="0" Background="#FFFFFF" CornerRadius="8" Padding="14" Margin="0,0,0,12" BorderBrush="#E2E8F0" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="当前设备：" FontWeight="Bold" FontSize="14" VerticalAlignment="Center" Foreground="#334155"/>
                <ComboBox Grid.Column="1" Name="CmbDevices" Margin="10,0,10,0" Height="36" FontSize="13" VerticalContentAlignment="Center" Background="#F8FAFC"/>
                <Button Grid.Column="2" Name="BtnRefreshDevices" Content="刷新设备列表" Width="130" Height="36"/>
            </Grid>
        </Border>

        <!-- 当前应用状态栏 -->
        <Border Grid.Row="1" Background="#FFFFFF" CornerRadius="8" Padding="14" Margin="0,0,0,12" BorderBrush="#E2E8F0" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="前台应用：" FontWeight="Bold" FontSize="14" VerticalAlignment="Center" Foreground="#334155"/>
                <TextBox Grid.Column="1" Name="TxtPackage" Height="34" Margin="10,0,10,0" FontSize="13" VerticalContentAlignment="Center" Padding="6,0,6,0" BorderBrush="#CBD5E1"/>
                <Button Grid.Column="2" Name="BtnRefreshForeground" Content="抓取前台" Width="100" Height="34"/>
                <Button Grid.Column="3" Name="BtnOpenApp" Style="{StaticResource PrimaryButton}" Content="打开应用" Width="100" Height="34"/>
            </Grid>
        </Border>

        <!-- 核心功能按钮区（卡片网格分类） -->
        <Grid Grid.Row="2" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- 列1：应用管理 -->
            <Border Grid.Column="0" Background="#FFFFFF" CornerRadius="8" Padding="14" Margin="0,0,8,0" BorderBrush="#E2E8F0" BorderThickness="1">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel>
                        <TextBlock Text="应用管理" FontSize="15" FontWeight="Bold" Foreground="#0F172A" Margin="4,0,0,10"/>
                        <Button Name="BtnClearApp" Content="清空应用数据"/>
                        <Button Name="BtnKillApp" Content="杀死当前应用"/>
                        <Button Name="BtnUninstallApp" Style="{StaticResource DangerButton}" Content="卸载当前应用"/>
                        
                        <TextBlock Text="预设包名快速切换" FontSize="13" FontWeight="SemiBold" Foreground="#64748B" Margin="4,12,0,4"/>
                        <Button Name="BtnPreset1" Content="1. 血压计 (bp_tracker)"/>
                        <Button Name="BtnPreset2" Content="2. PDF阅读 (simple.pdf)"/>
                        <Button Name="BtnPreset3" Content="3. 橙色QR (qrcreator)"/>
                        <Button Name="BtnPreset4" Content="4. 绿色QR (qrcode)"/>
                        <Button Name="BtnPreset5" Content="5. 紫色QR (purple)"/>
                    </StackPanel>
                </ScrollViewer>
            </Border>

            <!-- 列2：无线与屏幕镜像控制 -->
            <Border Grid.Column="1" Background="#FFFFFF" CornerRadius="8" Padding="14" Margin="4,0,4,0" BorderBrush="#E2E8F0" BorderThickness="1">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel>
                        <TextBlock Text="屏幕与文件管理" FontSize="15" FontWeight="Bold" Foreground="#0F172A" Margin="4,0,0,10"/>
                        <Button Name="BtnOpenFileManager" Style="{StaticResource PrimaryButton}" Content="📁 打开文件管理器 (File Explorer)"/>
                        <Button Name="BtnStartMirror" Content="🖥 开始镜像 (Start Mirroring)"/>
                        <Button Name="BtnTurnOffCurrent" Content="熄灭当前屏幕 (保持控制)"/>
                        <Button Name="BtnTurnOffAll" Content="熄灭所有屏幕 (保持控制)"/>
                        <Button Name="BtnEnableWireless" Content="开启无线调试 (端口5555)"/>

                        <TextBlock Text="Firebase 与 系统调试" FontSize="13" FontWeight="SemiBold" Foreground="#64748B" Margin="4,12,0,4"/>
                        <Button Name="BtnEnableFirebase" Content="开启 Firebase 调试"/>
                        <Button Name="BtnDisableFirebase" Content="关闭 Firebase 调试"/>
                    </StackPanel>
                </ScrollViewer>
            </Border>

            <!-- 列3：日志、时间与商店工具 -->
            <Border Grid.Column="2" Background="#FFFFFF" CornerRadius="8" Padding="14" Margin="8,0,0,0" BorderBrush="#E2E8F0" BorderThickness="1">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel>
                        <TextBlock Text="日志与时间工具" FontSize="15" FontWeight="Bold" Foreground="#0F172A" Margin="4,0,0,10"/>
                        <Button Name="BtnAppLog" Content="开启应用日志调试 (PID)"/>
                        <Button Name="BtnGlobalLog" Content="开启全局日志调试"/>
                        <Button Name="BtnSetTodayTime" Content="修改当天时间 (HHMM)"/>
                        <Button Name="BtnSetFullTime" Content="修改完整时间 (年月日时分)"/>
                        <Button Name="BtnRestoreAutoTime" Content="🔄 恢复网络自动时间"/>

                        <TextBlock Text="谷歌商店与浏览器" FontSize="13" FontWeight="SemiBold" Foreground="#64748B" Margin="4,12,0,4"/>
                        <Button Name="BtnOpenPlayStore" Content="打开 Play Store"/>
                        <Button Name="BtnClearPlayCache" Content="清除 Play Store 缓存"/>
                        <Button Name="BtnClearPlayData" Content="清除 Play Store 数据"/>
                        <Button Name="BtnOpenBrowserUrl" Content="默认浏览器打开链接"/>
                    </StackPanel>
                </ScrollViewer>
            </Border>
        </Grid>

        <!-- 底部日志控制台输出面板 -->
        <Border Grid.Row="3" Background="#0F172A" CornerRadius="8" Padding="12" BorderBrush="#334155" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="0,0,0,6">
                    <TextBlock Text="执行状态与输出日志" FontWeight="Bold" FontSize="12" Foreground="#94A3B8"/>
                    <Button Name="BtnClearLog" Content="清空输出" Width="70" Height="22" FontSize="11" HorizontalAlignment="Right" Background="#1E293B" Foreground="#94A3B8" BorderBrush="#334155" Margin="0"/>
                </Grid>
                <TextBox Grid.Row="1" Name="TxtLog" Background="Transparent" Foreground="#38BDF8" 
                         FontFamily="Consolas, Cascadia Code, Courier New" FontSize="12"
                         BorderThickness="0" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                         IsReadOnly="True"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml.OuterXml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# 获取 UI 控件
$cmbDevices = $window.FindName('CmbDevices')
$btnRefreshDevices = $window.FindName('BtnRefreshDevices')
$txtPackage = $window.FindName('TxtPackage')
$btnRefreshForeground = $window.FindName('BtnRefreshForeground')
$btnOpenApp = $window.FindName('BtnOpenApp')
$txtLog = $window.FindName('TxtLog')
$btnClearLog = $window.FindName('BtnClearLog')

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
        Log ('已检测到 ' + $devices.Count + ' 台设备。')
    } else {
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

$btnRefreshDevices.Add_Click({
    Refresh-DeviceList
})

$cmbDevices.Add_SelectionChanged({
    $dev = Get-CurrentSelectedDevice
    if ($dev) {
        $window.Title = $dev.Model + ' - ' + $dev.TypeStr + ' | Android 调试控制台'
        Refresh-ForegroundApp
    }
})

$btnRefreshForeground.Add_Click({
    Refresh-ForegroundApp
})

$btnOpenApp.Add_Click({
    $dev = Get-CurrentSelectedDevice
    $pkg = $txtPackage.Text.Trim()
    if (-not $dev -or -not $pkg) { Log '请确保已选设备和有效包名！'; return }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell monkey -p ' + $pkg + ' -c android.intent.category.LAUNCHER 1')
    Log ('打开应用 ' + $pkg + ' -> ' + $ret.Output)
})

$btnClearApp.Add_Click({
    $dev = Get-CurrentSelectedDevice
    $pkg = $txtPackage.Text.Trim()
    if (-not $dev -or -not $pkg) { Log '请确保已选设备和有效包名！'; return }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell pm clear ' + $pkg)
    Log ('清空应用数据 -> ' + $ret.Output)
})

$btnKillApp.Add_Click({
    $dev = Get-CurrentSelectedDevice
    $pkg = $txtPackage.Text.Trim()
    if (-not $dev -or -not $pkg) { Log '请确保已选设备和有效包名！'; return }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell am force-stop ' + $pkg)
    Log ('杀死应用 -> ' + $ret.Output)
})

$btnUninstallApp.Add_Click({
    $dev = Get-CurrentSelectedDevice
    $pkg = $txtPackage.Text.Trim()
    if (-not $dev -or -not $pkg) { Log '请确保已选设备和有效包名！'; return }
    $confirm = [System.Windows.MessageBox]::Show('确定要从设备 ' + $dev.Model + ' 上卸载 ' + $pkg + ' 吗？', '卸载确认', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
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
    $argList = '--serial="' + $dev.Serial + '" --window-title="' + $title + '"'

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $scrcpy
        $psi.Arguments = $argList
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        Log ('手机镜像窗口已在前台启动 (设备: ' + $title + ')')
    } catch {
        Log ('启动镜像失败: ' + $_.Exception.Message)
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
    $ip = Get-DeviceIp $dev.Serial
    if (-not $ip) {
        $ip = [Microsoft.VisualBasic.Interaction]::InputBox('未能自动获取IP，请输入设备IP：', '输入无线调试IP', '192.168.3.')
        if (-not $ip) { Log '已取消开启无线调试。'; return }
    }
    $tcpipRes = (adb -s $dev.Serial tcpip 5555 2>&1 | Out-String).TrimEnd()
    Start-Sleep -Seconds 1
    $target = $ip + ':5555'
    $connectRes = (adb connect $target 2>&1 | Out-String).TrimEnd()
    Log ('设置端口 5555: ' + $tcpipRes)
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
    $t = [Microsoft.VisualBasic.Interaction]::InputBox('请输入时间 (格式 HHMM，如 1530):', '修改当天时间', '')
    if ($t -notmatch '^\d{4}$') { Log '时间格式错误，已取消。'; return }

    $hour = $t.Substring(0,2)
    $minute = $t.Substring(2,2)
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
    $t = [Microsoft.VisualBasic.Interaction]::InputBox('请输入完整时间 (格式 YYYYMMDDHHMM，如 202609181530):', '修改完整时间', '')
    if ($t -notmatch '^\d{12}$') { Log '完整时间格式错误，已取消。'; return }

    $year = $t.Substring(0,4)
    $month = $t.Substring(4,2)
    $day = $t.Substring(6,2)
    $hour = $t.Substring(8,2)
    $minute = $t.Substring(10,2)

    $res = Set-DeviceTime -serial $dev.Serial -year $year -month $month -day $day -hour $hour -minute $minute
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
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell pm clear ' + $playStorePackage)
    Log ('清除 Play Store 应用数据 -> ' + $ret.Output)
})

$btnOpenBrowserUrl.Add_Click({
    $dev = Get-CurrentSelectedDevice
    if (-not $dev) { Log '请先选择设备！'; return }
    $url = [Microsoft.VisualBasic.Interaction]::InputBox('请输入要打开的链接：', '打开网页', 'https://')
    $url = $url.Trim()
    if (-not $url) { Log '未输入链接，已取消。'; return }
    if ($url -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $url = 'https://' + $url }
    $ret = Invoke-CmdText ('adb -s ' + $dev.Serial + ' shell am start -a android.intent.action.VIEW -d "' + $url + '"')
    Log ('浏览器打开链接 -> ' + $ret.Output)
})

# 初始化加载
Refresh-DeviceList
$window.ShowDialog() | Out-Null
