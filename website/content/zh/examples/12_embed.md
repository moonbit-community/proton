# 嵌入 HTML

本例将 HTML 保存在独立源文件中，构建时嵌入可执行文件并作为 MoonBit 字符串加载。页面内容可以单独维护，运行时不需要再查找这个 HTML 文件。

[12_embed](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/12_embed) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/12_embed/main.mbt), [hello.html](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/12_embed/hello.html), [hello.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/12_embed/hello.mbt), [moon.pkg](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/12_embed/moon.pkg)

## 行为

窗口通过 html() 加载嵌入资源。包的 prebuild 规则从 hello.html 生成 hello.mbt。

```moonbit
///|
async fn main {
  @proton.html("12 embed", resource, width=800, height=600, debug=true)
  .identifier("dev.proton.12-embed")
  .run_or_abort()
}
```

## 实现说明

resource 由包中的 embed 预构建规则从 hello.html 生成。运行时接收的仍是与最小示例相同的字符串，不是在启动时读取磁盘上的 hello.html。

修改 hello.html 后重新构建，不修改生成的 hello.mbt。嵌入一个文档不会自动嵌入它引用的相对图片或脚本；一组资源应使用 asset 入口。

## 运行

完成[源码检出与运行时安装](../introduction/installation.md#源码与运行时)后，在仓库根目录执行：

```sh
moon -C examples run 12_embed --target native
```

## 限制与使用边界

修改 hello.html，而不是生成的 hello.mbt。嵌入 HTML 不会自动包含旁边的文件；独立 JS/CSS 见静态资源示例。
