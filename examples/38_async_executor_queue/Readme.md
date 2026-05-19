# 38_async_executor_queue

临时示例

手动搭建一个底层异步执行队列：

- C 侧维护 task 队列和工作线程。
- MoonBit 侧用 `@async.run_async_main` 运行异步循环。
- 任务进度通过 `webview.dispatch` 回到 UI 线程

目前 lepus 的异步实现参考 `39_async_extension_add`，直接使用 `op_async_result` 注册异步 op。

