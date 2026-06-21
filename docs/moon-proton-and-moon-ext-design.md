# moon.proton 与 moon.ext 实施设计

## 目标

这是 Proton 配置系统的新设计，不保留旧配置格式的兼容层。

- `moon.proton` 是应用配置文件，替代应用层旧 JSON 配置。
- `moon.ext` 是扩展元数据文件，替代扩展层旧 JSON 元数据。
- 配置语法接近 `moon.mod`、`moon.pkg`、`moon.work`，但由 Proton 自己解析。
- 扩展必须在 MoonBit 代码中显式链接，配置文件不负责自动启用扩展。
- v1 不设计权限系统、不设计 options schema、不设计次级窗口配置。

## 设计原则

- 配置文件只表达稳定、必要、可静态检查的信息。
- runtime 只消费运行所需 manifest，不读取开发、构建、打包字段。
- CLI/tooling 可以读取完整 `moon.proton`，用于 dev/build/package/inspect。
- `moon.mod` 是模块发布元数据的来源，`moon.proton` 不重复维护 `version`、`description`、`license`。
- `moon.ext.package` 是 npm-style 发布包名，不是 MoonBit import path。
- MoonBit import path 由 catalog 根据最近的 `moon.mod.name` 和扩展目录推导。
- 新格式出现不支持字段时直接报错，不做静默忽略或旧格式 fallback。

## 文件职责

### moon.proton

描述一个 Proton 应用：

- 桌面应用专属 metadata：`product_name`、`identifier`
- 主窗口：`window`
- 主入口：`entry`
- 调试开关：`debug`
- 前端开发/构建输入：`frontend`
- 打包输入：`bundle`

`moon.proton` 不声明扩展，不声明权限，不声明次级窗口。

### moon.ext

描述一个 Proton 扩展包：

- 稳定扩展身份：`id`
- JavaScript namespace：`namespace`
- npm-style 发布包名：`package`
- 展示/发现 metadata
- 平台和扩展依赖 metadata

`moon.ext` 不触发自动链接，不配置导出 symbol，不配置 capabilities，不配置 options schema。

### moon.mod

继续作为 MoonBit 模块 metadata 来源。

`moon.proton` 从最近的上级 `moon.mod` 读取：

```text
version
description
license
```

`moon.ext` 从最近的上级 `moon.mod` 读取：

```text
version
description
license
repository
readme
keywords
```

查找规则固定为：从配置文件所在目录向上查找，命中第一个 `moon.mod` 后停止，不跨越最近模块继续合并。

## 语法

新增独立模块 `justjavac/proton_config`，提供语法层 parser，API 参考 `moonbitlang/moon_config` 的形状：

```moonbit
pub fn parse_moon_proton(
  name? : String = "moon.proton",
  source : String,
) -> (Ast, Array[@lexer_basic.Report])

pub fn parse_moon_ext(
  name? : String = "moon.ext",
  source : String,
) -> (Ast, Array[@lexer_basic.Report])

pub fn parse_moon_mod(
  name? : String = "moon.mod",
  source : String,
) -> (Ast, Array[@lexer_basic.Report])
```

支持的 v1 语法：

- 顶层赋值：`key = value`
- 对象：`key: value`
- 字符串
- 整数
- 布尔值：只接受 `true` / `false`
- 数组
- `//` 注释

不支持：

- 浮点数
- `null`
- 裸标识符值
- 表达式
- JSON 兼容模式

`proton_config` 只负责解析语法和保留位置信息；typed decode 和字段校验由调用方负责：

- `bootstrap` 解码 `moon.proton`
- `catalog` 解码完整 `moon.ext`
- `cli/codegen` 只读取 `moon.ext` 中的 `id` 和 `namespace`

## moon.proton 格式

最小配置：

```moonbit
window = {
  title: "Proton App",
  width: 920,
  height: 680,
}

entry = {
  kind: "file",
  value: "app.html",
}
```

完整配置：

```moonbit
product_name = "Proton Demo"
identifier = "com.justjavac.proton.demo"

window = {
  title: "Proton Demo",
  width: 920,
  height: 680,
  size_hint: "none",
}

entry = {
  kind: "asset",
  value: "frontend/dist/index.html",
}

debug = true

frontend = {
  dev_url: "http://localhost:5173",
  dist: "frontend/dist",
  before_dev: "npm run dev -- --host 127.0.0.1",
  before_build: "npm run build",
}

bundle = {
  active: true,
  targets: ["app", "zip"],
  icon: ["icons/icon.ico", "icons/icon.icns", "icons/icon.png"],
  resources: ["resources/**"],
  output: "target/proton-dist",
}
```

### 顶层字段

必填 runtime 字段：

- `window`
- `entry`

可选应用 metadata：

- `product_name`
- `identifier`

