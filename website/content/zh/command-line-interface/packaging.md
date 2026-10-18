# 打包参考

Proton CLI 将项目组装为分发产物，包含可执行文件、前端资源、CEF 运行时、匹配的 helper 和声明的资源。后端可执行文件本身不是完整分发包。打包面向当前宿主平台。

字段类型与默认值统一定义在 [Configuration](../configuration/project.md)。

## 平台覆盖

各平台对象接受 `formats`、`resources`、`sign`。Windows 还接受 `nsis_install_mode`，macOS 还接受 `minimum_system_version`。平台格式列表替换共享列表，平台资源与共享资源合并。路径值以项目配置文件目录为基准。

| 平台 | 格式 | 默认值 |
| --- | --- | --- |
| macOS Apple Silicon | `app`、`zip`、`dmg` | `app`、`zip` |
| Windows x64 | `app`、`zip`、`nsis` | `app`、`zip` |
| Linux x64 | `appimage` | `appimage` |

## 图标与工具前提

| 产物 | 图标和工具 |
| --- | --- |
| macOS app / zip | ICNS 用于应用图标；本机 Apple 工具链用于构建与签名 |
| macOS dmg | 在 app 基础上使用系统 hdiutil 创建磁盘映像 |
| Windows app / zip | ICO 由 Windows SDK 的 rc.exe 编入 EXE；不会自动将 PNG 转 ICO |
| Windows nsis | 在 Windows 应用基础上还需 NSIS 的 makensis |
| Linux appimage | 必须提供 PNG；PATH 中必须有可执行的 appimagetool |

