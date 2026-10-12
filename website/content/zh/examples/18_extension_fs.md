# 文件系统能力

本例通过文件系统扩展让页面请求宿主文件操作。后端声明允许访问的目录和操作，页面通过命令 bridge 使用这份授权。

[18_extension_fs](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/18_extension_fs) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/18_extension_fs/main.mbt), [fs.html](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/18_extension_fs/fs.html)

## 行为

页面提供读写和目录操作。原生入口用 PermissionRoot 和操作允许列表注册 fs 能力。

```moonbit
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

## 实现说明

后端安装文件系统扩展，同时选择目录和允许的操作。renderer 提供路径及操作，但不能自行扩大授权根目录。文件不存在和操作未授权是不同失败情况。

此例为了演示允许写入与删除，迁移时应缩小操作列表并选定数据目录。HTML 与 JavaScript 展示直接扩展 bridge，MoonBit 前端也可使用类型化描述符。

## 运行

完成[源码检出与运行时安装](../introduction/installation.md#源码与运行时)后，在仓库根目录执行：

```sh
moon -C examples run 18_extension_fs --target native
```

## 限制与使用边界

示例允许操作工作目录内的文件，包括写入和删除。体验时使用临时目录；应用只应声明真正需要的路径和操作。
