# 使用原生能力

[English](../capabilities.html)

扩展向渲染器提供可复用的宿主操作。capability 会安装扩展后端处理器，并授予特定范围的访问权限。本章让 minimal 应用读取一个本地文本文件。

## 添加文件系统扩展

在 minimal 项目的 **`moon.mod`** 中，将以下依赖加入 `import { ... }`：

```text
"moonbit-community/proton_ext@0.2.11",
```

在 **`app/moon.pkg`** 中使用以下导入，然后执行 `moon update`：

```text
import {
  "moonbitlang/async",
  "moonbit-community/proton",
  "moonbit-community/proton_ext/fs",
}

supported_targets = "native"

pkgtype(kind: "executable")
```

## 准备文件

在项目根目录创建 **`workspace`** 目录，并在其中创建 **`message.txt`**，内容为：

```text
Hello from the filesystem.
```

将 **`app/main.mbt`** 替换为：

```moonbit
///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html lang="en">
    #|<meta charset="utf-8">
    #|<title>Read a file</title>
    #|<button id="read">Read message.txt</button>
    #|<pre id="result" role="status"></pre>
    #|<script>
    #|  document.querySelector("#read").onclick = async () => {
    #|    const result = document.querySelector("#result");
    #|    try {
    #|      const reply = await window.__MoonBit__.core.invokeOp(
    #|        "ext:fs/read_file", { path: "./workspace/message.txt" }
    #|      );
    #|      result.textContent = reply.content;
    #|    } catch (error) {
    #|      result.textContent = String(error);
    #|    }
    #|  };
    #|</script>
    #|</html>
  @proton.html("Read a file", html)
  .load_config()
  .capability(
    @fs.capability([
      @fs.PermissionRoot("./workspace", ["read_file"]),
    ]),
  )
  .run_or_abort()
}
```

执行 `proton_cli dev`，点击 **Read message.txt**，页面应显示文件内容。这是真正的宿主文件读取，不是浏览器文件选择器。

## 理解授权内容

这个 capability 包含三个相关选择：

- **操作：** 只允许 `read_file`，页面不能利用此授权写入或删除文件。
- **根目录：** 只允许访问 `./workspace` 内的路径。
- **目标：** 未显式传入 `targets` 时，授权给主窗口入口。

底层路由 `ext:fs/read_file` 属于文件系统扩展，应用命令则使用独立的 `app:` 路由空间。无需自行注册文件系统处理器。

相对根目录和请求路径以 CLI 为应用设置的 `@proton.resource_dir()` 为基准，不应假定它们相对于任意终端工作目录。

## 主动检查失败情况

将请求路径改为 `workspace` 中不存在的文件，调用应失败，catch 分支会显示错误。再改为允许根目录之外的文件，此授权应拒绝访问。

删除 `.capability(...)` 不会阻止应用启动，但路由变得不可用。仅添加扩展依赖并不等于授予权限。

## 多窗口与持久化文件

为第二个窗口添加能力时，通过 `RendererTarget::entry(window="...")` 或 `RendererTarget::bundled(window="...")` 显式选择目标，只授予页面功能真正需要的权限。

本地 workspace 目录适合这个开发练习。安装资源目录可能只读，持久化文件应放在合适的可写应用数据目录或用户选择的位置。需要随应用分发的文件通过[资源配置](configuration.md)打包。

## 其他能力

对话框、剪贴板、shell、托盘等扩展也采用显式安装和授权的方式，但各自定义作用范围与平台支持。此版本的通知扩展面向 macOS，不能从框架的平台列表推断每个扩展都支持全部平台。

需要某项能力时，查阅[扩展 API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.2.11/)中的 capability 构建器及请求、响应类型。
