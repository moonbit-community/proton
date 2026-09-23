# 诊断参考

诊断来自不同层次：项目与工具链验证、原生启动与生命周期、bridge 请求、前端渲染。前端预览成功不证明原生操作正常，构建成功也不证明打包产物运行正常。

## 诊断接口

| 接口 | 范围 |
| --- | --- |
| `proton_cli doctor` | 只读检查项目、工具链、运行时和 helper |
| `proton_cli --version` / `moon version` | 工具版本 |
| `BrowserHandle.open_devtools()` | 浏览器的 Chromium 检查器 |
| `App.run()` | 类型化应用运行错误 |
| `App.run_or_abort()` | 报告失败并中止 |
| `ClientFailure` | 前端契约、bridge、通信及解码错误 |

`WindowHandle.browser()` 提供浏览器句柄，DevTools 属于该浏览器的生命周期。在窗口 ready 钩子中打开检查器时，应保留已有钩子的状态和清理逻辑。

## 日志

Proton 使用 `tonyfettes/xlog`。开发输出使用 stderr，打包应用使用平台日志目录。应用分类为 `app.*`，框架分类为 `proton.*`，应用设置的级别和分类过滤保持有效。

| 环境变量 | 作用 |
| --- | --- |
| `MOON_XLOG` | xlog 过滤 |
| `PROTON_LOG_OUTPUT=stderr` | 选择 stderr 输出，也适用于从终端启动的打包应用 |
| `PROTON_CEF_LOG` | 临时启用独立的 CEF 内部诊断，默认关闭 |

文件输出依赖打包元数据。CEF 诊断不是应用日志接口。

## 错误分类

| 现象 | 相关边界 |
| --- | --- |
| 缺少运行时／helper | setup 管理的版本与平台选择 |
| 找不到前端命令 | 工具安装与 PATH；Warren 单独安装 |
| bridge 不可用 | 页面不在 Proton 渲染器环境中 |
| 未知操作 | 缺少命令绑定或能力声明 |
| 解码失败 | 请求／响应类型与序列化载荷不匹配 |
| 窗口消失但进程仍存活 | 生命周期策略、活动子浏览器和清理完成状态 |
| 打包页面缺少资源 | 资源路径、前端输出和打包组装 |

有效的问题报告应包含准确命令、完整错误、Proton／MoonBit 版本、操作系统和架构、开发或打包模式，以及最小复现。强制结束进程必须与正常完成退出区分。