可选 runtime 字段：

- `debug`

可选 tooling 字段：

- `frontend`
- `bundle`

明确不支持：

- `version`
- `description`
- `license`
- `name`
- `repository`
- `readme`
- `keywords`
- `extensions`
- `permissions`
- `windows`

### window

```moonbit
window = {
  title: "App",
  width: 900,
  height: 700,
  size_hint: "none",
}
```

规则：

- `title` 必须是非空字符串。
- `width` 和 `height` 必须是正整数。
- `size_hint` 可选，接受 `none`、`fixed`、`min`、`max`，缺省为 `none`。

### entry

```moonbit
entry = {
  kind: "file",
  value: "app.html",
}
```

规则：

- `kind` 接受 `html`、`url`、`file`、`asset`。
- `value` 必须是非空字符串。
- `file` 和 `asset` 的相对路径从 `moon.proton` 所在目录解析。
- `frontend.dev_url` 只在 dev 流程中临时覆盖 entry，不改写配置文件。

### debug

```moonbit
debug = true
```

规则：

- 必须是布尔值。
- 缺省为 `false`。
- `false` 解码为当前 runtime manifest 的 `debug = 0`。
- `true` 解码为当前 runtime manifest 的 `debug = 1`。
- 如果以后需要日志等级，另加 `log_level` 或 `debug_level`，不要复用 bool 字段。

### frontend

`frontend` 是 CLI/tooling 配置，不进入 runtime manifest。

字段：

- `dev_url`：开发模式加载的前端 dev server URL。
- `dist`：生产构建后的前端静态资源目录。
- `before_dev`：`proton dev` 启动前端 dev server 前执行的命令。
- `before_build`：`proton build` 或 `proton package` 前执行的前端构建命令。

规则：

- 路径相对 `moon.proton` 所在目录。
- shell 命令由 CLI 执行，runtime 不执行 shell。
- `frontend.dev_url` 存在时，dev 流程应等待该 URL 可连接。
- `frontend.dist` 不隐式改写生产 entry，生产入口仍由 `entry` 决定。

### bundle

`bundle` 是 CLI/tooling 配置，不进入 runtime manifest。

字段：

- `active`：是否启用打包，缺省为 `false`。
- `targets`：v1 只接受 `app` 和 `zip`。
- `icon`：图标路径列表。
- `resources`：额外资源 glob 列表。
- `output`：打包输出目录，缺省为 `target/proton-dist`。

规则：

- `targets` 不能重复。
- `bundle.active = true` 时，`identifier` 必须存在。
- `bundle.active = true` 时，最近的 `moon.mod.version` 必须存在。
- `resources` glob 展开后必须仍位于项目目录内。
- v1 不配置 MSI、DMG、签名、公证、自动更新等平台细节。

## moon.ext 格式

最小扩展：

```moonbit
id = "examples/attribute-codegen"
namespace = "add"
```

完整扩展：

```moonbit
id = "justjavac/proton-fs"
namespace = "fs"

package = "@justjavac/proton-fs"

display_name = "Filesystem"
description = "Host filesystem access with text, directory, and stream helpers."

platforms = ["windows", "macos", "linux"]
dependencies = []
```

### 顶层字段

必填：

- `id`
- `namespace`

可选发布字段：

- `package`

可选 metadata：

- `version`
- `display_name`
- `description`
- `license`
- `repository`
- `readme`
- `keywords`

可选发现字段：

- `platforms`
- `dependencies`

明确不支持：

- `spec_symbol`
- `capabilities`
- `options_schema`
- `options_schema_path`
- `manifest_key`

### package

`package` 是 npm-style package name，不是 MoonBit import path。

合法示例：

```text
@justjavac/proton-fs
proton-fs
@vendor/proton-dialog
```

校验规则：

- 支持 scoped package：`@scope/name`。
- 支持 unscoped package：`name`。
- `scope` 和 `name` 只能包含小写字母、数字、`-`、`_`、`.`。
- 不允许大写字母、空格、反斜杠、URL、路径穿越片段。

内部模型必须拆成两个字段：

```text
publish_package = moon.ext.package
moonbit_import_path = 从最近 moon.mod.name + 当前包目录推导
```

link plan 和生成的 MoonBit import 只能使用 `moonbit_import_path`。

### 扩展身份

`id` 是唯一稳定扩展身份，用于：

- catalog lookup
- dependency entries
- generated link plans
- duplicate detection
- diagnostics

不配置 `manifest_key`。不配置 `spec_symbol`。生成代码固定调用导入包的 `extension()`。

### dependencies

`dependencies` 表示依赖的扩展 `id`，不是 npm package name，也不是 MoonBit import path。

规则：

- 每一项必须是非空字符串。
- 不允许依赖自身。
- 不允许重复。
- catalog link plan 负责展开传递依赖并检测循环依赖。

