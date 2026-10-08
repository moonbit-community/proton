# 架构与进程模型

Proton 将原生 MoonBit 应用与 Chromium 浏览器引擎组合为桌面应用。应用进程管理窗口、应用状态和操作系统功能；Web 页面负责界面，通过消息调用宿主提供的操作。

## 组成与职责

| 组成 | 职责 |
| --- | --- |
| MoonBit 原生应用 | 执行应用入口、业务逻辑和异步任务 |
| Proton | 提供窗口、生命周期、浏览器内容及前后端通信 API |
| CEF（Chromium Embedded Framework） | 将 Chromium 嵌入原生应用，提供浏览器创建、回调及进程通信接口 |
| Chromium | 执行 Web 平台功能，包括页面渲染、JavaScript、网络和浏览器存储 |
| Web 前端 | 用 HTML、CSS 和 JavaScript 实现应用界面 |

应用通过 `moonbit-community/proton` 使用公开 API。Proton 的原生绑定随应用从源码编译，CEF／Chromium 则作为独立运行时加载，分发时与应用一起打包。页面使用这套随包分发的浏览器引擎，不依赖操作系统 WebView。

前端可以使用普通 JavaScript，也可以由 MoonBit 编译器编译为 JavaScript。Rabbita 是可选的 MoonBit UI 库，`proton_rabbita` 为其提供命令与订阅集成；两者都不是 Proton 运行时的必需组成。

## 进程模型

应用可执行文件既运行 MoonBit 宿主代码，也承载 CEF 的 browser process。这个进程管理原生窗口和浏览器实例，并协调 Chromium 子进程。页面脚本在 renderer 进程执行；GPU 和 utility 等子进程承担图形及其他浏览器服务。

```text
应用进程
  MoonBit 应用逻辑
       │
  Proton ── 原生窗口
       │
  CEF browser process
       │ Chromium 进程间通信
       ├── renderer 进程：页面、JavaScript、worker
       ├── GPU 进程：图形处理
       └── utility 等进程：浏览器服务
```

`cef_process` 是供 CEF 启动子进程的辅助可执行文件。CEF 在启动时选择进程角色，同一个 helper 可用于不同子进程；helper 不执行应用的 MoonBit 入口。它与应用使用匹配的 Proton 版本和 CEF 运行时。

进程数量由 Chromium 根据页面和运行状态管理。一个 renderer 可以承载多个 task，例如页面和 worker。因此，窗口数、浏览器实例数、task 数与操作系统进程数不是一一对应的，task 的资源指标也不能直接相加作为应用总用量。

## 窗口与浏览器内容

一个 Proton 应用运行时可以管理多个原生窗口。每个窗口拥有主浏览器内容，也可以承载额外的子浏览器视图：

```text
应用运行时
  ├── 窗口 A
  │    ├── 主浏览器内容
  │    └── 子浏览器视图
  └── 窗口 B
       └── 主浏览器内容
```

窗口负责标题、位置、尺寸和原生装饰；浏览器内容负责文档、导航、脚本和页面事件。子视图是窗口内容区内的独立浏览器，有自己的文档和边界。它的导航不改变主页面，移除它也不等于关闭整个窗口。

这些对象的生命周期不同：页面可以重新加载，renderer 可以终止，而原生窗口仍然存在。关闭窗口会进一步关闭它承载的浏览器内容。相关创建、关闭和恢复约定见[应用 API](application-api.md#窗口与浏览器视图)。

## 执行与通信边界

原生 UI 对象由创建它们的线程管理。Proton 将原生事件处理接入 `moonbitlang/async` 的外部事件循环：原生回调排队记录并唤醒调度器，MoonBit 再处理事件和应用回调。应用异步任务可以让出执行，但同步的耗时工作仍会占用宿主事件循环。

renderer 与宿主有独立的执行环境。Proton 在页面中注入 bridge，将前端请求送到宿主注册的处理器，再把结果或错误交回页面；宿主也可以发送事件通知。载荷经过序列化，共享类型定义不会使两端共享内存。

`proton_contract` 描述类型化命令和事件，`proton_client` 供 MoonBit 前端调用；JavaScript 前端直接使用页面 bridge。宿主通过命令绑定和 capability 决定向哪些页面开放哪些操作。具体协议、取消和授权行为见[命令](application-api.md#命令)、[事件](application-api.md#事件)及[能力](application-api.md#扩展与能力)。

## 开发与分发

开发和分发使用同一套原生宿主与浏览器架构，变化的是页面及运行时资源的来源。

| 场景 | 页面来源 | 原生运行时来源 |
| --- | --- | --- |
| 内联 HTML | 编译进应用的字符串 | setup 安装的共享运行时与 helper |
| 使用前端开发服务器 | CLI 配置的开发 URL | setup 安装的共享运行时与 helper |
| 打包应用 | 内联内容或打包的静态资源；URL 入口也可使用远程页面 | 产物携带的运行时与 helper |

前端开发服务器只提供页面资源，不承担宿主业务逻辑。通过普通浏览器访问同一个 URL 时，没有 Proton 注入的原生 bridge。打包将应用可执行文件、所需页面资源、CEF 运行时和 helper 组装成可分发产物，文件职责与输出路径见 Configuration 章节，打包格式及前提见 Command Line Interface 章节。
