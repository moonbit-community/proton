# 应用更新

应用更新替换分发中的应用，不更新开发 CLI 或 Mooncakes 依赖。运行前通过 App.update_channel(endpoint, public_keys, check_on_launch?, freshness_days?) 配置。

## 更新渠道与检查

endpoint 必须是 HTTPS，至少配置一个受信任 RSA 公钥。默认开启自动检查，manifest 新鲜度默认为 30 天且必须为正数。公钥格式由 [updater public-key](../command-line-interface/commands.md#updater-public-key) 校验。

自动检查在启动成功后进行，失败写入日志而不使应用启动失败。显式检查使用 ApplicationContext.check_for_update()，处理结果与异常。NotConfigured 与 UpToDate 不同；应用结束后，保留的上下文不再拥有活动更新渠道。

PendingUpdate 表示 manifest 已通过信任、新鲜度和 revision 检查。它提供 version、revision、size 和可选 notes URL，此时尚未下载产物。

## 安装与重启

安装必须显式调用 PendingUpdate.install()。下载先写入私有暂存区域，通过大小、摘要和签名验证后才能使用。应检查 UpdateInstallOutcome，不能假设所有平台都已经完成文件替换。macOS 和 Linux 在 install 中应用替换；Windows 保留已验证的 NSIS 安装器，待 restart 使用。

PendingUpdate.restart() 请求启动替换后的应用，调用方随后应退出。请求成功只表示操作系统接受启动，不代表新进程已经 ready。检查更新或收到更新通知都不会隐式安装。

未保存数据的处理应与检查、下载分开，通过[退出生命周期](lifecycle.md)决定何时退出。旧的受管理更新产物在成功启动后清理；暂存新包不代表新应用已经启动成功。

## 发布者责任

应用 identifier 保持稳定，revision 单调递增。[CLI package](../command-line-interface/commands.md#package) 的更新元数据选项指定产物位置、发布时间和 revision。updater public-key 只格式化公钥，不生成密钥、签署更新 manifest 或托管服务器。系统签名／公证与更新器签名验证承担不同检查，配置其中一项不会自动配置另一项。
