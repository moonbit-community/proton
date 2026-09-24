# Configuration

`proton.project.json` 包含应用身份及 CLI 构建／打包元数据。顶层是 JSON 对象，只接受以下四个字段；未知字段会被拒绝。窗口状态、命令注册和能力声明属于 MoonBit 应用构建器，不属于此配置文件。

默认文件名为 `proton.project.json`。若使用 `moon.proton.json` 等其他名称，需给 `dev`、`build` 或 `package` 显式传递 `--config moon.proton.json`；它不是自动发现的别名。

`identifier` 会去除首尾空白，必须包含至少两个非空的点分段。每段以 ASCII 字母或数字开头，仅允许 ASCII 字母、数字和连字符。

## 顶层字段

| 字段 | 类型 | 要求与含义 |
| --- | --- | --- |
| `identifier` | string | 必填，经过校验的应用标识 |
| `backend` | object | 解码时可省略，提供 CLI 后端位置与入口 |
| `frontend` | object | 可省略，前端命令及资源配置 |
| `package` | object | 可省略，分发元数据；基于元数据打包时需要 |

最小配置形状为：

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

后端／前端路径、打包图标、资源和输出目录相对于配置文件目录解析。`frontend.dist` 相对于前端目录解析。绝对路径保持绝对路径。

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
| `sign.binaries` | string array | 空；额外选择签名的二进制文件 |
| `url_schemes` | string array | 空；应用注册的 URL scheme |
| `document_types` | object array | 空；文档关联 |
| `output` | string | `dist`，相对于配置文件目录 |
| `platforms` | object | 可选的 `macos`、`windows`、`linux` 覆盖 |

文档类型包含必填的 `name`、`extensions`，`role` 默认为 `Viewer`。规范应用标识位于顶层 `identifier`，不是 package 字段。修改产品名称不会改变应用身份。

## `package.sign`

| 字段 | 类型 | 默认值与含义 |
| --- | --- | --- |
| `binaries` | string array | `[]`；额外签名的二进制文件，路径相对于配置文件目录 |

省略 `sign` 时不添加额外二进制文件。此对象不会启用签名；启用签名使用 `package --sign` 或 `--notarize`。

## `package.document_types[]`

| 字段 | 类型 | 默认值与含义 |
| --- | --- | --- |
| `name` | string | 必填，文档类型显示名称 |
| `extensions` | string array | 必填，非空的文件扩展名列表 |
| `role` | string | `Viewer`；传递给打包器的文档角色 |

## `package.platforms`

| 字段 | 类型 | 默认值与含义 |
| --- | --- | --- |
| `macos` | object | 无；macOS 覆盖配置 |
| `windows` | object | 无；Windows 覆盖配置 |
| `linux` | object | 无；Linux 覆盖配置 |

各平台对象接受以下字段。未知字段会被拒绝，包括在非 Windows 对象中设置 `nsis_install_mode`。

| 字段 | 类型 | 默认值与含义 |
| --- | --- | --- |
| `formats` | string array | 继承共享的 `package.formats`；显式列表替换共享列表 |
| `resources` | string array | `[]`；追加到共享资源列表并去重 |
| `sign` | object | 无；只接受 `binaries`（string array，默认 `[]`），追加到共享签名列表并去重 |
| `nsis_install_mode` | string | 仅 Windows；`currentUser`（默认）、`perMachine` 或 `both` |
| `minimum_system_version` | string | 仅 macOS；格式为 `major.minor[.patch]`。设置 `LSMinimumSystemVersion`；未配置时省略该字段。不改变编译目标，也不验证二进制兼容性。 |

合并后的格式列表为空时采用宿主平台默认格式。CLI 选项覆盖解析后的配置。支持的格式、签名和安装模式见[打包行为](../command-line-interface/packaging.md)。

## 完整配置示例

以下路径用于说明字段组织方式；项目必须实际提供引用的图标、资源和命令。

```json
{
  "identifier": "com.example.notes",
  "backend": { "path": "backend", "package": "app" },
  "frontend": {
    "path": "frontend",
    "dev_url": "http://127.0.0.1:4300",
    "before_dev": "warren dev --browser-entry main --direct --port 4300",
    "before_build": "warren build --browser-entry main",
    "dist": "dist"
  },
  "package": {
    "product_name": "Notes",
    "version": "1.0.0",
    "formats": ["app", "zip"],
    "icons": ["icons/app.icns", "icons/app.ico", "icons/app.png"],
    "prepare": "node scripts/prepare.mjs",
    "resources": ["resources"],
    "sign": { "binaries": [] },
    "url_schemes": ["notes"],
    "document_types": [
      { "name": "Note", "extensions": ["note"], "role": "Editor" }
    ],
    "output": "dist",
    "platforms": {
      "macos": { "formats": ["app", "dmg"] },
      "windows": { "formats": ["nsis"], "nsis_install_mode": "currentUser" },
      "linux": { "formats": ["appimage"] }
    }
  }
}
```
