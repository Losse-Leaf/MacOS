# Loose-Leaf (活页集) · macOS Native Workstation

> **暗房工作台与灵感捕捉器 (The Darkroom & Quick Capture Station)**  
> 活页集 (`Loose-Leaf`) 的原生 macOS 桌面客户端，基于 `SwiftUI + AppKit` 构建。

---

## 安装与更新 (Installation & Updates)

> 本客户端为开源纯原生 macOS 应用程序（arm64 Apple Silicon）。由于未签发收费的 Apple Developer ID 证书，macOS Gatekeeper 安全机制会对从网络下载的应用触发隔离拦截。推荐以下两种最便捷的安装与使用方式：

### 方式一：终端一行命令极速安装与更新（推荐，3 秒全自动）

打开 Mac「终端」（Terminal），粘贴运行以下命令并回车：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Losse-Leaf/MacOS/main/install.sh)"
```

- **全自动流程**：自动从 GitHub Releases 拉取最新版本 → 下载解压至 `/Applications` → 自动放行 Gatekeeper 隔离属性 (`xattr -cr`) → 自动启动应用。
- **更新应用**：日后需要更新时也只需再次运行此命令，3 秒自动无缝升级至最新版本，**彻底告别手动输入命令或“已损坏”提示**。

---

### 方式二：手动下载安装（纯图形界面，免终端）

如果习惯通过浏览器直接下载使用：

1. 前往 [GitHub Releases](https://github.com/Losse-Leaf/MacOS/releases) 下载最新的 `LooseLeaf-*.zip` 压缩包并解压；
2. 将解压出的 `LooseLeaf.app` 拖入 **「访达」→「应用程序」**（`/Applications`）文件夹；
3. **首次打开系统安全放行流程**（仅需在首次打开时操作一次）：
   - 双击打开若提示：“*无法打开 LooseLeaf.app，因为无法验证开发者*” 或 “*已损坏*”；
   - 打开 Mac **「系统设置」**；
   - 点击左侧 **「隐私与安全性」**；
   - 滚动到页面下方 **「安全性」** 区域，会看到提示：“*已阻止使用 LooseLeaf.app，因为来自身份不明的开发者*”；
   - 点击旁边的 **「仍要打开」** 按钮，验证指纹或输入开机密码即可永久正常打开使用。

> 💡 **提示**：该放行操作仅需首次配置一次，后续双击打开、开机常驻均可直接使用。

---

## 核心特性

1. **纸张数字主义与暗房双模态 (`Paper & Darkroom`)**
   - 严格遵循跨端语义色彩资产表 (`Assets.xcassets`)，零硬编码十六进制色值。
   - **纸张模式 (Light)**：温润宣纸底色与宋刻衬线混排；**暗房模式 (Dark)**：炭黑底色与银盐文字，专为深夜修图与归档设计。
   - 支持 `.film-frame` 相纸装裱画框与 `NoiseBackground` 纸张纹理。

2. **全局极速捕捉 (`MenuBarExtra` & 全局快捷键)**
   - **全局呼出 (`⌘⇧L`)**：任意应用内呼出菜单栏捕捉面板（自动聚焦输入框，`⌘↩` 归档，`ESC` 收起），热键可在设置中录制修改。
   - **双 Tab 捕捉**：面板内「极速记录 / 快速记账」切换；记账支持类 Spotlight 自然语言解析（如输入 `42.5 午餐手冲咖啡` 自动拆解为 `4250` 分、`餐饮` 分类与备注），记录支持 `#标签` 自动提取、多张照片拖拽、`⌘V` 截图直贴与任意历史时刻补记。
   - **工作台快捷键**：主窗口 `⌘N` 撰写散页、`⌘R` 全量同步、`⌘1`–`⌘6` 切换六大内容板块、`⌘↑`/`⌘↓` 键盘流浏览、`⌘↩` 打开详情。
   - **侧栏结构**：6 大内容板块 + 5 个配置条目（偏好设置 / 中枢与设备 / 存储与备份 / 分类字典 / 关于活页）平铺，底部「辅助工具」收银盐暗房；配置类原「配置中心」容器已扁平化进侧栏。
   - **系统集成**：系统右键「服务」菜单「摘录到活页集」直送捕捉面板；散页已接入 Spotlight 系统搜索（增量重建）。Apple 快捷指令 / Siri 入口已于 1.5.x 下线，不再提供。

