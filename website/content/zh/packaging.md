# 打包参考

[English](../packaging.html)

Proton CLI 将项目组装为分发产物，包含可执行文件、前端资源、CEF 运行时、匹配的 helper 和声明的资源。后端可执行文件本身不是完整分发包。打包面向当前宿主平台。

字段类型与默认值统一定义在 [Configuration](configuration.md)。

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
