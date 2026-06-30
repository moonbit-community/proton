# `proton new` 命令规划

本文记录 `proton new` 脚手架命令的设计方案、实施步骤和落地策略。它是规划文档，不是实现代码。

## 目标

- 一条命令创建可运行的 Proton native 桌面应用。
- 生成内容尽量贴近 `moon new` 的 MoonBit 项目习惯。
- 只使用当前 native DLL runtime 路线。
- 使用 `@proton.asset(...)` 读取静态 HTML 文件，不生成 embed 规则。
- 默认模板就是 counter 示例：主应用使用 `extensions/counter` 扩展。
- `extensions/` 目录只放扩展包，不放可执行示例。
- 本地开发交互友好，CI 环境行为可预测。

## 命令形态

```sh
proton new [PATH] [options]
```

支持参数：

```text
--title <TITLE>      应用、窗口和产品标题。
--module <MODULE>    moon.mod 模块名。
--width <PX>         窗口宽度，默认 960。
--height <PX>        窗口高度，默认 640。
--check              创建后运行 moon check，默认启用。
--no-check           创建后不运行 moon check。
-y, --yes            接受默认值，跳过交互式询问。
--git                初始化 git 仓库。
--no-git             不初始化 git 仓库。
--dry-run            只打印将要生成的文件，不写入磁盘。
```

不使用 `--name`。`moon new --name` 中的 `name` 表示模块名，`proton new` 使用 `--title` 表示应用标题，避免语义冲突。

## 默认值

默认项目路径：

```text
counter
```

如果用户传入 `PATH`，取路径最后一段作为 project slug。

示例：

```text
PATH: counter       -> title: Counter, module: counter
PATH: my-counter    -> title: My Counter, module: my-counter
PATH: tools/counter -> title: Counter, module: counter
PATH: .             -> 使用当前目录名推导 title/module
```

格式转换使用 `justjavac/case`，不要手写零散字符串替换规则。
模板渲染使用 `justjavac/template`，不要手写大量 `replace` 或拼接式渲染逻辑。

规则：

- `title` 默认由 project slug 转为 Title Case。
- `module` 默认等于 project slug。
- 用户传入 `--title` 时，原样使用，不再转换。
- 用户传入 `--module` 时，校验后原样使用。
- `moon.proton.product_name`、`moon.proton.window.title` 和 `app/main.mbt` 里传给 `@proton.asset(...)` 的标题都使用最终 title。

## 交互规则

交互式模式只在以下条件同时满足时启用：

```text
interactive = !yes && !@ci.is_ci()
```

使用 `justjavac/ci` 判断 CI 环境。实现前用 `moon ide doc` 确认准确 API。

交互式问题：

```text
Project directory [counter]:
App title [Counter]:
Module name [counter]:
Window width [960]:
Window height [640]:
Run moon check after creation [Y/n]:
```

写入文件前展示确认摘要：

```text
Project directory: my-counter
App title: My Counter
Module name: my-counter
Window: 960x640
Counter extension: extensions/counter
Run moon check: yes

Create project? [Y/n]:
```

CI 环境或传入 `-y/--yes` 时跳过全部 prompt，直接使用解析后的默认值。

## 生成目录结构

生成：

```text
my-app/
  AGENTS.md
  LICENSE
  README.mbt.md
  .gitignore
  moon.mod
  moon.proton
  app/
    moon.pkg
    main.mbt
    app.html
  extensions/
    counter/
      moon.pkg
      counter.mbt
      README.mbt.md
```

不生成：

```text
.github/workflows/copilot-setup-steps.yml
.githooks/
```

## 项目文件设计

### `moon.mod`

生成项目应 native-first，并包含 app 和 counter extension 所需依赖：

```moonbit
name = "my-counter"

version = "0.1.0"

import {
  "moonbitlang/async@<version>",
  "justjavac/proton@<version>",
}

readme = "README.mbt.md"

repository = ""

license = "MIT"

keywords = [ "proton", "gui", "web", "desktop-app" ]

description = "A Proton desktop app."

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
```

依赖版本在 `proton new` 实现中集中定义，发布时只需要更新一个位置。

### `moon.proton`

生成：

```moonbit
product_name = "My Counter"

window = {
  title: "My Counter",
  width: 960,
  height: 640,
  size_hint: "none",
}

entry = {
  kind: "asset",
  value: "app/app.html",
}

debug = true
```

