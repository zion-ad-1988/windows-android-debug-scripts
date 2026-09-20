# Windows 一键 Android 调试脚本

一套跑在 Windows 上的 Android 调试/测试辅助工具，用 **PowerShell + ADB + scrcpy** 实现，双击 `.bat` 即可使用，**免安装、免配置**（脚本自带 `scrcpy\adb.exe`）。

面向日常测试高频操作：清数据、启停应用、抓日志、改时间、清 Play 商店、无线调试、镜像投屏、文件管理。

## 快速开始

```
windows-android-debug-scripts
├── testApp.bat          # 命令行版启动器（双击运行）
├── testApp.ps1          # 命令行版主脚本 / 22 项功能
├── testApp_gui.bat      # 图形界面版启动器（双击运行）
├── testApp_gui.ps1      # 图形界面版主脚本（WPF 控制台）
├── scrcpy/              # 随包携带的 adb / scrcpy 运行环境
│   ├── adb.exe  AdbWinApi.dll  AdbWinUsbApi.dll  fastboot.exe
│   └── scrcpy.exe  scrcpy-server  SDL3.dll  av*.dll  *.png
└── README.md
```

1. 手机开启 **开发者选项 → USB 调试**，用数据线连接电脑，弹窗点「允许 USB 调试」。
2. 双击 `testApp.bat`（命令行版）或 `testApp_gui.bat`（图形界面版）。
3. 检测到多台设备时会让你选择；只有一台时自动选中。

