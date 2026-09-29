# 类型化事件

异步命令执行期间推送进度事件。

[40_event_broadcast](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/40_event_broadcast) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/40_event_broadcast/main.mbt), [app.html](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/40_event_broadcast/app.html)

## 行为

启动计数器后产生 tick 事件和 done 事件，命令还会返回汇总结果。run_id 用于区分不同运行。

## 运行

需满足[运行环境要求](../introduction/installation.md)。在仓库根目录执行：

```sh
moon -C examples run 40_event_broadcast --target native
```

## 限制与使用边界

事件与命令响应职责不同。启动运行前注册监听器；事件不是持久历史记录或确认消息。

## 关键代码与设计

以下为入口中的节选，完整上下文见本页源码链接。

```moonbit
async fn run_ticker(
  context : @proton.CommandContext,
  payload : StartPayload,
) -> TickerResult {
  let count = clamp(payload.count, 1, 20)
  let interval_ms = clamp(payload.interval_ms, 100, 2000)
  let ticks : Array[TickEvent] = []
  for index in 1..<=count {
    @async.sleep(interval_ms)
    let tick = TickEvent::{
      run_id: payload.run_id,
      index,
```

类型化扩展把 start 绑定到 run_ticker。处理器在 tick 之间异步等待，发送 tick／done 通知，最后返回 TickerResult。进度事件与命令结果职责不同，显示一次 tick 不代表命令已经完成。

次数与间隔由后端限制。UI 应使用请求标识区分重叠任务，随所属对象关闭订阅，并处理请求取消。目录虽叫 broadcast，这不是持久广播日志。