### platforms

`platforms` 表示扩展支持的平台。v1 只接受：

```text
windows
macos
linux
```

空数组表示“不声明平台限制”，工具不应解释为“不支持任何平台”。

## API 改动

### bootstrap

公开入口：

```moonbit
pub fn load_proton_manifest_from_file(path : String) -> Result[LoadedAppManifest, String]
pub fn load_config_manifest_from_file(path : String) -> Result[LoadedAppManifest, String]
pub fn load_proton_project_config_from_file(path : String) -> Result[ProtonProjectConfig, String]
pub fn load_proton_project_summary_from_file(path : String) -> Result[Json, String]
pub fn load_runtime_manifest_from_json(text : String) -> Result[LoadedAppManifest, String]
pub fn app_manifest_to_json(manifest : @manifest.AppManifest) -> Json
```

规则：

- `load_config_manifest_from_file` 只接受 `moon.proton`。
- `load_proton_manifest_from_file` 读取 runtime 所需字段。
- `load_proton_project_config_from_file` 读取完整 tooling 配置。
- `load_runtime_manifest_from_json` 和 `app_manifest_to_json` 只用于内部框架进程 handoff，不是用户配置 API。
- 不提供 JSON document 编辑 API。

### proton facade

保留：

```moonbit
@proton.config("moon.proton")
```

暂不新增 `@proton.proton()`。如果以后需要默认查找规则，再单独设计。

配置文件加载后的 inline 覆盖 warning 使用通用文案：

```text
config field "..." is overridden by inline code
```

### catalog

规则：

- discovery 只发现 `moon.ext`。
- 显式传入非 `moon.ext` metadata 文件时直接报错。
- 不加载 schema 文件。
- `ExtensionDescriptor` 不包含 `manifest_key`、`spec_symbol`、`capabilities`、`options_schema_path`。
- descriptor 内部区分 `publish_package` 和 `moonbit_import_path`。
- catalog summary 输出 `metadata_format = "moon.ext"`。

建议公开入口：

```moonbit
pub fn load_extension_catalog_summary_from_search_roots(
  search_roots : Array[String],
) -> Result[Json, String]

pub fn ExtensionCatalog::to_summary_json(self : ExtensionCatalog) -> Json
```

### codegen

`generate_app_commands_from_file_with_metadata` 只读取输入文件同目录的 `moon.ext`。

流程：

1. 读取 `moon.ext`。
2. 提取 `id` 和 `namespace`。
3. 缺少 `moon.ext`、`id` 或 `namespace` 时直接报错。
4. 生成的 command/event API 仍来自 `#proton.command` 和 `#proton.event`。

## 开发流程

目标命令：

```powershell
proton dev
```

建议行为：

1. 解析 `moon.proton`。
2. 校验 runtime 字段和 tooling 字段。
3. 如果配置了 `frontend.before_dev`，由 CLI 在 `moon.proton` 所在目录执行。
4. 如果配置了 `frontend.dev_url`，等待 URL 可连接。
5. 构造 dev manifest：只在内存中用 `Url(dev_url)` 覆盖 entry。
6. 启动应用。

runtime 不读取 `frontend`，也不执行 shell 命令。

## 调试流程

`debug = true` 只表示开启 runtime debug 行为，例如：

- devtools
- bridge diagnostics
- 更详细日志

CLI 可以提供：

```powershell
proton inspect config
proton inspect extensions
```

`inspect config` 复用 `load_proton_project_summary_from_file`，输出规范化 JSON 摘要。

`inspect extensions` 复用 catalog summary，输出已发现扩展、依赖、平台和 import path。

## 构建流程

目标命令：

```powershell
proton build
```

建议行为：

1. 解析 `moon.proton`。
2. 如果配置了 `frontend.before_build`，先执行前端构建命令。
3. 运行最小必要 MoonBit 构建命令，例如 `moon build --target native`。
4. 如果配置了 `frontend.dist`，校验该目录存在。
5. 输出构建摘要：entry、dist、version、identifier、已链接扩展。

Proton 不复制 `moon.pkg` 职责。MoonBit 源码、native stub、link flags、prebuild 脚本继续由 `moon.pkg` / `moon.mod` 管理。

## 打包流程

目标命令：

```powershell
proton package
```

建议行为：

1. 执行 `proton build`。
2. 校验 `bundle.active = true`。
3. 校验 `identifier` 和 `moon.mod.version`。
4. 收集可执行文件、`frontend.dist`、`bundle.resources`、图标和必要 runtime 文件。
5. 输出到 `bundle.output`。
6. 根据 `bundle.targets` 生成 `app` 目录产物或 `zip` 产物。

v1 暂不内建平台安装器、签名、公证和自动更新。它们后续应在真实打包器边界清楚后单独设计。

