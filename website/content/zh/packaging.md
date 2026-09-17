# 构建与分发

[English](../packaging.html)

构建生成可执行文件和前端输出，打包再将它们与运行时、helper、声明的资源组合为平台分发产物。Proton 项目应使用 **Proton CLI** 完成这个流程。

## 准备应用元数据

在 **`proton.project.json`** 已有的 `package` 对象中设置应用名称和版本：

```json
{
  "product_name": "Todo App",
  "version": "0.1.0",
  "output": "dist"
}
```

合并这些字段，不要替换整个项目文件。跨版本保持根级 `identifier` 稳定。`package.version` 是你的应用版本，不需要与 Proton 0.2.11 相同。

## 构建发布版本

在项目根目录执行：

```sh
proton_cli build -- --release
```

CLI 先构建配置的前端，再构建原生后端。`--` 后的 `--release` 传给 Moon。命令成功说明构建通过，还没有生成最终安装器。

## 检查并打包

```sh
proton_cli package --release --dry-run
proton_cli package --release
```

dry run 显示选中的后端、元数据、格式、输出路径和签名选项，不执行完整构建、打包与签名流程。第二个命令实际构建并组装产物。

未另行配置时，产物写入 `dist`。具体路径请查看命令输出。

## 选择平台格式

在准备支持的目标操作系统上构建，这些命令不提供交叉编译流程。

- **macOS Apple Silicon：** `app` 生成应用包，`zip` 生成归档，`dmg` 生成磁盘映像。
- **Windows x64：** `app` 生成应用目录，`zip` 生成便携归档，`nsis` 生成安装器。
- **Linux x64：** `appimage` 生成 AppImage，需要在准备支持的 Linux 环境中验证。

macOS、Windows 默认使用 app 和 zip，Linux 默认使用 appimage。可以通过重复的 `--format` 参数覆盖单次调用，也可以将以下片段合并进已有的 `package` 对象：

```json
{
  "platforms": {
    "macos": { "formats": ["app", "dmg"] },
    "windows": { "formats": ["nsis"], "nsis_install_mode": "currentUser" },
    "linux": { "formats": ["appimage"] }
  }
}
```

平台列表会替换共享的 `package.formats` 列表。生成 Windows 安装器前先安装 NSIS，可执行文件图标则需要 Windows SDK 资源编译器。

## Windows 安装范围

默认的 `currentUser` 面向当前用户安装，无需管理员权限。`perMachine` 提权后面向所有用户安装。`both` 允许在安装时选择范围，即使选择当前用户安装也可能请求提权。

如果应用旧版使用机器级安装器，后续更新应显式保留 `perMachine`。修改这个设置不会将已有安装从一个范围迁移到另一个范围。

## 签名与公证

本地打包本身不会建立可信的发布者身份。在 macOS 上，`--sign` 请求签名，`--notarize` 使用已配置凭据提交公证、装订并验证分发产物。

公开发布前，先检查当前的签名选项：

```sh
proton_cli package --help
```

为目标平台配置自己的签名身份与凭据，不要把私有签名凭据写入应用源码。具体支持选项见[打包参考](https://github.com/moonbit-community/proton#packaging)；仓库文档可能领先于本指南对应版本。

## 验证真正要分发的产物

停止开发服务器，在源码目录之外启动打包应用，检查：

1. 前端能从打包资源加载，不需要 localhost 服务器。
2. 命令和所需原生能力正常工作。
3. 能读取声明的附加资源，可写数据使用预期位置。
4. 关闭窗口和显式退出符合应用的生命周期策略。

对于 Todo 教程，在打包应用中添加待办项并使用 Complete all/Reopen all，再分发产物。构建检查和打包 dry run 都不会执行这一步实际运行验证。
