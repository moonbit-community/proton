# 项目结构

[English](../project-structure.html)

Proton 项目包含应用代码、MoonBit 包元数据和 CLI 配置。两种模板的区别主要在前端的组织方式，使用的原生运行时相同。

## Minimal 项目

```text
hello-proton/
  moon.mod
  proton.project.json
  app/
    moon.pkg
    main.mbt
```

- **`moon.mod`** 定义模块名称和带版本的依赖。导入库中的包之前，先在这里添加该库。
- **`app/moon.pkg`** 导入入口使用的包，并将其声明为原生可执行包。
- **`app/main.mbt`** 定义 async 入口、HTML 和应用构建器。
- **`proton.project.json`** 告诉 CLI 要运行哪个包，以及如何标识和打包应用。

添加模块依赖不会自动将其导入每个包。例如，[命令一章](commands-events.md)会同时添加 `proton_contract` 模块依赖和包导入。

## Isomorphic 项目

希望用 MoonBit 编写前端时，使用 `--template isomorphic` 创建另一个项目：

```text
todo-app/
  moon.work
  proton.project.json
  shared/
    moon.mod
    moon.pkg
    todo_contract.mbt
  backend/
    moon.mod
    app/
      moon.pkg
      main.mbt
    todo/
      moon.pkg
      backend.mbt
      commands.mbt
  frontend/
    moon.mod
    main/
      moon.pkg
      main.mbt
    internal/query/
    public/
```

根目录的 `moon.work` 连接三个模块：

- **shared** 定义可序列化的载荷，以及命令、事件描述符，供两个构建目标使用。
- **backend** 编译为原生代码。`todo/backend.mbt` 保存 Todo 状态和业务操作，`todo/commands.mbt` 绑定操作，`app/main.mbt` 启动应用。
- **frontend** 编译为 JavaScript。`main/main.mbt` 定义 Rabbita 界面，`public/` 保存 HTML 和样式表。

模板中的 `frontend/internal/query` 管理查询状态与订阅。它属于生成的应用，可以随应用一起修改，并不是 Proton 公共 API。

## 配置的边界

在 Moon 模块与包文件中声明依赖和导入，在 `proton.project.json` 中配置前后端构建路径及打包元数据，在 MoonBit 应用构建器中配置窗口、命令、capability 和生命周期钩子。

应用命令的绑定是普通代码，isomorphic 模板不需要额外添加命令代码生成规则。

## 生成的产物

Moon 将构建产物写入 `_build/`，将解析的依赖写入 `.mooncakes/`。Warren 将前端构建写入 `frontend/dist/`，打包工具将分发产物写入配置的输出目录，通常为根目录的 `dist/`。

不要直接修改这些产物，应修改源码或项目配置后重新构建。setup 安装的运行时和 helper 是用户级共享文件，不属于项目源码。

接下来可以了解[架构与进程模型](architecture.md)，或通过 [Todo 教程](isomorphic.md)修改一个完整应用。
