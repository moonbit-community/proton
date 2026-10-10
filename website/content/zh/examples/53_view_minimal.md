# 嵌入浏览器视图

本例在主窗口侧栏旁放置一个子浏览器，展示主页面与可独立导航的浏览器视图之间的关系，以及如何显式设置子视图的边界。

[53_view_minimal](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/53_view_minimal) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/bdb169302952db553deda6de015887c7a6a19831/examples/53_view_minimal/main.mbt)

## 行为

`WindowConfig.views` 在 x=288 处添加 832 × 720 子浏览器，独立于宿主 HTML 加载 example.com。

## 实现说明

以下为入口中的节选，完整上下文见本页源码链接。

```moonbit
async fn main {
  @proton.App(
    @proton.WindowConfig(
      "Minimal View",
      @proton.AppEntry::Html(sidebar),
      width=1120,
      height=720,
      views=[
        (
          "browser",
          @proton.view("https://example.com/", width=832, height=720, x=288),
        ),
      ],
    ),
  )
  .debug(enabled=true)
  .identifier("dev.proton.53-view-minimal")
  .run_or_abort()
}
```

主浏览器渲染侧栏，`WindowConfig.views` 在同一个原生窗口中创建第二个浏览器。x=288 留出侧栏宽度，子视图独立加载 example.com，适合宿主外壳内嵌页面，而非另开顶层窗口。

示例故意使用固定几何尺寸。实际布局应在 resize 后重新计算子视图边界，并决定如何处理远程导航。对本地主页面授权不表示远程子页面也应拥有相同能力。

## 运行

完成[源码检出与运行时安装](../introduction/installation.md#源码与运行时)后，在仓库根目录执行：

```sh
moon -C examples run 53_view_minimal --target native
```

## 限制与使用边界

远程页面需要联网。最小示例使用固定边界，响应式布局需由应用处理。父窗口关闭会结束子视图生命周期。
