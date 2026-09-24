# Command Line Interface

本页列出 `proton_cli` 的全部命令及其参数。应用的 IPC 命令见[命令](../introduction/commands-events.md)，配置文件字段见[项目配置](../configuration/index.md)。

## 调用形式与全局选项

```text
proton_cli [--cwd <directory>] <command> [options]
```

| 选项 | 含义 |
| --- | --- |
| `-C`、`--cwd <directory>` | 工作目录，默认 `.`；对子命令也有效 |
| `-h`、`--help` | 显示所选命令的帮助 |
| `-V`、`--version` | 显示 CLI 版本，用途与 `version` 相同 |

`--config`、`--moon-target-dir` 和 doctor 报告路径以所选工作目录为基准；`dev --frontend-path` 和打包图标、输出路径以项目配置目录为基准。配置文件内的路径以配置文件目录为基准，`frontend.dist` 以 frontend 目录为基准。显式命令选项覆盖对应的配置值。

## 命令索引

| 命令 | 用途 |
| --- | --- |
| [`help`](#help) | 显示命令帮助 |
| [`version`](#version) | 输出 CLI 版本 |
| [`new`](#new) | 创建应用项目 |
| [`dev`](#dev) | 构建并以开发模式运行应用 |
| [`build`](#build) | 构建前端资源和原生后端 |
| [`package`](#package) | 构建并组装分发产物 |
| [`doctor`](#doctor) | 输出环境和项目诊断 |
| [`cef setup`](#cef-setup) | 安装匹配当前发行版的运行时和 helper |
| [`cef requirements`](#cef-requirements) | 输出内嵌的 CEF 版本要求 |
| [`updater public-key`](#updater-public-key) | 校验并格式化更新器信任的公钥 |

## `help`

```text
proton_cli help [command] [subcommand]
```

显示帮助，不执行所选命令。例如 `proton_cli help cef setup` 说明运行时安装命令，不执行安装。对应的选项形式是 `proton_cli <command> --help`。

## `version`

```text
proton_cli version
```

输出 `proton_cli <version>`。没有专属选项，不执行更新检查。

## `new`

```text
proton_cli new [path] [options]
```

创建项目源码。未指定 `--yes` 且不在 CI 环境时使用交互提示。以下默认值适用于没有交互输入或显式选项覆盖的情况。

| 参数 / 选项 | 默认值及含义 |
| --- | --- |
| `[path]` | `todo`；目标目录 |
| `--template <name>` | `isomorphic`；可选 `minimal`、`isomorphic` |
| `--title <text>` | 根据项目目录名生成；应用及窗口标题 |
| `--author <name>` | `username`；MoonBit 模块作者 |
| `--identifier <id>` | `dev.proton.<规范化项目名>`；反向域名形式的应用标识 |
| `--width <pixels>` | `960`；正整数 |
| `--height <pixels>` | `640`；正整数 |
| `--check`、`--no-check` | 默认开启；创建后执行 `moon check --target js,native` |
| `--git`、`--no-git` | 显式启用或禁用 Git 初始化；非交互默认不初始化 Git |
| `-y`、`--yes` | 跳过提示并接受默认值 |
| `--dry-run` | 打印计划生成的文件，不写入文件 |

`minimal` 创建内嵌 HTML 的原生模块；`isomorphic` 创建 shared、frontend、backend 三个模块。无效标识、非正数尺寸和不支持的模板名会被拒绝。


## `dev`

```text
proton_cli dev [options] [-- <application-arguments>...]
```

构建并运行原生后端。配置前端命令时，会启动该命令、等待服务就绪，并向应用提供开发 URL。后端修改需要重新构建、启动；前端刷新由前端工具负责。

| 选项 | 默认值及含义 |
| --- | --- |
| `--config <path>` | 项目配置，默认工作目录下的 `proton.project.json` |
| `--package <selector>` | 覆盖配置中的后端包；回退值为 `app` |
| `--moon-target-dir <path>` | 覆盖内部 Moon 调用的输出目录 |
| `--url <url>` | 覆盖 `frontend.dev_url` |
| `--command <command>` | 覆盖 `frontend.before_dev` |
| `--frontend-path <path>` | 覆盖前端命令的工作目录 |
| `--timeout-ms <milliseconds>` | `30000`；等待前端就绪的超时时间 |
| `--ready-path <path>` | 在此路径使用 HTTP 就绪探测；未指定时检查 TCP 连接 |
| `--no-frontend` | 不启动前端命令，使用外部管理的服务 |
| `--setup`、`--no-setup` | 自动安装缺失的运行时和 helper；默认关闭 |
| `-- <arguments>...` | 传给应用的参数，不是 Moon 参数 |

由 CLI 管理的前端必须配置启动命令，且开发地址已被占用时会报错。HTTP 探测需要 `curl`。等待超时后不会启动应用。CLI 负责自己启动的前端进程，外部服务的生命周期独立。

## `build`

```text
proton_cli build [options] [-- <moon-build-arguments>...]
```

依次执行前端构建、验证前端输出、构建原生后端。前端命令失败时不会继续构建后端。结果是构建产物，不是完整分发包。

| 选项 | 默认值及含义 |
| --- | --- |
| `--config <path>` | 项目配置，默认工作目录下的 `proton.project.json` |
| `--package <selector>` | 覆盖配置中的后端包；回退值为 `app` |
| `--moon-target-dir <path>` | 覆盖内部 Moon 构建的输出目录 |
| `--no-frontend` | 跳过前端构建命令，不会生成缺失的前端资源 |
| `-- <arguments>...` | 传给 `moon build`，例如 `-- --release` |

后端始终使用 native 目标；通过转发参数覆盖 `--target` 会被拒绝。

## `package`

```text
proton_cli package [options]
```

为当前主机平台构建并组装应用、前端资源、CEF 运行时、匹配的 helper 和声明的资源。必须有项目配置。本命令不接收尾随的 Moon 参数。

| 选项 | 默认值及含义 |
| --- | --- |
| `--config <path>` | 项目配置，默认 `proton.project.json` |
| `--package <selector>` | 覆盖后端包 |
| `--release` | 使用 release 构建，默认 debug |
| `--dry-run` | 解析并打印计划，不执行完整构建、打包流程 |
| `--product-name <name>` | 覆盖 `package.product_name` |
| `--version <version>` | 覆盖应用版本，不是选择 Proton 版本 |
| `--format <format>` | 可重复；`app`、`zip`、`dmg`、`nsis`、`appimage`，受主机平台限制 |
| `--output <directory>` | 覆盖输出目录 |
| `--icon <path>` | 可重复；覆盖配置的图标 |
| `--url-scheme <scheme>` | 可重复；覆盖配置的 URL scheme |
| `--nsis-install-mode <mode>` | `currentUser`、`perMachine`、`both`；覆盖 Windows 配置 |
| `--macos-minimum-system-version <version>` | 覆盖 `package.platforms.macos.minimum_system_version` |
| `--sign` | 签名应用，默认关闭 |
| `--notarize` | macOS 签名、公证和 stapling；隐含 `--sign` |
| `--updater-base-url <https-url>` | 使用此产物地址生成更新元数据；要求同时提供发布时间和 revision |
| `--updater-published-at <instant>` | `YYYY-MM-DDTHH:MM:SSZ` 格式的发布时间；要求提供 base URL |
| `--updater-revision <integer>` | 写入应用与更新元数据的单调递增发布序号 |

`--format` 等命令行列表覆盖对应配置列表。应用标识来自配置顶层的 `identifier`，`package` 没有 `--identifier` 选项。`--release` 不隐含签名；dry run 成功不代表产物创建或运行验证成功。平台格式、配置默认值和资源规则见[打包](packaging.md)。

### 签名环境

凭据通过环境配置，不是命令选项。

| 变量 | 含义 |
| --- | --- |
| `PROTON_MACOS_SIGNING_IDENTITY` | macOS 签名所需的身份 |
| `PROTON_MACOS_ENTITLEMENTS` | 可选 entitlements 文件 |
| `PROTON_MACOS_NOTARY_PROFILE` | macOS 公证凭据 profile；回退变量为 `PROTON_NOTARY_PROFILE` |
| `PROTON_MACOS_BUILD_NUMBER` | 可选 bundle version，包含一至三个数字分量 |
| `PROTON_MACOS_ALLOW_ADHOC` | `1` 允许用于本地诊断的 ad-hoc 签名 |
| `PROTON_WINDOWS_CERTIFICATE` | Windows 签名所需的证书路径 |
| `PROTON_WINDOWS_CERTIFICATE_PASSWORD` | 证书密码，默认空字符串 |
| `PROTON_WINDOWS_TIMESTAMP_URL` | 时间戳服务，默认 `http://timestamp.digicert.com`；`none` 禁用 |

## `doctor`

```text
proton_cli doctor [options]
```

检查环境和当前项目，不安装依赖或修复项目文件。诊断失败时返回失败状态。

| 选项 | 含义 |
| --- | --- |
| `--verbose` | 包含详细项目诊断 |
| `--json` | 输出一个 JSON 文档，与 `--quiet` 冲突 |
| `--quiet` | 只输出失败的诊断，与 `--json` 冲突 |
| `--output <path>` | 将报告写入文件 |

## `cef setup`

```text
proton_cli cef setup
```

将当前 Proton 发行版指定的 CEF 运行时和 helper 安装到用户级共享存储，并输出运行时根目录。没有专属选项，不写入项目运行时选择文件，也不选择任意 CEF 版本。缺少安装产物时需要网络访问。

## `cef requirements`

```text
proton_cli cef requirements
```

以 JSON 输出当前发行版内嵌的 CEF 要求。不安装运行时，也不检查正在运行的应用浏览器。没有专属选项。

## `updater public-key`

```text
proton_cli updater public-key --modulus <hex> [--exponent <hex>]
```

校验受信任 RSA 公钥，输出包含位数的注释及 `rsa-sha256:<modulus>:<exponent>` 文本，可用于 `App::update_channel` 的 `public_keys`。

| 选项 | 含义 |
| --- | --- |
| `--modulus <hex>` | 必填 RSA 模数；接受 OpenSSL 输出的 `Modulus=` 前缀 |
| `--exponent <hex>` | 公钥指数，默认 `010001`（65537） |

参数会去除首尾空白，并将十六进制规范化为小写。校验使用运行时的公钥解析器，包括模数尺寸和指数约束。本命令不生成密钥对、不读取 PEM 文件、不签名产物，也不发布更新。

## 退出状态与更新检查

| 状态码 | 含义 |
| --- | --- |
| `0` | 命令成功 |
| `1` | 执行失败，或诊断报告失败 |
| `2` | 参数解析失败 |

除 `version` 外，命令会尝试检查 CLI 更新。`PROTON_NO_UPDATE_CHECK=1` 可关闭检查。更新服务不可用不会阻止命令执行。
