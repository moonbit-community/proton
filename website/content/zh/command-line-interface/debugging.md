# 诊断参考

诊断来自不同层次：项目与工具链验证、原生启动与生命周期、bridge 请求、前端渲染。前端预览成功不证明原生操作正常，构建成功也不证明打包产物运行正常。

## 诊断接口

| 接口 | 范围 |
| --- | --- |
| `proton_cli doctor` | 只读检查项目、工具链、运行时和 helper |
| `proton_cli --version` / `moon version` | 工具版本 |
| `WebContentsHandle.open_devtools()` | 浏览器的 Chromium 检查器 |
| `App.run()` | 类型化应用运行错误 |
| `App.run_or_abort()` | 报告失败并中止 |
| `ClientFailure` | 前端契约、bridge、通信及解码错误 |

`WindowHandle.web_contents()` 提供浏览器句柄，DevTools 属于该浏览器的生命周期。在 `setup_window` 中打开检查器；额外清理通过该上下文的 `add_cleanup` 注册。

## CDP 端点发现

启动原生应用时设置 `PROTON_REMOTE_DEBUGGING_PORT=0`，让 Chromium 选择可用端口。从进程输出读取实际浏览器 WebSocket 端点：

```text
DevTools listening on ws://127.0.0.1:<port>/devtools/browser/<id>
```

在该进程生命周期内使用它公布的端点；不要先预占再释放端口，也不要假定固定端口。仍可显式指定端口。这是 Chromium 的诊断端点，不是 Proton 的应用命令传输通道。

应用需要通过 `App.debug()` 启用调试；端口环境变量本身不会开启调试。
使用 native MoonBit 编写自动化程序时，可以参考独立的
[`proton_cdp` 库](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/cdp/README.mbt.md)。

## 原生 CDP 自动化

`moonbit-community/proton_cdp@0.5.0` 是可选的原生自动化依赖。它连接已经运行的 Proton 或 Chromium 应用，连接操作不会启动一个 Chrome 窗口；显式启动浏览器是另一组操作。CDP 库本身不依赖 Proton 应用运行时。

自动化可执行程序导入 `moonbitlang/async`、`moonbit-community/proton_cdp/client` 和 `moonbit-community/proton_cdp/page`。对于已公布的端点和已有页面标题：

```moonbit
async fn read_title(endpoint : String, title : String) -> Json {
  @async.with_task_group(tasks => {
    let page = @page.Page::connect(
      tasks,
      @client.parse_cdp_target(endpoint),
      title~,
    )
    page.evaluate("document.title")
  })
}
```

`Page.connect` 选择页面；多个目标时可使用 `target_id`、`url` 和 `title` 筛选。连接属于传入的任务组，离开作用域会关闭连接，不会关闭目标应用；`Page.close()` 可显式断开。导航或 reload 会替换执行上下文，应先等待返回的 `Navigation.wait_for_context()`，再执行新文档中的脚本。`Page.evaluate` 只执行一次，不会自动重试可能有副作用的 JavaScript。 新执行上下文不等于 DOM 或 Proton bridge 已就绪；需要这些条件时，通过 `Page.wait_until` 等待应用定义的无副作用条件，并由应用设置超时。

浏览器启动、截图及 schema 兼容性见[版本化 CDP 指南](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/cdp/README.mbt.md)。CDP 用于诊断和外部自动化，不替代应用命令桥接。

## 日志

Proton 使用 `tonyfettes/xlog`。开发输出使用 stderr，打包应用使用平台日志目录。应用分类为 `app.*`，框架分类为 `proton.*`，应用设置的级别和分类过滤保持有效。

| 环境变量 | 作用 |
| --- | --- |
| `MOON_XLOG` | xlog 过滤 |
| `PROTON_LOG_OUTPUT=stderr` | 选择 stderr 输出，也适用于从终端启动的打包应用 |
| `PROTON_CEF_LOG` | 临时启用独立的 CEF 内部诊断，默认关闭 |

文件输出依赖打包元数据。CEF 诊断不是应用日志接口。

## 找到实际日志

打包应用的默认文件名是 proton-&lt;pid&gt;.log，目录以应用 identifier（不是显示名称）区分：

| 平台 | 默认目录 |
| --- | --- |
| macOS | ~/Library/Logs/&lt;identifier&gt;/ |
| Windows | %LOCALAPPDATA%\&lt;identifier&gt;\Logs\ |
| Linux | $XDG_STATE_HOME/&lt;identifier&gt;/logs/，未设置时为 ~/.local/state/&lt;identifier&gt;/logs/ |

App.path(AppPathKind::Logs) 返回解析后的路径。通过 set_path 或 set_app_logs_path 自定义过路径时，应使用查询结果。PROTON_LOG_OUTPUT=stderr 可使从终端启动的打包程序输出到终端；未打包应用不能使用 file 模式。

## 按阶段定位

| 现象 | 检查与下一步 |
| --- | --- |
| CLI 找不到运行时 | 比较 proton_cli --version 与应用 proton 依赖版本；运行 cef requirements 查看该 CLI 要求，再执行 cef setup；保留 setup 的完整错误 |
| dev 等不到前端 | 在 frontend.path 中单独执行 before_dev，检查 dev_url 的主机和端口；已有服务用 --no-frontend，不要同时启动第二个 |
| 普通浏览器里没有 bridge | 改为通过 proton_cli dev 启动原生应用；网页预览不注入宿主 bridge |
| permission_denied / unknown_op | 检查注册的命令描述符、capability 目标与当前窗口／页面；不要只检查是否添加模块依赖 |
| 找不到前端命令 | 检查配置中的工具是否安装并位于 PATH；Warren 需要独立于 Proton CLI 安装 |
| 请求或响应解码失败 | 对照命令描述符类型与实际 JSON 载荷，检查 ClientFailure 和后端日志 |
| 打包后资源 404 | 检查产物内资源树与 HTML 相对 URL，确认 frontend.dist 与 package.resources；停止开发服务器后重试 |
| 关闭窗口后进程仍在 | 先检查 KeepRunning 和被拒绝的 quit；查看最终退出／清理错误。记录关闭操作与进程状态，不把手动 kill 当作退出成功 |
| appimage 打包失败 | 先检查 PNG 文件及 appimagetool --version；区分图标校验失败与 create AppImage 工具错误 |

## 报告问题

报告应包含执行命令与完整错误、Proton 和 MoonBit 版本、操作系统及架构，并说明故障发生在开发模式还是打包应用中。附上 `proton_cli doctor --json` 输出、相关应用日志及最小复现。退出问题还应注明进程自行退出还是被手动终止。分享日志前检查其中是否包含业务数据或凭据。