默认 scaffold 不提供图标。Linux 缺少 PNG 会在调用 AppImage 工具之前失败。准备图标和工具的完整操作见 [Todo 打包步骤](../tutorial/isomorphic.md#linux)。为不同平台提供对应格式的图标，不要只配置 macOS 和 Linux 图标却期待 Windows 自动转换。

## NSIS 安装模式

| 值 | 行为 |
| --- | --- |
| `currentUser` | 默认；当前用户，不要求管理员安装；安装到 `%LOCALAPPDATA%` 下，使用当前用户注册 |
| `perMachine` | 所有用户，需要提权；安装到 Program Files 下，使用机器级注册 |
| `both` | 安装器提供范围选择；即使选择当前用户也可能提示提权 |

修改模式不是安装范围迁移。更新已有的机器级安装时，应保持其预期安装范围。

**升级旧版 Proton 安装器：** 旧版 Proton 始终生成机器级 NSIS 安装器。已采用该方式分发的应用，后续版本必须显式将 `package.platforms.windows.nsis_install_mode` 设为 `perMachine`。当前默认的 `currentUser` 面向另一种安装范围。同一范围内会复用已有安装路径；固定模式不会将安装从用户级迁移到机器级，反之亦然。

`both` 使用 NSIS MultiUser，并请求最高可用权限。因此，即使用户选择当前用户安装，也可能先看到 UAC 提示。`--nsis-install-mode` 覆盖项目配置，参见 [CLI 命令参考](commands.md#package)。

## macOS 最低版本

minimum_system_version 只写 macOS 的 LSMinimumSystemVersion 元数据，不能使较新 SDK／CEF 编译出的应用自动兼容旧系统。最低系统支持需要在目标系统上验证整个产物，而不只是编译通过。

## 签名与公证

`--release` 控制构建模式，不意味着签名。macOS 上，`--sign` 请求签名；`--notarize` 使用配置的凭据请求公证、装订和验证。身份与凭据环境变量见 [CLI 命令参考](commands.md#签名环境)。

未签名或本地签名的产物不代表受信任的发布者身份。凭据属于部署配置，不属于应用源码。

## 运行时资源行为

打包前端资源不依赖开发服务器。后端资源路径通过 `resource_dir()` 解析。安装资源可能只读，持久应用数据不应写入其中。

`package.resources` 提供共享的附加资源，平台资源会追加到共享列表。`package.sign.binaries` 及其平台覆盖指定额外参与签名的可执行文件。显式 CLI 选项优先于配置。字段类型和合并规则见 [Configuration](../configuration/project.md#package)。

`--dry-run` 校验并展示打包计划，不证明实际打包、签名或产物运行成功。[Todo 教程](../tutorial/isomorphic.md)包含应用构建与打包练习。

## 打包准备命令

`package.prepare` 在前端和原生可执行文件构建完成后、资源组装前，从项目配置文件目录执行一次。它用于生成已声明的打包专用资源或额外二进制。命令以非零状态退出会中止打包。

`proton_cli build` 和 `proton_cli package --dry-run` 不执行此命令。独立的 `proton_package` 工具只打包已有可执行文件与提供的资源，不发现项目、不执行构建或准备命令，也不组装 CEF。参见[独立打包器](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/package/README.md)。

## 更新产物与元数据

更新元数据是可选输出。`package --updater-base-url <https-url> --updater-published-at <instant>` 必须同时提供两个参数，使用最终的 `package.version`（包括 `--version` 覆盖值），不再有独立的更新 revision。

| 宿主平台 | 必需输出格式 | 自更新选用的产物 |
| --- | --- | --- |
| macOS | `zip` | `.app.zip`；DMG 不用于自动更新 |
| Windows | `nsis` | `-setup.exe`；应用目录或 ZIP 不能代替安装器 |
| Linux | `appimage` | `.AppImage` |

选择的打包格式没有生成对应产物时，元数据生成失败，不会将其它格式转换为更新载荷。

命令在产物旁写入 `<artifact>.sha256` 和 `latest-<platform>.json`。JSON 是 schema 3 的**片段**，不是可以直接发布的更新渠道：产物签名有意留空。字段如下：

| 字段 | 约定 |
| --- | --- |
| `schema_version` | `3`；新版更新器不接受 schema 2 |
| `version` | 最终应用版本，严格使用 `major.minor.patch`；按数值比较，不允许前导零或后缀 |
| `published_at` | UTC `YYYY-MM-DDTHH:MM:SSZ` |
| `notes_url` | 组装最终 manifest 时可选的发布说明 URL |
| `platforms` | 以 `darwin-arm64`、`win32-x64` 或 `linux-x64` 为键 |
| `platforms.<id>.kind` | `full` |
| `platforms.<id>.url` | 基础 URL 与文件名组合得到的 HTTPS 产物地址 |
| `platforms.<id>.size` | 正的 `Int64` 字节数 |
| `platforms.<id>.sha256` | 小写十六进制 SHA-256 摘要 |
| `platforms.<id>.signature` | 小写十六进制 RSA/SHA-256 产物签名 |

发布者使用自己的私钥签署产物并填入 `signature`。同一应用版本的多个平台条目可以组装成一个 manifest。最终 manifest 的字节也需要签名：运行时读取配置的端点及 `<endpoint>.sig`，后者是以十六进制文本表示的独立 RSA/SHA-256 签名。签名后再修改 manifest 会使签名失效。产物、完整 manifest 和独立签名应一并通过 HTTPS 发布。

`--sign`／`--notarize` 负责操作系统分发签名，不会填充更新器签名。这组更新参数不接收私钥，也不负责上传文件。公钥生成／导入及安装生命周期见[应用更新](../introduction/application-api.md#应用更新)。

## URL 协议与文档类型

`package.url_schemes` 和 `package.document_types` 描述操作系统的启动关联。具体效果取决于产物：

| 产物 | 行为 |
| --- | --- |
| macOS app | 将 URL 协议和文档类型写入应用元数据 |
| Windows NSIS | 在所选安装范围注册 URL 协议，卸载时移除仍属于该应用的注册；尚未实现文档类型关联 |
| Windows app / zip | 不安装操作系统关联 |
| Linux AppImage | 在内置 desktop entry 中声明 URL 协议，仍需桌面集成将其注册到系统；尚未实现文档类型关联 |

声明关联并不实现应用侧处理。启动输入处理器的注册方法见[应用生命周期](../introduction/application-api.md#应用生命周期)。
