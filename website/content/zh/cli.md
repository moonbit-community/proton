# CLI 参考

[English](../cli.html)

`proton_cli` 操作由 `proton.project.json` 描述的 Proton 项目。`-C <directory>` 指定项目目录。命令的完整选项由 `proton_cli <command> --help` 列出。

## 命令

| 命令 | 行为 |
| --- | --- |
| `new <name>` | 创建项目，支持 `minimal` 和 `isomorphic` 模板 |
| `cef setup` | 安装与发布版本匹配的运行时及 helper |
| `doctor` | 只读的项目和环境诊断 |
| `dev` | 按配置管理前端开发，构建并启动原生后端 |
| `build` | 构建配置的前端资源和原生后端 |
| `package` | 构建并组装平台分发产物 |

## 项目创建

`--template minimal` 创建包含内联 HTML 的单个原生模块。`--template isomorphic` 创建 shared、frontend、backend 三个模块。非交互默认模板为 `isomorphic`。`--yes` 接受默认值，`--identifier` 设置应用身份，`--no-git` 禁止初始化 Git。

当前已发布 CLI 为 0.3.0，其生成的 Warren 命令需要按[项目配置](configuration.md)替换。仅安装 Warren 不会修改已经生成的配置文件。

## 开发

配置前端时，`dev` 在 `frontend.path` 中启动 `frontend.before_dev`，等待开发 URL 可用，再以该 URL 运行原生应用。CLI 管理前端时拒绝已被占用的端点。`--no-frontend` 使用外部管理的服务器。`--command` 和 `--frontend-path` 覆盖前端命令及目录，`--setup` 允许在开发启动过程中安装运行时。

前端刷新由前端工具负责。修改后端源码后需要重新构建／启动原生应用。CLI 管理由它启动的前端进程，外部服务器具有独立的生命周期。

## 构建

构建顺序为：执行前端命令、验证前端输出、构建原生后端。前端命令失败时不会继续构建后端。`build` 不生成完整分发包。

`--` 后的参数传给 Moon，例如 `proton_cli build -- --release`。后端目标始终为 native；通过转发参数覆盖 `--target` 会被拒绝。

## 打包

`package --release` 选择 release 产物。`--dry-run` 输出计划，不执行完整的构建／打包／签名流程。重复的 `--format` 参数选择产物格式，`--icon` 覆盖配置图标。签名、公证选项与构建模式独立。参见[打包参考](packaging.md)。
