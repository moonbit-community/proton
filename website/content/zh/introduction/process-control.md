# 进程控制与指标

## 单实例所有权

App.single_instance() 按应用身份选择一个持有进程。后续实例转发 URL、文档或 reopen 激活，主实例事件循环接受后返回；接受不代表异步激活处理器已经完成。转发有五秒期限，失败不会终止主实例，也不会另起一个持有者。

ApplicationContext.has_single_instance_lock() 查询所有权，release_single_instance_lock() 在运行期间释放锁。释放不终止进程；应用应明确决定是否允许另一个进程成为持有者。激活处理需要同时考虑初次启动和后续转发。

## 应用状态与窗口状态

应用的 focus、hide/show、active/hidden 查询及 readiness 描述整个应用；窗口句柄控制一个窗口。隐藏窗口仍然存活，KeepRunning 应用也能在没有窗口时继续运行。后台应用必须提供明确的退出入口。

## 任务指标

ApplicationContext.task_metrics() 返回 Chromium task 的 AppTaskMetric 列表。renderer 和多个 worker 可以共享进程。task id 标识任务；多个条目的 process_cpu_percent 和 process_memory_bytes 可能完全相同，因为它们属于同一个进程。不能将各行相加作为进程或应用总用量。

采样间隔尚未完成时 CPU 为零，100% 表示一个核心满载；内存测量前为 -1，不是零字节。这些观测不赋予应用对进程的所有权，不应借此绕过 Proton 生命周期单独杀死 helper。
