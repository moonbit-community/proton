# 项目配置

`proton.project.json` 包含应用身份及 CLI 构建／打包元数据。顶层是 JSON 对象，只接受以下五个字段；未知字段会被拒绝。窗口状态、命令注册和能力声明属于 MoonBit 应用构建器，不属于此配置文件。

默认文件名为 `proton.project.json`。若使用 `moon.proton.json` 等其他名称，需给 `dev`、`build` 或 `package` 显式传递 `--config moon.proton.json`；它不是自动发现的别名。

下述根级平台覆盖格式尚未发布；从 0.6.0 升级时请参照迁移说明。

## 顶层字段

| 字段 | 类型 | 要求与含义 |
| --- | --- | --- |
| `identifier` | string | 必填，经过校验的应用标识 |
| `backend` | object | 解码时可省略，提供 CLI 后端位置与入口 |
| `frontend` | object | 可省略，前端命令及资源配置 |
| `package` | object | 可省略，分发元数据；基于元数据打包时需要 |
| `platforms` | object | 可省略，宿主平台覆盖：`macos`、`windows`、`linux` |

`identifier` 会去除首尾空白，必须包含至少两个非空的点分段。每段以 ASCII 字母或数字开头，仅允许 ASCII 字母、数字和连字符。

最小配置为：

```json
{
  "identifier": "com.example.app",
  "backend": { "path": ".", "package": "app" }
}
```

## 后端

存在 `backend` 时，两个字段均为必填。

| 字段 | 类型 | 解释 |
| --- | --- | --- |
| `path` | string | 相对于配置文件目录解析的目录 |
| `package` | string | 在该目录执行 Moon 时使用的包选择器 |

## 前端

解码时，所有前端字段均可省略。具体 CLI 命令会提出额外要求。

| 字段 | 类型 | 默认值与解释 |
| --- | --- | --- |
| `path` | string | 省略时为配置文件目录；前端命令的工作目录 |
| `dev_url` | string | 无默认值；开发页面 URL |
| `before_dev` | string | 无默认值；前端服务器命令 |
| `before_build` | string | 无默认值；前端构建命令 |
| `dist` | string | 无默认值；指定 `frontend.path` 时，相对于该目录解析的输出目录 |

`dev` 管理配置的开发 URL 时要求提供前端命令。`--no-frontend` 连接外部管理的服务器。`build` 先执行配置的构建命令，再验证前端输出并构建后端。CLI 负责启动服务器时，会拒绝已被占用的开发端点。

## 路径与资源

后端／前端路径、打包图标、资源和输出目录相对于配置文件目录解析。`frontend.dist` 相对于前端目录解析。绝对路径保持绝对路径。路径分隔符遵循宿主操作系统的规则。加载配置保留路径原文，不要求所引用的文件或目录已经存在；构建和打包操作检查各自实际使用的输入。

`@proton.resource_dir()` 是应用资源基准目录：开发时 CLI 提供项目根目录；打包后为应用资源目录；没有托管元数据的直接运行使用启动工作目录。安装资源不属于持久可写数据存储。

## `package`

以下字段属于 `proton.project.json` 的 `package` 对象。

| 字段 | 类型 | 默认值与含义 |
| --- | --- | --- |
| `product_name` | string | 必填，显示名称 |
| `version` | string | 必填，应用版本，独立于 Proton 版本 |
| `formats` | string array | 省略时使用宿主平台默认格式 |
| `icons` | string array | 空；图标路径相对于配置文件目录 |
| `prepare` | string | 无；准备命令 |
| `resources` | string array | 空；附加打包资源 |
| `sign.binaries` | string array | 空；额外选择签名的二进制文件，或 macOS 的 `dir/**` 目录树 |
| `url_schemes` | string array | 空；应用注册的 URL scheme |
| `document_types` | object array | 空；文档关联 |
| `output` | string | `dist`，相对于配置文件目录 |

文档类型包含必填的 `name`、`extensions`，`role` 默认为 `Viewer`。规范应用标识位于顶层 `identifier`，不是 package 字段。修改产品名称不会改变应用身份。