初始 `app/main.mbt` 可以不直接读取 `moon.proton`，但文件应生成，供后续 `dev/build/bundle/doctor` 等工具链使用。

### `app/moon.pkg`

生成可执行包：

```moonbit
import {
  "moonbitlang/async",
  "justjavac/proton",
  "my-counter/extensions/counter" @counter,
}

supported_targets = "native"

options(
  "is-main": true,
  targets: { "main.mbt": [ "native" ] },
)
```

`counter` import 使用最终 module name。

### `app/main.mbt`

生成：

```moonbit
///|
async fn main {
  @proton.asset(
    "My Counter",
    "app/app.html",
    width=960,
    height=640,
    debug=true,
  ).extension(@counter.extension()).run_or_abort()
}
```

默认 app 演示 counter extension。用户运行：

```sh
moon run app --target native
```

### `app/app.html`

默认 HTML 是 counter UI。它应当：

- 展示当前计数。
- 提供 increment、reset 按钮。
- 等待 `window.__MoonBit__.core.invokeOp` 可用后再启用按钮。
- 调用 `ext:counter/get`、`ext:counter/increment`、`ext:counter/reset`。
- 在 UI 上显示 bridge 状态和错误信息。
- 保持静态 HTML、CSS、JavaScript，不依赖前端构建工具。

调用示例：

```js
window.__MoonBit__.core.invokeOp("ext:counter/increment", {})
```

### `extensions/counter`

`extensions/counter` 是扩展包，不是可执行包，不包含 `main.mbt`，不能 `moon run extensions/counter`。

`extensions/counter/moon.pkg`：

```moonbit
import {
  "moonbitlang/core/json",
  "justjavac/proton/command" @proton_command,
  "justjavac/proton/extension" @proton_extension,
}

supported_targets = "native"
```

`extensions/counter/counter.mbt` 对外提供：

```moonbit
pub fn extension() -> @proton_extension.Extension
```

扩展 namespace 为：

```text
counter
```

命令：

- `get`：返回当前计数。
- `increment`：计数加一并返回新计数。
- `reset`：归零并返回当前计数。

这个示例演示 native extension command bridge，同时保持扩展包可复用。

## 支持文件

### `AGENTS.md`

生成 Proton 专用 `AGENTS.md`，至少包含：

- 这是 MoonBit Proton 应用。
- 使用 `moon fmt` 格式化。
- 使用 `moon check --target native --diagnostic-limit 80` 检查。
- 使用 `moon run app --target native` 运行 app。
- 若 runtime 未配置，先运行 `proton_cli cef setup`。
- `extensions/` 包含扩展包，不是 runnable app。
- 不要重新引入旧 WebSocket app runtime 路线。

### `.gitignore`

生成：

```gitignore
.DS_Store
_build/
target/
target
.mooncakes/
.moonagent/
.proton/
```

### `README.mbt.md`

包含：

设置：

```sh
moon update
proton_cli cef setup
```

检查：

```sh
moon check --target native --diagnostic-limit 80
```

运行：

```sh
moon run app --target native
```

说明：

- `app/` 是可运行应用。
- `extensions/counter/` 是被 app 使用的 counter extension 包。
- `extensions/counter/` 不能直接运行。

## 创建后校验

除非传入 `--no-check`，写完文件后运行：

```sh
moon -C <project-dir> check --target native --diagnostic-limit 80
```

如果 check 失败：

- 保留已生成文件。
- 命令返回非零状态。
- 打印重试命令：

```sh
cd <project-dir>
moon check --target native --diagnostic-limit 80
```

不要自动运行 `moon update`。它可能访问网络，应由用户显式执行。

## 目录安全规则

- 目标目录不存在：创建目录。
- 目标目录存在且为空：允许使用。
- 目标目录存在且非空：失败。
- 目标目录已有 `moon.mod`：失败并给出明确提示。
- `--yes` 不是 force，只是跳过交互。
- 初版不提供 `--force`。

错误示例：

```text
error: target directory is not empty: my-counter

Choose a different directory:
  proton_cli new my-counter-2

Or remove files manually and retry.
```

## 实现位置

新增独立 CLI 子模块：

