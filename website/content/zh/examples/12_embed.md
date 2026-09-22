# 嵌入 HTML

[English](../../examples/12_embed.html)

将 HTML 源文件嵌入 MoonBit 字符串。

[12_embed](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/12_embed) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/12_embed/main.mbt), [hello.html](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/12_embed/hello.html), [hello.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/12_embed/hello.mbt), [moon.pkg](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/12_embed/moon.pkg)

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

## 运行

需满足[运行环境要求](../installation.md)。在仓库根目录执行：

```sh
moon -C examples run 12_embed --target native
```

## 限制与使用边界

修改 hello.html，而不是生成的 hello.mbt。嵌入 HTML 不会自动包含旁边的文件；独立 JS/CSS 见静态资源示例。
