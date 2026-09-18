# 创建项目

[English](../../tutorial/first-app.html)

本章用 minimal 模板创建一个桌面窗口，运行它、修改页面，再构建可执行文件。开始前请完成[环境准备](../installation.md)。

## 1. 创建应用

在存放项目的目录中执行，不要放在另一个 MoonBit 工作区内部：

```sh
proton_cli new hello-proton --template minimal --yes
cd hello-proton
```

这里需要明确指定 `--template minimal`：非交互模式的默认模板是 `isomorphic`。`--yes` 接受生成器的默认值。准备分发的应用可以在创建时用 `--identifier com.example.hello-proton` 指定标识。

生成的 `app/main.mbt` 管理窗口与 HTML；`moon.mod` 声明依赖；`app/moon.pkg` 导入包；`proton.project.json` 记录应用标识和构建入口。

## 2. 准备并运行

在 `hello-proton/` 中执行：

```sh
moon update
proton_cli cef setup
proton_cli dev
```

应用会打开原生窗口，显示模板中的欢迎信息。应用运行期间终端会被占用。继续下一步前，请先关闭窗口。

CLI 构建原生可执行文件，并携带项目配置启动它。此模板使用内联 HTML，没有需要启动的前端服务器。

## 3. 修改页面

将 **`app/main.mbt` 的全部内容**替换为：

```moonbit
///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html lang="en">
    #|<meta charset="utf-8">
    #|<title>Hello Proton</title>
    #|<style>
    #|  body { font: 18px system-ui; padding: 32px; }
    #|</style>
    #|<h1>Hello from MoonBit</h1>
    #|<p>This page lives inside a desktop window.</p>
    #|</html>
  @proton.html("Hello Proton", html, width=900, height=700)
  .load_config()
  .run_or_abort()
}
```

再次执行 `proton_cli dev`，应看到“Hello from MoonBit”、一段说明文字，以及初始大小为 900 × 700 的窗口。

`@proton.html` 创建应用构建器，第一个参数是窗口标题，第二个参数是 HTML 文档。`#|` 开头的各行组成 MoonBit 多行字符串。

`.load_config()` 从生成的元数据中加载必需的应用标识。请保留这个调用，仅有显示标题并不能标识应用。

`.run_or_abort()` 持续运行到应用退出，并报告启动或运行错误。入口是 async 函数，所以需要保留模板中的 `moonbitlang/async` 导入。

## 4. 检查并构建

关闭窗口后执行：

```sh
moon check --target native
proton_cli build
```

构建成功会生成原生可执行文件，但还没有组装成可分发的应用。[构建与分发](../packaging.md)会说明后续步骤。

## 下一步

通过[项目结构](../project-structure.md)了解生成的文件。想为当前页面增加交互，可以阅读[从前端调用后端](commands-events.md)；想同时用 MoonBit 编写界面，可以跟随[完整前后端示例](isomorphic.md)。

如果应用无法启动，执行 `proton_cli doctor` 并查看终端中的完整错误。如果构建成功却仍显示旧页面，先停止旧进程，再重新运行 `dev`；此模板没有提供前端热更新的服务器。
