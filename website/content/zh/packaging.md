# 打包参考

[English](../packaging.html)

Proton CLI 将项目组装为分发产物，包含可执行文件、前端资源、CEF 运行时、匹配的 helper 和声明的资源。后端可执行文件本身不是完整分发包。打包面向当前宿主平台。

## 元数据

以下字段属于 `proton.project.json` 的 `package` 对象。

| 字段 | 类型 | 默认值与含义 |
| --- | --- | --- |
| `product_name` | string | 必填，显示名称 |
| `version` | string | 必填，应用版本，独立于 Proton 版本 |
| `formats` | string array | 省略时使用宿主平台默认格式 |
| `icons` | string array | 空；图标路径相对于配置文件目录 |
| `prepare` | string | 无；准备命令 |
| `resources` | string array | 空；附加打包资源 |
| `sign.binaries` | string array | 空；额外选择签名的二进制文件 |
| `url_schemes` | string array | 空；应用注册的 URL scheme |
| `document_types` | object array | 空；文档关联 |
| `output` | string | `dist`，相对于配置文件目录 |
| `platforms` | object | 可选的 `macos`、`windows`、`linux` 覆盖 |

文档类型包含必填的 `name`、`extensions`，`role` 默认为 `Viewer`。规范应用标识位于顶层 `identifier`，不是 package 字段。修改产品名称不会改变应用身份。

## 平台覆盖

各平台对象接受 `formats`、`resources`、`sign`。Windows 还接受 `nsis_install_mode`。平台格式列表替换共享列表，平台资源与共享资源合并。路径值以项目配置文件目录为基准。

| 平台 | 格式 | 默认值 |
| --- | --- | --- |
| macOS Apple Silicon | `app`、`zip`、`dmg` | `app`、`zip` |
| Windows x64 | `app`、`zip`、`nsis` | `app`、`zip` |
| Linux x64 | `appimage` | `appimage` |

Windows 使用 Windows SDK 资源编译器将配置的 ICO 内容编译进应用可执行文件。NSIS 产物还要求安装 NSIS。

## NSIS 安装模式

| 值 | 行为 |
| --- | --- |
| `currentUser` | 默认；当前用户，不要求管理员安装 |
| `perMachine` | 所有用户，需要提权 |
| `both` | 安装器提供范围选择；即使选择当前用户也可能提示提权 |

修改模式不是安装范围迁移。更新已有的机器级安装时，应保持其预期安装范围。

## 签名与公证

`--release` 控制构建模式，不意味着签名。macOS 上，`--sign` 请求签名；`--notarize` 使用配置的凭据请求公证、装订和验证。身份与凭据环境变量见 [CLI 命令参考](cli.md#签名环境)。

未签名或本地签名的产物不代表受信任的发布者身份。凭据属于部署配置，不属于应用源码。

## 运行时资源行为

打包前端资源不依赖开发服务器。后端资源路径通过 `resource_dir()` 解析。安装资源可能只读，持久应用数据不应写入其中。

`--dry-run` 校验并展示打包计划，不证明实际打包、签名或产物运行成功。[Todo 教程](tutorial/isomorphic.md)包含应用构建与打包练习。
