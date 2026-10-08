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
| `currentUser` | 默认；当前用户，不要求管理员安装 |
| `perMachine` | 所有用户，需要提权 |
| `both` | 安装器提供范围选择；即使选择当前用户也可能提示提权 |

修改模式不是安装范围迁移。更新已有的机器级安装时，应保持其预期安装范围。

## macOS 最低版本

minimum_system_version 只写 macOS 的 LSMinimumSystemVersion 元数据，不能使较新 SDK／CEF 编译出的应用自动兼容旧系统。最低系统支持需要在目标系统上验证整个产物，而不只是编译通过。

## 签名与公证

`--release` 控制构建模式，不意味着签名。macOS 上，`--sign` 请求签名；`--notarize` 使用配置的凭据请求公证、装订和验证。身份与凭据环境变量见 [CLI 命令参考](commands.md#签名环境)。

未签名或本地签名的产物不代表受信任的发布者身份。凭据属于部署配置，不属于应用源码。

## 运行时资源行为

打包前端资源不依赖开发服务器。后端资源路径通过 `resource_dir()` 解析。安装资源可能只读，持久应用数据不应写入其中。

`--dry-run` 校验并展示打包计划，不证明实际打包、签名或产物运行成功。[Todo 教程](../tutorial/isomorphic.md)包含应用构建与打包练习。
