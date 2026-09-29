# 浏览器会话

浏览器会话保存 Cookie、缓存、认证状态和 Web storage，通过 window.browser().session() 获取句柄。虽然句柄来自一个浏览器，清理共享会话数据并不是仅对这个页面的私有操作。

## 启动配置

App.session_partition(name) 选择应用 sessionData 目录下的持久 profile。这是应用启动配置，不是每窗口独立的无痕开关；运行时中的窗口使用该配置的 profile。保持应用 identifier 和 partition 稳定才能跨启动保留数据。

App.proxy(server, bypass?) 配置 Chromium 启动级代理，运行中不能修改。它控制浏览器流量，不会自动配置宿主内每一个 MoonBit 网络库。

on_session_created 在应用启动钩子创建窗口前提供 partition 和解析后的数据路径。打包资源与浏览器 profile 是不同目录，不应将可写 profile 放入应用 bundle。

## 操作

| API | 效果 |
| --- | --- |
| get_cookies | 异步读取匹配的 Cookie，可选择 URL 及是否包括 HttpOnly |
| set_cookie | 以 URL、名称、值及可选 domain/path/安全属性设置 Cookie |
| delete_cookies、flush_cookies | 删除选定 Cookie，或将持久 Cookie 存储刷盘 |
| clear_cache、clear_storage_data | 清缓存或选定类型的 Web storage |
| clear_auth_cache | 清除 HTTP 认证缓存 |
| clear_certificate_exceptions | 清除证书例外状态 |
| close_all_connections | 关闭会话连接 |

所属浏览器或窗口不再可用时操作可能失败。Cookie 异步读取应在有效生命周期作用域内等待。清理浏览器存储不会删除应用自己管理的文件，也不等于完成业务登出；后端凭据和 UI 状态需单独处理。

完整属性及 StorageDataKind 变体见[API 参考](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/)。