```text
cli/
  new/
    moon.pkg
    new_project.mbt
    templates.mbt
    templates.generated.mbt
    prompt.mbt
    validation.mbt
    new_project_wbtest.mbt
    templates/
      counter/
        files/
          moon.mod.mtpl
          moon.proton.mtpl
          app/
            moon.pkg.mtpl
            main.mbt.mtpl
            app.html.mtpl
          extensions/
            counter/
              moon.pkg.mtpl
              counter.mbt.mtpl
              README.mbt.md.mtpl
          AGENTS.md.mtpl
          README.mbt.md.mtpl
          .gitignore.mtpl
          LICENSE.mtpl
scripts/
  generate_new_templates.mjs
```

在 `cli/main.mbt` 中用别名导入：

```moonbit
import {
  "justjavac/proton_cli/new" @new_project,
}
```

`cli/main.mbt` 只负责顶层命令分发；参数解析、prompt、模板渲染、目录写入、check 执行都放在 `cli/new/`。

## CLI 实现依赖

CLI 模块需要新增：

- `justjavac/ci`：判断 CI，决定是否启用交互式模式。
- `justjavac/case`：把路径 slug 转为默认 title。
- `justjavac/template`：渲染脚手架文件模板。

实现前用 `moon ide doc` 确认这些包的 API。

## 详细实施步骤

### 阶段 1：确认依赖 API 和现有 CLI 风格

1. 使用 `moon ide doc` 查询 `justjavac/ci` 的 CI 判断 API。
2. 使用 `moon ide doc` 查询 `justjavac/case` 的大小写转换 API。
3. 使用 `moon ide doc` 查询 `justjavac/template` 的模板编译、渲染、变量传递和错误报告 API。
4. 阅读 `cli/main.mbt` 中已有 `doctor`、`codegen`、`cef setup` 的参数解析和错误处理方式。
5. 确认 `moonbitlang/core/argparse` 当前用法，保持新命令的解析风格和现有 CLI 一致。

产出：

- 确定 `ci_is_ci()` 包装函数。
- 确定 `slug_to_title()` 的实现方式。
- 确定 `render_template(name, context)` 的包装函数。
- 确定 `new` 命令入口函数签名。

### 阶段 2：建立 `cli/new` 子模块骨架

1. 新建 `cli/new/moon.pkg`。
2. 添加所需 import：
   - `moonbitlang/core/argparse`
   - `moonbitlang/async/process` 或现有 CLI 使用的 process API
   - `moonbitlang/x/fs` 或现有文件系统 API
   - `justjavac/ci`
   - `justjavac/case`
   - `justjavac/template`
3. 新建 `new_project.mbt`，定义对外入口，例如：

   ```moonbit
   pub async fn run(cwd : String, args : Array[String]) -> Result[Unit, String]
   ```

4. 新建 `validation.mbt`，放路径、模块名、尺寸等校验逻辑。
5. 新建 `templates.mbt`，集中管理模板上下文、渲染入口和生成文件计划。
6. 新建 `cli/new/templates/counter/` 模板源目录，模板文件统一放在 `files/**/*.mtpl`。
7. 新建 `scripts/generate_new_templates.mjs`，把模板源目录编译成 `templates.generated.mbt`。
8. 新建 `prompt.mbt`，封装交互式输入。

策略：

- 先让子模块能被 `moon check` 通过。
- 先不要接入 `cli/main.mbt`，降低调试面。
- 运行时不直接读取 `cli/new/templates/`，避免发布后的路径依赖；模板源通过生成文件进入 CLI 包。

### 阶段 3：实现配置解析和默认值归一

定义内部配置类型，例如：

```moonbit
struct NewProjectOptions {
  target_dir : String
  title : String
  module_name : String
  width : Int
  height : Int
  run_check : Bool
  yes : Bool
  git : Bool?
  dry_run : Bool
}
```

实现步骤：

1. 解析 CLI 参数，得到 raw options。
2. 从 `PATH` 或默认值 `counter` 推导 project slug。
3. 用 `justjavac/case` 推导默认 title。
4. 生成初始 `NewProjectOptions`。
5. 判断 `interactive = !yes && !@ci.is_ci()`。
6. 如果 interactive，逐项 prompt 并允许回车使用默认值。
7. prompt 完成后再次校验。

策略：

- 参数解析和默认值解析分开，方便测试。
- prompt 只改写配置，不负责校验业务规则。
- 校验错误统一返回 `Err(String)`。

### 阶段 4：实现模板源目录和生成资源