## 测试流程

基础验证命令：

```powershell
moon check --target native
moon -C cli test codegen --target native
moon -C extensions test --target native
moon -C examples build --target native
moon -C e2e build --target native
moon fmt --check
moon info --target native
```

配置层测试：

- parser 接受合法 `moon.proton` / `moon.ext`。
- parser 保留 source location。
- decoder 报告 duplicate field。
- decoder 拒绝未知字段。
- `moon.proton` 拒绝 `extensions`、`permissions`、`windows`。
- `moon.proton.debug` 只接受 bool。
- 应用发布 metadata 从最近 `moon.mod` 读取。
- 相对路径按配置文件目录解析。

扩展 metadata 测试：

- catalog 只发现 `moon.ext`。
- codegen 从 `moon.ext` 读取 `id` 和 `namespace`。
- `package` 按 npm-style package name 校验。
- `moonbit_import_path` 从最近 `moon.mod.name` 和扩展包目录推导。
- `dependencies` 使用扩展 `id`，能检测缺失依赖、自依赖、重复依赖和循环依赖。

e2e smoke：

- `@proton.config("moon.proton")` 能启动窗口。
- `debug = true` 时 debug 行为可见。
- `frontend.dev_url` 能在 dev 模式临时覆盖 entry。
- `frontend.dist` 能进入 package 产物。
- 打包后的 `app` 或 `zip` 产物可以运行基础页面。

## 分发字段来源

```text
product_name = moon.proton.product_name ?? window.title
identifier = moon.proton.identifier
version = moon.mod.version
description = moon.mod.description
license = moon.mod.license
```

建议产物命名：

```text
{product_name}-{version}-{platform}-{arch}.{ext}
```

示例：

```text
Proton Demo-0.1.0-windows-x64.zip
Proton Demo-0.1.0-macos-arm64.zip
```

## 实施阶段

### Phase 1: 配置 parser

- 新建独立模块目录 `proton_config`。
- 实现 `Ast`、source location、parser reports。
- 提供 `parse_moon_proton`、`parse_moon_ext` 和 `parse_moon_mod`。
- 添加 parser 单元测试。

### Phase 2: moon.proton

- 在 `bootstrap` 中实现 `moon.proton` decoder。
- 新增 `ProtonProjectConfig`、`ProtonFrontendConfig`、`ProtonBundleConfig`、`ProtonAppMetadata`。
- `@proton.config(path)` 和 `create_app_from_file(path)` 只接受 `moon.proton`。
- 删除旧 JSON document/control-plane API。
- 示例迁移到 `moon.proton`。

### Phase 3: moon.ext

- 在 `catalog` 中实现 `moon.ext` decoder。
- discovery 只读取 `moon.ext`。
- 删除扩展旧 JSON metadata 文件。
- codegen 只读取 `moon.ext`。
- 内置扩展全部补齐 `moon.ext`。

### Phase 4: inspect/check CLI

- 实现 `proton check`。
- 实现 `proton inspect config`。
- 实现 `proton inspect extensions`。
- CLI 复用 `bootstrap` 和 `catalog` 的 decoder，不重复实现配置解析。

### Phase 5: dev/build/package CLI

- 实现 `proton dev`。
- 实现 `proton build`。
- 实现 `proton package`。
- 先支持 `app` 和 `zip`，不扩展平台安装器。

## 验收标准

- `@proton.config("moon.proton")` 能加载配置。
- 非 `moon.proton` 路径作为应用配置会报错。
- `debug = true` 解码为当前 runtime 的 `debug = 1`。
- `moon.proton` 不接受 `version`、`license`、`description`。
- `moon.proton` 不接受 `extensions`、`permissions`、`windows`。
- `load_proton_project_config_from_file` 能读取 `frontend`、`bundle` 和最近 `moon.mod` metadata。
- `bundle.active = true` 且缺少 `identifier` 或 `moon.mod.version` 时会报错。
- catalog 只发现 `moon.ext`。
- 显式读取旧扩展 metadata 文件会报错。
- `moon.ext.package` 是 npm-style package name，不参与 MoonBit import。
- link plan 使用 `moonbit_import_path`，生成代码固定调用 `extension()`。
- codegen 能从 `moon.ext` 读取 `id` 和 `namespace`。
- 仓库内不保留旧扩展 metadata fixture。
- `moon check --target native` 通过。
- 相关 `moon info` 生成的 public API 符合本设计。

## 参考

- Tauri v2 配置参考：<https://v2.tauri.app/reference/config/>
- Tauri v2 capabilities 设计：<https://v2.tauri.app/security/capabilities/>
- `moonbitlang/moon_config@0.3.4` API：<https://mooncakes.io/docs/moonbitlang/moon_config@0.3.4/>