3. **桌面暗房流水线 (`DarkroomDropZone`)**
   - 原生 `ImageIO` 提取相机、镜头、光圈、快门、ISO 等 EXIF 元数据。
   - 客户端无损缩放至 4K (`3840px`) 与 85% JPEG 编码，通过预签名 URL 直传 Cloudflare R2（本地开发未配置 R2 时自动回退至 `/api/v1/files/upload`）。

4. **分位整数精度账本与联动装备库 (`Ledger & Gear`)**
   - 所有金额均以 `Int64` **分 (`cents`)** 存储与传输，彻底杜绝浮点数精度漂移。
   - 新增器物资产支持勾选 **`create_transaction = true`**，一键同步生成大额购置账单。

5. **离线发件箱与增量同步 (`SyncManager`)**
   - 本地快照 (`archive_snapshot_v1.json`，`~/Library/Application Support/LooseLeaf/`) 冷启动直接渲染；写入做 0.35 秒合并，退出前强制落盘。快照损坏时会隔离备份并以只读警告提示，不会静默覆盖。
   - 断网状态下新建的手稿与账单自动进入持久化 `Outbox` 发件箱，`NWPathMonitor` 探测网络恢复后自动重放上云（相片上传仍需联网）。

---

## 目录结构

```text
mac/
├── Package.swift                      # Swift Package Manager 构建与测试工程
├── LooseLeaf.xcodeproj/               # Xcode 原生工程配置
├── LooseLeaf/
│   ├── App/
│   │   ├── LooseLeafApp.swift         # @main 入口、MenuBarExtra、主窗口与菜单快捷键
│   │   ├── AppDelegate.swift          # 全局热键监听、浮动 NSPanel、URL Scheme 与系统服务
│   │   └── AppState.swift             # 跨窗口 UI 导航与模态框状态中心
│   ├── Models/
│   │   ├── EntryModel.swift           # LifeEntry / Attachment / GlobalStats 模型
│   │   ├── TransactionModel.swift     # Transaction (Int64 分) / GearItem / 信用渠道模型
│   │   └── ProfileModel.swift         # CuratorProfile / Wish / Footprint / 配对鉴权模型
│   ├── Services/
│   │   ├── APIClient.swift            # Async/Await 网络客户端（Bearer / X-Device-Token / ETag）
│   │   ├── CredentialStore.swift      # 本机受保护凭据档案 (0600，免签场景替代 Keychain)
│   │   ├── SyncManager.swift          # 增量同步、本地快照与 Offline Outbox 队列
│   │   ├── Pagination.swift           # 统一分页拉取（页大小 / 最大页数保险丝）
│   │   ├── ImageProcessor.swift       # ImageIO EXIF 解析与 4K JPEG 压缩
│   │   ├── R2DirectUploader.swift     # R2 预签名 PUT 直传与本地回退上传器
│   │   └── FormatUtils.swift          # Int64 分转换、UTC+8 北京时间解析与自然语言记账解析
│   ├── Views/
│   │   ├── MenuBar/                   # QuickCaptureView & QuickLedgerView
│   │   ├── Main/                      # StreamView / WishlistView / ProjectsView / TravelAtlasView / LedgerAssetsView / DarkroomDropZone / SettingsView
│   │   └── Components/                # FilmFrameView / NoiseBackground / PaperComponents
│   └── Resources/
│       ├── Assets.xcassets/           # 跨端统一语义色板与图标资产
└── LooseLeafTests/                    # XCTest 单元测试套件
```

---

## 构建与运行

### 命令行构建与测试 (SwiftPM)

```bash
cd mac
swift build
swift test
```

### 使用 Xcode 打开

```bash
open LooseLeaf.xcodeproj
```
