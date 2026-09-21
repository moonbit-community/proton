# 项目配置

[English](../configuration.html)

`proton.project.json` 包含应用身份及 CLI 构建／打包元数据。顶层是 JSON 对象，只接受以下四个字段；未知字段会被拒绝。窗口状态、命令注册和能力声明属于 MoonBit 应用构建器，不属于此配置文件。

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

## 打包字段

`package` 的完整字段、平台覆盖规则和产物格式见[打包参考](packaging.md)。

## 0.3.0 的 Warren 命令

已发布的 CLI 0.3.0 生成已弃用的 native `moonx` 命令。替代方式是调用已安装的 `moonbit-community/warren@0.3.3` 可执行文件，前端字段为：

```json
{
  "path": "frontend",
  "dev_url": "http://127.0.0.1:4300",
  "before_dev": "warren dev --browser-entry main --direct --port 4300",
  "before_build": "warren build --browser-entry main",
  "dist": "dist"
}
```

该对象是 `frontend` 的值，不是完整项目配置。修正后的生成器已进入 main，尚未包含在已发布的 CLI 0.3.0 中。Warren 0.3.2 没有已发布的 Wasm 可执行文件，因此不能仅删除 native 目标参数。安装要求见[运行环境](installation.md)。
