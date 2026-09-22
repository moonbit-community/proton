# Examples

[English](../../examples/index.html)

按行为集中、入口清晰、能力覆盖互补的标准挑选以下十个示例。源码链接固定到 0.3.3 发布提交，避免文档与代码漂移。这些是可运行参考；逐步开发应用的内容集中在 [Tutorial](../tutorial/index.md)。

| 示例 | 重点 |
| --- | --- |
| [最小应用](01_run.md) | 内联 HTML 与原生应用入口。 |
| [嵌入 HTML](12_embed.md) | 将 HTML 源文件嵌入 MoonBit 字符串。 |
| [文件系统能力](18_extension_fs.md) | 渲染端在显式权限根目录内请求文件操作。 |
| [类型化事件](40_event_broadcast.md) | 异步命令执行期间推送进度事件。 |
| [多窗口命令](45_bridge_multi_window.md) | 多个窗口共用类型化命令注册。 |
| [HTML 与静态资源](46_asset_sidecar_resources.md) | 资源入口配合独立 JavaScript、CSS 和 worker 文件。 |
| [原生应用菜单](49_app_menu.md) | 类型化菜单、动态命令状态与应用回调。 |
| [嵌入浏览器视图](53_view_minimal.md) | 在宿主侧边栏旁声明子浏览器。 |
| [应用国际化](56_i18n.md) | 命令上下文、Chromium 与原生菜单共用启动语言环境。 |
| [后台驻留](57_background_residency.md) | 单实例应用在最后一个窗口关闭后继续运行。 |

## 源码与运行时

示例使用仓库工作区。检出对应发布提交，安装[所需工具](../installation.md)，并先安装该版本的运行时：

```sh
git clone https://github.com/moonbit-community/proton.git
cd proton
git checkout 25d77e6236420025ddf1ab04995c0c2a05bba9ed
moon update
proton_cli cef setup
```
