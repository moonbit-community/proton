# 命令

[English](../../introduction/commands-events.html)

命令是跨渲染器与宿主边界的类型化请求／响应操作。载荷经过序列化；共享 MoonBit 类型不会共享内存，也不会让前端直接执行后端代码。

## 契约与绑定

| API | 约定 |
| --- | --- |
| `proton_contract.command[Request, Response](name)` | 声明类型化应用路由，不注册处理器 |
| `App.commands(register, targets?)` | 为指定渲染器目标安装应用命令绑定 |
| `CommandRegistrar.bind(command, handler)` | 绑定接收 `(CommandContext, Request)`、返回 `Response` 的异步处理器 |
| `proton_client.invoke(command, request)` | 前端异步调用，返回 `Response` 或抛出 `ClientFailure` |
| `proton_rabbita.invoke(...)` | 将成功与失败映射到 Rabbita 命令 |

后端要求 `Request` 实现 `FromJson`、`Response` 实现 `ToJson`；前端要求相反方向的转换。契约与注册错误不同于运行中请求的失败。应用路由名称必须合法且唯一；绑定和调用时都会验证描述符。

处理器上下文标识调用方，并提供 `emit_to_caller`。处理器可以等待后端异步工作。校验不通过等业务结果可以建模为响应类型，而不是通信失败。

## JavaScript 接口

注入的 bridge 将应用方法暴露为 `window.__MoonBit__.app.<name>(request)`。调用返回 Promise，失败时 reject。应用路由使用 `app:`，扩展操作使用 `ext:`。普通浏览器页面没有注入的原生 bridge。

## 载荷大小

Proton 不对命令载荷设置固定的大小上限。载荷通过 JSON 序列化，仍受可用内存与底层传输约束。大消息会增加序列化、复制和解析开销。

## 取消

`proton_client.invoke_with_callbacks` 返回取消函数，用于取消响应观察并请求取消通信；迟到的响应会被忽略。异步 `invoke` 所在任务取消时，也会取消待完成请求。取消不保证撤销后端已经执行的操作。

## 客户端错误

| 变体 | 含义 |
| --- | --- |
| `BridgeUnavailable` | 原生 bridge 不存在 |
| `InvalidContract` | 命令或事件描述符不合法 |
| `RemoteFailure` | 后端拒绝，携带 code、message 和可选 detail |
| `TransportFailure` | 通信失败 |
| `ResponseDecode` | 响应无法解码为声明的类型 |
| `RequestCancelled` | 待完成请求被取消 |

命令向调用方返回结果，[事件](events.md)向观察者传递通知；两者都不意味着应用数据已经持久化。

完整签名见[客户端 API](https://mooncakes.io/docs/moonbit-community/proton_client@0.3.3/)。逐步示例位于独立的[命令教程](../tutorial/commands-events.md)。
