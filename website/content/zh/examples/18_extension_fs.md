# 文件系统能力

[English](../../examples/18_extension_fs.html)

渲染端在显式权限根目录内请求文件操作。

[18_extension_fs](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/18_extension_fs) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/18_extension_fs/main.mbt), [fs.html](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/18_extension_fs/fs.html)

## 行为

页面提供读写和目录操作。原生入口用 PermissionRoot 和操作允许列表注册 fs 能力。

```moonbit
///|
async fn main {
  @proton.html("18 extension fs", resource, width=960, height=720, debug=true)
  .capability(
    @fs.capability([
      @fs.PermissionRoot(".", [
        "read_file", "write_file", "exists", "kind", "size", "readdir", "mkdir",
        "remove", "rmdir", "rename", "realpath",
      ]),
    ]),
  )
  .identifier("dev.proton.18-extension-fs")
  .run_or_abort()
}
```

## 运行

需满足[运行环境要求](../introduction/installation.md)。在仓库根目录执行：

```sh
moon -C examples run 18_extension_fs --target native
```

## 限制与使用边界

示例允许操作工作目录内的文件，包括写入和删除。体验时使用临时目录；应用只应声明真正需要的路径和操作。
