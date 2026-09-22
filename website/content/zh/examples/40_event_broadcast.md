# 类型化事件

[English](../../examples/40_event_broadcast.html)

异步命令执行期间推送进度事件。

[40_event_broadcast](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/40_event_broadcast) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/40_event_broadcast/main.mbt), [app.html](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/40_event_broadcast/app.html)

## 行为

启动计数器后产生 tick 事件和 done 事件，命令还会返回汇总结果。run_id 用于区分不同运行。

## 运行

需满足[运行环境要求](../introduction/installation.md)。在仓库根目录执行：

```sh
moon -C examples run 40_event_broadcast --target native
```

## 限制与使用边界

事件与命令响应职责不同。启动运行前注册监听器；事件不是持久历史记录或确认消息。
