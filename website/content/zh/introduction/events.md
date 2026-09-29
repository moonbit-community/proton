# 事件

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

`proton_rabbita.subscribe` 将订阅所有权接入 Rabbita，选项包括订阅 key、重试次数、ready 命令和 client 覆盖。完整签名见 [Rabbita API](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.4/)。

JavaScript 接口为 `window.__MoonBit__.app.on(name, callback)`。回调接收包含 `payload` 的事件对象；注册返回取消订阅函数。

## 传递语义

- 订阅之前错过的通知不会重放。
- 命令响应与事件是独立传递，二者的相对顺序不是应用同步约定。
- 释放监听器后停止观察；事件不是持久队列或确认协议。
- 状态变化通知可以使前端查询失效；权威快照通过命令获取。

[事件教程](../tutorial/events.md)演示订阅与清理；[Todo 教程](../tutorial/isomorphic.md)演示通知失效后重新查询快照。

## 订阅有效期与状态同步

订阅属于当前 renderer 文档或 UI 组件，所属对象销毁时应关闭订阅。重新加载会创建新文档，需要重新订阅；原生窗口继续存在不代表 JavaScript 监听器跨 reload 保留。

同步状态时，先订阅再读取初始快照，用事件使快照失效，并忽略已经被新查询替代的响应。先订阅消除了初次读取前的监听空档，但不会让两条独立消息成为原子事务。需要识别旧快照或遗漏变更时，应在业务数据中加入 revision。

on_window_created、on_render_process_gone 等应用生命周期通知是宿主回调，不是 proton_contract 前端事件。它们注册在 App 构建器上；前端也需要相关信息时，再通过命令或显式事件传递。