> `.bat` 启动器会先把 `scrcpy\` 加入 PATH，所以 `adb` / `scrcpy` 都直接用脚本自带的版本，不会和你系统里已装的冲突。

## 环境要求

| 项目 | 要求 |
|---|---|
| 系统 | Windows 10 / 11 |
| PowerShell | 5.1（系统自带）即可；GUI 版依赖 WPF，Win10 起自带 |
| 安卓设备 | Android 7.0+ 建议；时间修改依赖 `cmd time_detector`（Android 8+ 免 Root） |
| 网络 | 仅无线调试、Firebase 相关功能需要 |

无需单独安装 adb 或 scrcpy，仓库内已附带（scrcpy 4.1，adb 37.0.0）。

## 命令行版（testApp.bat）

启动后先选设备 / 包名，进入 22 项功能菜单：

| 编号 | 功能 | 说明 |
|---|---|---|
| 1 | 清空应用数据 | `pm clear`，回到首次安装状态 |
| 2 | 打开应用 | `monkey -c android.intent.category.LAUNCHER` 拉起首页 |
| 3 | 刷新前台应用 | 抓当前前台包名并切换为操作目标 |
| 4 | 选择预设包名 | 内置 5 个常用包名，也支持手动输入 |
| 5 | 卸载当前应用 | `adb uninstall` |
| 6 | 重新选择设备 | 热插拔设备后重新扫码 |
| 7 | 开启 Firebase 调试 | `setprop debug.firebase.analytics.app <包名>` |
| 8 | 关闭 Firebase 调试 | 置为 `.none.` |
| 9 | 杀死当前应用 | `am force-stop` |
| 10 | 修改当天时间 | 输入 `HHMM`，只改时分 |
| 11 | 开启应用日志调试 | 按 PID 抓 logcat，写入日志文件 |
| 12 | 全局日志调试 | 抓全量 logcat |
| 13 | 清除 Play Store 缓存 | `pm trim-caches` + 缓存目录清理 |
| 14 | 清除 Play Store 数据 | `pm clear com.android.vending` |
| 15 | 打开 Play Store | 直达商店页面 |
| 16 | 默认浏览器打开链接 | 设备内打开指定 URL |
| 17 | 修改完整时间 | 输入 `YYYYMMDDHHMM` |
| 18 | 开启无线调试并连接 | `tcpip 5555` + `adb connect` |
| 19 | 关闭当前手机屏幕（保持调试） | scrcpy `--turn-screen-off`，屏幕黑但调试不断 |
| 20 | 关闭所有手机屏幕（保持调试） | 批量执行 |
| 21 | 开始镜像当前手机 | scrcpy 投屏到电脑 |
| 22 | 恢复为网络自动时间 | 还原自动对时 |

### 修改时间的三级兜底

`cmd time_detector suggest_network_time`（Android 8+，免 Root）→ Shizuku 广播 → `su -c date`，都不行会明确提示失败原因。

### 日志输出

logcat 会在新窗口实时采集，文件写入 `E:\workspace\data\log`（目录不存在会自动创建）：

```
<型号>-<安卓版本>-<包名>-<版本号>-<时间戳>.txt            # 应用日志
<型号>-<安卓版本>-<包名>-<版本号>-<时间戳>-logcat.txt     # 全局日志
```

路径在脚本开头的 `$logDir` 处可改；命令行版还会把当前包名记录到 `current_app.txt`。

## 图形界面版（testApp_gui.bat）

WPF 控制台，点按钮即可，适合不习惯敲菜单的场景：

- **设备面板**：设备列表自动刷新，显示型号 / 序列号 / 有线无线；一键抓取前台应用
- **应用操作**：打开 / 清数据 / 杀进程 / 卸载 / 5 个预设包名快捷按钮
- **文件管理器**（独立窗口）：浏览手机目录、上传（支持多选与**拖拽**）、批量导出到电脑、新建文件夹、重命名、删除、复制完整路径、双击打开文件
- **镜像与屏幕**：开始镜像、熄灭当前 / 所有屏幕（保持调试控制）
- **日志**：应用日志（按 PID）、全局日志，实时写入文件
- **时间**：修改当天时间（HHMM）、完整时间（YYYYMMDDHHMM）、恢复自动时间
- **Play Store**：打开、清缓存、清数据
- **无线调试 / Firebase 调试 / 浏览器打开链接**
- 底部实时输出日志，可一键清空

## 自定义预设包名

两个脚本顶部的 `$preset1 ~ $preset5`、`$playStorePackage` 按需改成你自己的包名即可：

```powershell
$preset1 = 'com.one.bp_tracker'
$preset2 = 'com.smartreader.simple.pdf'
$preset3 = 'com.smartbar.qrcreator'
$preset4 = 'com.quickscan.qrcode'
$preset5 = 'com.simplescan.qrcode.purple'
```

## 常见问题

| 现象 | 处理 |
|---|---|
| 列表里没有设备 | 换数据线 / 换 USB 口；手机端「USB 调试」重新授权；`scrcpy\adb.exe kill-server` 后重试 |
| 设备显示 `unauthorized` | 手机上重新确认「允许 USB 调试」弹窗 |
| 无线调试连不上 | 手机与电脑需在同一网段；先有线执行一次「开启无线调试」，再用 IP 重连 |
| 时间修改失败 | 需 Android 8+ 支持 `time_detector`，或设备已装 Shizuku / 有 Root |
| Play Store 清缓存无效 | 部分版本需 Root 才能清 `/data/data/com.android.vending`，脚本会自动降级并提示 |
| 中文乱码 | 两个脚本已强制 UTF-8 输出；终端字体请选支持中文的（如微软雅黑、Cascadia） |

## scrcpy

`scrcpy/` 目录来自 [Genymobile/scrcpy](https://github.com/Genymobile/scrcpy)（Apache-2.0），版本 4.1；`adb.exe` / `fastboot.exe` 来自 Google Android Platform Tools。随包携带只是为了开箱即用，可自行替换为更新版本。

## 已知限制

- 仅支持 Windows。
- 脚本内预设包名、日志目录为个人环境配置，使用前按需修改。
- 未提供安装包/签名，属于个人测试辅助脚本，不面向生产环境分发。

## License

MIT（`scrcpy/` 内的第三方组件遵循其各自许可证）。

---

## English

A Windows toolkit for daily Android debugging: double-click `testApp.bat` (CLI, 22 functions) or `testApp_gui.bat` (WPF GUI console) to clear app data, launch/kill/uninstall apps, capture logcat, change device time, manage the Play Store, enable wireless ADB (`tcpip 5555` + `connect`), mirror the screen and manage device files — all via the bundled `adb` and `scrcpy` (no installation required).

Requirements: Windows 10/11, PowerShell 5.1, an Android device with USB debugging enabled.
