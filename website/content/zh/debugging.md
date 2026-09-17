# 运行与调试

[English](../debugging.html)

前端渲染、命令处理和原生启动会在不同位置失败。先确定出问题的部分，再检查对应层。

## 运行开发应用

在包含 `proton.project.json` 的目录中执行：

```sh
proton_cli doctor
proton_cli dev
```

doctor 检查配置、工具链、运行时与 helper，不修改项目。如果报告运行时缺失，执行 `proton_cli cef setup`。

minimal 模板修改内嵌页面或后端后，需要停止并重新运行应用。isomorphic 模板由 Warren 提供前端服务，前端刷新行为取决于该工具；修改原生后端代码后应重启原生应用。

当前端端口已有服务器占用时，停止它，或者明确使用 `proton_cli dev --no-frontend`。不要让多个 dev 命令争用同一端点。

## 打开浏览器开发者工具

可以先在 minimal 项目中使用下面的完整 **`app/main.mbt`**，验证检查器，无需依赖平台快捷键：

```moonbit
///|
async fn main {
  @proton.html("Debugging", "<h1>Inspect this page</h1>", debug=true)
  .load_config()
  .window_lifecycle(
    on_ready=context => { context.handle().browser().open_devtools() },
    on_close=_ => (),
  )
  .run_or_abort()
}
```

执行 `proton_cli dev` 后，ready 回调会为主浏览器打开 DevTools。用 Elements 检查 DOM 与 CSS，用 Console 查看前端异常。完成调试后移除自动打开检查器的钩子。

在已有应用中，应保留原有生命周期逻辑，将 `open_devtools()` 加到 ready 处理器中，而不是替换整个处理器。

## 排查命令失败

- **Bridge 不可用：** 页面可能运行在普通浏览器中，应从 Proton 打开。
- **操作未知或不可用：** 确认后端已绑定命令，或已授予对应扩展 capability。
- **解码失败：** 对照序列化字段名称、类型与请求、响应契约。
- **业务拒绝：** 检查 `InvalidTitle` 等响应数据，不要当作通信错误处理。

调试期间保留可见的前端 catch 或失败回调，并从后端终端输出中查找操作的详细错误。

## 阅读应用日志

Proton 使用 `tonyfettes/xlog`。开发时输出到 stderr，打包应用写入平台日志目录。应用分类使用 `app.*`，框架使用 `proton.*`。

在进程环境中设置 `MOON_XLOG` 调整 xlog 过滤规则，Proton 会保留应用的级别与分类设置。从终端启动打包应用时，`PROTON_LOG_OUTPUT=stderr` 有助于直接观察输出；文件输出需要打包元数据。

CEF 内部日志是独立的，默认关闭。`PROTON_CEF_LOG` 只适用于调查 Chromium 或运行时行为，不作为日常应用日志接口。

## 报告前检查

minimal 使用 `moon check --target native`，isomorphic 使用 `moon check --target js,native`。报告时附上准确命令、完整错误、Proton 版本、MoonBit 版本、操作系统与架构，以及问题发生在开发阶段还是仅发生于打包后。

浏览器预览成功不能验证原生命令，构建成功也不能验证打包应用。提交 [issue](https://github.com/moonbit-community/proton/issues) 前，尽量将复现缩小到出现问题的那一层。
