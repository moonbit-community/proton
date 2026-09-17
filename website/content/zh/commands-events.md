# 从前端调用后端

[English](../commands-events.html)

命令让前端请求原生后端执行操作。本章为[最小项目](first-app.md)添加一个可运行的问候表单，先用普通 JavaScript 展示原生通信边界；[Todo 教程](isomorphic.md)则使用共享 MoonBit 类型和 Rabbita。

## 添加契约依赖

在 **`moon.mod`** 已有的 `import { ... }` 块中加入下面一项，保留其他依赖：

```text
"moonbit-community/proton_contract@0.3.0",
```

将 **`app/moon.pkg`** 替换为：

```text
import {
  "moonbitlang/core/json",
  "moonbitlang/async",
  "moonbit-community/proton",
  "moonbit-community/proton_contract",
}

supported_targets = "native"

pkgtype(kind: "executable")
```

在项目根目录运行 `moon update`。模块依赖让库可用，包导入则让入口能使用 `@proton_contract`。

## 定义、注册并调用命令

将 **`app/main.mbt`** 替换为下面的完整示例：

```moonbit
///|
struct GreetRequest {
  name : String
} derive(FromJson, ToJson)

///|
let greet : @proton_contract.Command[GreetRequest, String] =
  @proton_contract.command("greet")

///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html lang="en">
    #|<meta charset="utf-8">
    #|<title>Greeting</title>
    #|<style>body { font: 18px system-ui; padding: 32px; }</style>
    #|<label>Name <input id="name" value="MoonBit"></label>
    #|<button id="greet">Greet</button>
    #|<p id="result" role="status"></p>
    #|<script>
    #|  document.querySelector("#greet").onclick = async () => {
    #|    const result = document.querySelector("#result");
    #|    try {
    #|      result.textContent = await window.__MoonBit__.app.greet({
    #|        name: document.querySelector("#name").value
    #|      });
    #|    } catch (error) {
    #|      result.textContent = String(error);
    #|    }
    #|  };
    #|</script>
    #|</html>
  @proton.html("Greeting", html)
  .load_config()
  .commands(fn(registrar) raise {
    registrar.bind(greet, (_context, request) => {
      "Hello, " + request.name + "!"
    })
  })
  .run_or_abort()
}
```

执行 `proton_cli dev`。输入“Ada”，点击 **Greet**，页面应显示“Hello, Ada!”。

这里有三个相互连接的部分：

1. `GreetRequest` 描述 JSON 请求，`greet` 声明路由及响应类型。
2. `.commands(...)` 通过 `registrar.bind` 注册处理器，处理器接收调用方上下文和解码后的请求。
3. `window.__MoonBit__.app.greet(...)` 返回一个表示响应的 JavaScript promise，页面等待结果并处理拒绝。

仅声明描述符并不会注册处理器。应用中的命令名称需要保持唯一。

## 参数与返回值

对象属性 `name` 对应请求字段。操作需要更多输入时，在请求中添加可序列化字段。返回值可以是字符串、数字、数组，也可以是实现 `ToJson` 的结构体。

原生处理器运行在后端，适合执行业务校验和原生操作。渲染器不能借此直接调用任意 MoonBit 函数。

## 错误处理

请求格式错误、命令不存在或处理器失败，都会使 JavaScript promise 被拒绝。保留调用外层的 `try/catch`，并显示有用的错误信息。

预期的业务结果应作为响应数据。例如 Todo 模板返回 `Changed`、`InvalidTitle` 或 `MissingTodo`，前端将它们与描述 bridge、传输和解码失败的 `ClientFailure` 分开处理。

不要因为前端按钮回调已经执行，就假定请求成功。依赖操作成功的界面更新，应等待返回结果。

## 异步操作与调用方上下文

命令处理器可以执行异步操作。上下文用于识别调用方，也可以向其发送类型化事件。[向前端发送事件](events.md)会在这个示例上继续修改。

如果在普通浏览器打开页面，`window.__MoonBit__` 不存在。请使用 `proton_cli dev` 启动桌面应用，而不是仅打开前端 URL。
