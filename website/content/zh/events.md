# 事件

[English](../events.html)

事件是从宿主发往渲染器的类型化通知，没有响应值。`proton_contract.event[Payload](name)` 仅声明描述符，不安装监听器，也不保留历史通知。

## 发送目标

| API | 目标与有效期 |
| --- | --- |
| `CommandContext.emit_to_caller(event, payload)` | 发起当前命令的页面 |
| `WindowContext.events()` | 获取窗口事件发送器 |
| `WindowEventEmitter.emit(event, payload)` | 关联窗口仍存活时向其发送 |

宿主载荷要求实现 `ToJson`。窗口发送器的有效期受窗口生命周期约束；保存在应用状态中的发送器应在窗口关闭时移除。发送事件不意味着向全部窗口广播。

## 订阅

`proton_client.subscribe(event, listener, failure)` 通过 `FromJson` 解码载荷，返回 `Subscription`。`Subscription.close()` 释放监听器。订阅建立可能抛出 `ClientFailure`；事件解码失败通过 failure 回调报告 `EventDecode`。

`proton_rabbita.subscribe` 将订阅所有权接入 Rabbita，选项包括订阅 key、重试次数、ready 命令和 client 覆盖。完整签名见 [Rabbita API](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.3/)。

JavaScript 接口为 `window.__MoonBit__.app.on(name, callback)`。回调接收包含 `payload` 的事件对象；注册返回取消订阅函数。

## 传递语义

- 订阅之前错过的通知不会重放。
- 命令响应与事件是独立传递，二者的相对顺序不是应用同步约定。
- 释放监听器后停止观察；事件不是持久队列或确认协议。
- 状态变化通知可以使前端查询失效；权威快照通过命令获取。

[事件教程](tutorial/events.md)演示订阅与清理；[Todo 教程](tutorial/isomorphic.md)演示通知失效后重新查询快照。