使用自动更新时，`package.version` 同时决定发布顺序，必须使用三个无前导零、无后缀的非负 `Int32` 分量，每次更新严格递增。`package --version` 同时覆盖打包应用与更新元数据中的版本，不存在 `revision` 字段。参见[更新元数据](../command-line-interface/packaging.md#更新产物与元数据)。

## `package.sign`

| 字段 | 类型 | 默认值与含义 |
| --- | --- | --- |
| `binaries` | string array | `[]`；额外签名的二进制文件，路径相对于配置文件目录 |

每一项都是必须存在于包内的确切目标，`.app` 或 `.framework` 目录按单个目标签名。在 macOS 上，以 `/**` 结尾的项表示目录树：打包时 Proton 会由内向外签名该目录下的所有 Mach-O 可执行文件、库和 bundle，并跳过符号链接和目标文件。其他 glob 写法会被拒绝。带签名的 Windows 打包会拒绝目录树，如果同一份配置也要为 Windows 签名，请把目录树写在 `platforms.macos.package.sign` 下。

省略 `sign` 时不添加额外二进制文件。此对象不会启用签名；启用签名使用 `package --sign` 或 `--notarize`。

## `package.document_types[]`

| 字段 | 类型 | 默认值与含义 |
| --- | --- | --- |
| `name` | string | 必填，文档类型显示名称 |
| `extensions` | string array | 必填，非空的文件扩展名列表 |
| `role` | string | `Viewer`；传递给打包器的文档角色 |

## 平台覆盖

根级 `platforms` 是唯一的平台覆盖入口。`macos`、`windows`、`linux` 对象可以包含
部分 `backend`、`frontend`、`package` 字段。平台指运行 CLI 的操作系统，不是 MoonBit
编译目标。不会加载额外的平台配置文件。

解析顺序为通用字段、宿主平台覆盖、显式 CLI 参数。对最终省略的字段应用默认值；
所有平台分支都会经过校验，包括当前未选中的平台。未知字段会报错。

- 未指定的字段继承通用值。
- 对象按字段覆盖；数组整体替换，包括 `resources` 和 `sign.binaries`，不再追加。
- 显式 `null` 清除可选字段，例如 `before_build`、`prepare`、`sign`。
  必填字段和数组不接受 `null`。
- `identifier` 和 `package.version` 跨平台共用，不能覆盖；不允许嵌套 `platforms`。
- 最终 `formats` 为空数组时，使用宿主平台默认格式。

平台专属打包字段如下：

| 字段 | 类型 | 默认值与含义 |
| --- | --- | --- |
| `platforms.macos.package.minimum_system_version` | string | 未设置；`major.minor[.patch]`，写入 `LSMinimumSystemVersion`。不改变编译目标，也不校验二进制兼容性 |
| `platforms.windows.package.nsis_install_mode` | string | `currentUser`；接受 `currentUser`、`perMachine`、`both` |

其它打包覆盖使用通用 package 的字段名称，但不能覆盖 `version`。
平台专属字段放在其它平台或通用配置中会被拒绝。参见[打包行为](../command-line-interface/packaging.md)。

## 命令工作目录

`frontend.path` 是两条前端命令共用的工作目录；省略时使用配置文件目录。
`package.prepare` 始终在配置文件目录执行。命令保持为 shell 字符串：Windows 使用
`cmd /d /c`，macOS/Linux 使用 `sh -c`。子进程继承 CLI 环境；Proton 不会自动将
项目的工具目录加入 `PATH`。

命令内部的路径由 shell 相对于工作目录解释。如果项目根目录中的 `tools/warren`
与 `frontend/` 并列，且 `frontend.path` 为 `frontend`，命令应写为
`../tools/warren build`；Windows 的 JSON 覆盖写为 `..\\tools\\warren.exe build`。
程序路径和参数必须遵循宿主 shell 的语法。`--frontend-path` 覆盖前端工作目录；
`--command` 只替换开发命令，保留工作目录。改变前端目录也会改变 `frontend.dist`
的解析基准，不影响打包资源和输出目录的基准。

## 从 0.6.0 迁移

根级平台覆盖尚未发布。升级到包含此格式的版本时，将 `package.platforms.<平台>.*`
迁移为 `platforms.<平台>.package.*`。旧位置会给出迁移错误。
此前平台资源和签名输入会追加到通用数组；现在应在覆盖中列出完整目标数组。

## 配置职责与目录布局

Proton 不要求使用 minimal 或 isomorphic 模板的目录布局。CLI 根据本文件定位后端、前端和资源；各路径的解析规则见本页“路径与资源”。

| 文件或入口 | 职责 |
| --- | --- |
| moon.mod | 模块名称和版本化依赖 |
| moon.pkg | 包导入、目标及可执行入口声明 |
| moon.work（使用多个模块时） | 将模块组织为工作区 |
| proton.project.json | 应用身份、CLI 构建路径与打包元数据 |
| MoonBit App 构建器 | 窗口、命令、capability 和生命周期行为 |

模块依赖使模块可用，包导入选择当前包使用的 API。项目配置中的 backend.package 选择构建入口，不代替 Moon 的包声明。

## 构建输出

Moon 默认将构建产物写入 _build/。前端输出位置取决于前端构建工具，应与 frontend.dist 对应；frontend/dist 是 isomorphic 模板的选择，不是框架固定路径。打包器将分发产物写入 package.output，默认 dist。

这些目录保存生成产物，内容由源码、构建命令和项目配置决定。setup 安装的运行时与 helper 位于用户级共享存储，不属于应用源码目录。

## 完整配置示例

以下路径用于说明字段组织方式；项目必须实际提供引用的图标、资源和命令。

```json
{
  "identifier": "com.example.notes",
  "backend": {
    "path": "backend",
    "package": "app"
  },
  "frontend": {
    "path": "frontend",
    "dev_url": "http://127.0.0.1:4300",
    "before_dev": "../tools/warren dev --browser-entry main --direct --port 4300",
    "before_build": "../tools/warren build --browser-entry main",
    "dist": "dist"
  },
  "package": {
    "product_name": "Notes",
    "version": "1.0.0",
    "formats": ["app", "zip"],
    "icons": ["icons/app.icns", "icons/app.ico", "icons/app.png"],
    "prepare": "node scripts/prepare.mjs",
    "resources": ["resources"],
    "sign": {
      "binaries": []
    },
    "url_schemes": ["notes"],
    "document_types": [
      {
        "name": "Note",
        "extensions": ["note"],
        "role": "Editor"
      }
    ],
    "output": "dist"
  },
  "platforms": {
    "macos": {
      "package": {
        "formats": ["app", "dmg"]
      }
    },
    "windows": {
      "package": {
        "formats": ["nsis"],
        "nsis_install_mode": "currentUser"
      },
      "frontend": {
        "before_dev": "..\\tools\\warren.exe dev --browser-entry main --direct --port 4300",
        "before_build": "..\\tools\\warren.exe build --browser-entry main"
      }
    },
    "linux": {
      "package": {
        "formats": ["appimage"]
      }
    }
  }
}
```

## 运行时配置

先独立加载配置，再将它安装到应用：

```moonbit
let config = @proton.load_config()
let app = @proton.html("Hello", "<h1>Hello</h1>")..config(config)

if config.frontend is Some(frontend) {
  if frontend.dev_url is Some(url) {
    println(url)
  }
}
```

`load_config()` 解析宿主平台覆盖，返回生效的类型化 `AppConfig`，失败时立即抛出
`AppConfigError`。开发环境读取 `proton.project.json`，打包环境读取
`proton-package.json`。需要指定路径时，使用 `@proton.AppConfig::load(path)`；
也可以直接构造 `AppConfig`。

从配置值直接读取字段。嵌套章节是可选结构体：`config.frontend` 包含
`dev_url`、`path`、`dist`、`before_dev` 和 `before_build`。
生效的 `package_config` 还包含 `minimum_system_version` 和 `nsis_install_mode`。
`AppConfig` 不保留未选中的平台定义；`to_json()` 输出可再次读取的生效配置快照。
JSON 中的 `package` 对应 `config.package_config`，`backend.package`
对应 backend 的 `app_package` 字段。

`proton_cli dev` 提供经过 `--url`、`--command`、`--frontend-path` 和
`--package` 覆盖的生效配置。打包也会嵌入生效配置，包括格式和平台选项的
命令行覆盖值。相对路径保持原样；读取字段不会解析路径或执行命令。

`app..config(config)` 安装独立副本，与 `app..identifier(...)` 互斥。
无效配置或与包内身份不一致的 identifier 会阻止启动。保留 `config` 即可查询
配置，应用不再提供配置 getter。`app.name()` 和 `app.version()` 读取安装的
快照，不再访问文件。