脚手架模板采用“模板源目录 + 生成 MoonBit resource”的模式，参考 `moon new`、`tauri init`、`zero-native new` 这类实现：模板以普通文件存在于仓库中，便于阅读、维护和 review；构建前由脚本生成 `templates.generated.mbt`，CLI 运行时只依赖已生成的 MoonBit 代码，不依赖源码目录。

模板渲染必须基于 `justjavac/template`。`templates.mbt` 不应手写大量字符串拼接；它负责管理模板上下文、调用模板替换 API、检查未解析占位符，并把生成资源转换为 `PlannedFile`。

建议组织：

```moonbit
struct TemplateContext {
  title : String
  module_name : String
  width : Int
  height : Int
  proton_version : String
  async_version : String
}

struct TemplateSpec {
  output_path : String
  template_name : String
  template_source : String
}
```

模板源目录：

```text
cli/new/templates/counter/
  files/
    moon.mod.mtpl
    moon.proton.mtpl
    app/moon.pkg.mtpl
    app/main.mbt.mtpl
    app/app.html.mtpl
    extensions/counter/moon.pkg.mtpl
    extensions/counter/counter.mbt.mtpl
    extensions/counter/README.mbt.md.mtpl
    AGENTS.md.mtpl
    README.mbt.md.mtpl
    .gitignore.mtpl
    LICENSE.mtpl
```

生成产物：

```text
cli/new/templates.generated.mbt
```

实现步骤：

1. 在 `cli/new/templates/counter/files/` 下定义所有模板源文件。
2. 用 `scripts/generate_new_templates.mjs` 扫描 `*.mtpl`，生成 `generated_template_specs()`。
3. 生成时把 `.mtpl` 后缀去掉作为输出路径，例如 `app/main.mbt.mtpl` 输出为 `app/main.mbt`。
4. 把 `NewProjectOptions` 转换为 `TemplateContext`。
5. 使用 `justjavac/template` 渲染每个 `TemplateSpec`。
6. 将渲染结果转换为 `PlannedFile`。
7. 模板渲染错误应带上模板名，便于定位问题。
8. 在 `scripts/verify_generated.mjs` 中加入模板生成校验，避免提交 stale 的 `templates.generated.mbt`。

策略：

- 模板渲染函数保持纯逻辑，不触碰文件系统。
- 文件写入层只接收已经渲染好的 `PlannedFile`，不理解模板语法。
- 所有模板变量集中来自 `TemplateContext`，避免每个模板单独拼上下文。
- 所有输出路径统一使用 `/` 描述，写文件阶段再转换为平台路径。
- `templates.generated.mbt` 是提交到仓库的生成文件，并在 `cli/new/moon.pkg` 中加入 formatter ignore，避免格式化破坏生成布局。
- 模板源目录是维护入口；修改模板时必须重新运行 `node scripts/generate_new_templates.mjs`。
- `scripts/verify_generated.mjs` 必须在临时目录重新生成并比较 `cli/new/templates.generated.mbt`。
- HTML、MoonBit 字符串、配置值中的动态内容必须选择合适的 escaping 策略；优先使用 `justjavac/template` 提供的转义机制。如果该包不提供目标格式转义，则在模板上下文进入渲染前集中转义。

### 阶段 5：实现文件计划和写入

定义文件计划类型：

```moonbit
struct PlannedFile {
  path : String
  content : String
}
```

实现：

1. 根据配置生成 `Array[PlannedFile]`。
2. `--dry-run` 时只打印文件列表，不创建目录、不写文件。
3. 非 dry-run 时：
   - 校验目标目录状态。
   - 创建目录树。
   - 写入所有文件。
4. 写入后打印创建摘要。

策略：

- 先完整计算文件计划，再写文件。
- 写文件前做目录安全检查。
- 不做自动回滚；如果写入中途失败，返回错误并说明可能已有部分文件。
- 不覆盖已有非空目录。

### 阶段 6：实现 `moon check`

除非 `run_check == false`，执行：

```sh
moon -C <project-dir> check --target native --diagnostic-limit 80
```

实现策略：

- 捕获 stdout/stderr 或继承输出，保持用户能看到真实诊断。
- 失败时保留项目并返回错误。
- 错误消息必须包含可复制的重试命令。

### 阶段 7：接入 `cli/main.mbt`

