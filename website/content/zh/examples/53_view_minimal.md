# 嵌入浏览器视图

在宿主侧边栏旁声明子浏览器。

[53_view_minimal](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/53_view_minimal) · 关键文件：[main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/53_view_minimal/main.mbt)

## 行为

with_view() 在 x=288 处添加 832 × 720 子浏览器，独立于宿主 HTML 加载 example.com。

## 运行

需满足[运行环境要求](../introduction/installation.md)。在仓库根目录执行：

```sh
moon -C examples run 53_view_minimal --target native
```

## 限制与使用边界

远程页面需要联网。最小示例使用固定边界，响应式布局需由应用处理。父窗口关闭会结束子视图生命周期。
