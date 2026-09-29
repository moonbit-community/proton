# 应用 API 参考

根包 moonbit-community/proton 是公开应用入口。运行前使用 App 构建器；运行中使用上下文和句柄。CLI 项目元数据不能代替运行时配置。

| 领域 | 所属对象／入口 | 参考 |
| --- | --- | --- |
| 启动、ready、退出与任务清理 | App、ApplicationContext、生命周期钩子 | [生命周期](lifecycle.md) |
| 窗口声明、实例与子浏览器 | App、WindowManager、WindowHandle、ViewHandle | [窗口](windows.md) |
| 请求／响应通信 | 契约、注册器、客户端 | [命令](commands-events.md) |
| 前端通知与订阅有效期 | emitter、客户端订阅 | [事件](events.md) |
| 宿主操作与 renderer 授权 | App.capability、扩展范围 | [能力](capabilities.md) |
| Cookie、浏览器存储与代理 | SessionHandle、启动构建器 | [浏览器会话](sessions.md) |
| 签名应用更新 | App.update_channel、PendingUpdate | [自动更新](updates.md) |
| 进程所有权与激活 | 单实例构建器、上下文方法 | [进程控制](process-control.md) |
| 菜单、语言与后台驻留 | 窗口／应用配置 | [精选示例](../examples/index.md) |
| 路径、文件与构建元数据 | 项目配置、应用路径 | [项目结构](project-structure.md)、[Configuration](../configuration/index.md) |

完整方法、类型化错误和默认参数见[版本化 API 索引](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/)。本书说明对象关系与行为约定，不复制每一条签名。参考页中的短片段用于解释 API，不要求读者先修改某个教程项目。