1. 在 `cli/moon.pkg` 中 import `justjavac/proton_cli/new`，别名 `@new_project`。
2. 在 usage 中增加：

   ```text
   proton_cli [-C DIR] new [PATH] [--title <title>] [--module <module>] [--width <px>] [--height <px>] [--no-check] [-y|--yes]
   ```

3. 在 `main` 分发逻辑中添加：

   ```moonbit
   args[0] == "new"
   ```

4. 将 `cwd` 传入 new 子模块，保持 `-C DIR` 行为一致。

策略：

- 保持 `cli/main.mbt` 尽量薄。
- 顶层只处理命令分发和统一错误打印。

### 阶段 8：文档和示例同步

需要更新：

- `cli` README 或主 README 中的 CLI 命令说明。
- 如有 examples index，说明 `proton new` 是创建新项目的推荐入口。
- 确认生成的 `README.mbt.md` 内容和真实模板一致。

策略：

- 不在文档中承诺未实现的 `dev/build/bundle` 行为。
- 明确 `.proton/` runtime 由 `proton_cli cef setup` 生成。

## 测试策略

### 单元测试

放在 `cli/new/new_project_wbtest.mbt`，重点测试纯逻辑：

- 默认配置解析。
- `--title` 覆盖 title。
- `--module` 覆盖 module。
- `--width`、`--height` 正常解析。
- 非法 width/height 报错。
- `--no-check` 禁用 check。
- `-y/--yes` 禁用 prompt。
- CI 禁用 prompt。
- slug 到 title 的转换。
- 文件计划包含预期路径。
- 模板中 module import 使用最终 module name。
- 模板渲染失败时错误信息包含模板名。
- 模板上下文中的 title、module、width、height 正确进入输出文件。

### 文件系统测试

使用临时目录：

- 目标目录不存在时成功。
- 目标目录存在但为空时成功。
- 目标目录非空时报错。
- 目标目录已有 `moon.mod` 时报错。
- `--dry-run` 不写入任何文件。

### 集成验证

手动或 CI 中执行：

```sh
moon -C cli test new --target native --diagnostic-limit 80
moon -C cli check --target native --diagnostic-limit 80
```

生成临时项目后验证：

```sh
moon -C <generated-project> check --target native --diagnostic-limit 80
```

如果本地 runtime 可用，可额外手动运行：

```sh
moon -C <generated-project> run app --target native
```

## 风险和处理策略

### 依赖版本漂移

风险：模板中 `justjavac/proton` 或 `moonbitlang/async` 版本和实际发布版本不同步。

策略：在 `templates.mbt` 中集中定义版本常量，发布前检查。

### `justjavac/case` 转换不符合预期

风险：`my-counter` 转换出的 title 不符合用户预期。

策略：只作为默认值；用户可用 `--title` 或交互式输入覆盖。

### `justjavac/template` 渲染或转义行为不明确

风险：模板变量进入 MoonBit 字符串、HTML、配置文件时转义不符合预期。

策略：实现前用 `moon ide doc` 确认 `justjavac/template` 的变量、过滤器和转义能力；无法由模板库处理的格式转义，集中放在模板上下文构建阶段，禁止散落在各个模板函数中。

### 交互式输入阻塞 CI

风险：CI 中执行 `proton new` 卡住。

策略：使用 `justjavac/ci`，CI 中自动非交互；同时提供 `-y/--yes`。

### asset 路径相对目录错误

风险：`@proton.asset("app/app.html")` 依赖运行时工作目录。

策略：README 明确从项目根目录运行 `moon run app --target native`；`moon.proton` 中也使用同一相对路径。

### extension 包被误认为可运行

风险：用户尝试 `moon run extensions/counter`。

策略：不生成 `main.mbt`，README 和 AGENTS 明确说明 `extensions/counter` 是扩展包，由 `app/` 引用。

### `moon check` 失败但项目已写入

风险：用户误以为创建失败且无文件。

策略：失败消息明确写出“项目已创建，但 check 失败”，并打印重试命令。

## 初版不做

- 不支持 `--force`。
- 不生成 `.github/workflows/copilot-setup-steps.yml`。
- 不生成 `.githooks/`。
- 不自动运行 `moon update`。
- 不自动运行 `proton_cli cef setup`。
- 不生成 React/Vite/Svelte 等前端框架模板。
- 不生成 embed 规则或 `app.mbt`。
