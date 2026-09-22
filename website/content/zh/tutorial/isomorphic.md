# 构建完整 Todo 应用

[English](../../tutorial/isomorphic.html)

本教程使用 isomorphic 模板连接共享契约、原生状态和 Rabbita 界面。先运行生成的 Todo 应用，再跨三个模块加入 **Complete all** 和 **Reopen all** 操作。

请先完成[环境准备](../introduction/installation.md)，包括 Warren 构建工具需要的 Node.js。无需修改之前的 minimal 应用。

## 创建并体验应用

在另一个 MoonBit 工作区之外执行：

```sh
proton_cli new todo-app --template isomorphic --yes
cd todo-app
moon update
moon install moonbit-community/warren@0.3.3
proton_cli cef setup
```

生成的配置已经调用安装好的 Warren 可执行文件。启动应用：

```sh
proton_cli dev
```

添加“Alpha”和“Beta”，标记其中一个完成，再搜索它。生成的应用已经支持创建、完成、删除和过滤查询。列表保存在内存中，重启后会清空。

编辑前先关闭应用。保留生成的模块名与包导入，以下修改均在现有模板上追加。

## 理解已有流程

可以同时打开这些文件：

- **`shared/todo_contract.mbt`** 定义请求、`TodoItem`、`TodoSnapshot`、`MutationReply` 及描述符。
- **`backend/todo/backend.mbt`** 保存列表与修订号，实现修改操作。
- **`backend/todo/commands.mbt`** 将描述符绑定到方法。
- **`frontend/main/main.mbt`** 管理输入草稿、UI 消息和 Rabbita 视图。
- **`backend/app/main.mbt`** 启动应用、安装命令，并在窗口生命周期中建立和移除事件目标。

已有的创建操作中，`Create` 调用 `create_todo`，后端校验并修改状态，`MutationReply` 返回成功或业务拒绝，`todos_changed` 让前端快照失效并触发查询。

前端草稿是本地 UI 状态，后端列表是应用状态的权威来源。新操作应修改后端完整列表，而不只是当前搜索结果中可见的行。

## 1. 扩展共享契约

在 **`shared/todo_contract.mbt`** 末尾追加：

```moonbit
///|
pub(all) struct SetAllCompletedRequest {
  completed : Bool
} derive(ToJson, FromJson)

///|
pub extend SetAllCompletedRequest with ToJson::{to_json}

///|
pub extend SetAllCompletedRequest with FromJson::{from_json}

///|
pub let set_all_completed : @proton_contract.Command[
  SetAllCompletedRequest,
  MutationReply,
] = @proton_contract.command("set_all_completed")
```

布尔值选择完成或重新打开。复用模板的 `MutationReply`，可以继续使用现有响应处理逻辑。两个构建目标导入同一个描述符。

## 2. 实现状态修改

在 **`backend/todo/backend.mbt`** 末尾追加：

```moonbit
///|
fn Backend::set_all_completed(
  self : Backend,
  completed : Bool,
) -> @shared.MutationReply {
  let mut changed = false
  for index = 0; index < self.todos.length(); index = index + 1 {
    let todo = self.todos[index]
    if todo.completed != completed {
      self.todos[index] = { ..todo, completed, }
      changed = true
    }
  }
  if changed {
    self.version += 1
  }
  @shared.Changed(version=self.version)
}
```

操作遍历完整列表，有实际变化时只将修订号增加一次。重复相同操作不会改变修订号；即使列表为空，也返回当前版本。

## 3. 注册处理器并通知数据失效

在 **`backend/todo/commands.mbt`** 的已有 **`Backend::register_commands`** 方法内，与其他绑定并列添加：

```moonbit
registrar.bind(@shared.set_all_completed, (_context, request) => {
  let reply = self.set_all_completed(request.completed)
  self.notify(reply)
  reply
})
```

保留原有绑定。`self.notify` 是生成后端中已有的辅助方法，会向应用窗口生命周期中保存的事件目标发送 `todos_changed`。

这里不需要新事件类型。它与其他 Todo 修改一样改变了状态，已有观察者重新执行相同查询即可。

## 4. 接入前端操作

本步骤全部修改 **`frontend/main/main.mbt`**。

在已有的 `enum Msg` 内添加一个分支：

```moonbit
SetAllCompleted(Bool)
```

在 `update` 已有的 `match msg` 内添加以下分支：

```moonbit
SetAllCompleted(completed) =>
  (
    { ..model, error: None, },
    @proton_rabbita.invoke(
      @shared.set_all_completed,
      { completed, },
      reply => emit(MutationReceived(reply)),
      error => emit(CommandFailed(error)),
    ),
  )
```

`model`、`emit`、`MutationReceived` 和 `CommandFailed` 已由该函数与模块定义。成功路径复用模板的修改响应处理，错误路径继续显示 bridge 失败。

在 `view` 中找到 `div(class="todo-toolbar", [...])`，将下面两个按钮追加到其子元素数组中，放在已有 Refresh 按钮之后：

```moonbit
button(
  type_="button",
  on_click=emit(SetAllCompleted(true)),
  "Complete all",
),
button(
  type_="button",
  on_click=emit(SetAllCompleted(false)),
  "Reopen all",
),
```

模板已经导入 `button`，无需增加导入。消息中的布尔值经由请求传到后端。

## 5. 检查行为

在 **`backend/todo/backend_wbtest.mbt`** 中追加这个回归检查：

```moonbit
///|
test "bulk completion changes the whole list once" {
  let backend = Backend()
  ignore(backend.create("Alpha"))
  ignore(backend.create("Beta"))
  assert_true(backend.set_all_completed(true) is @shared.Changed(version=3))
  assert_true(backend.snapshot("").todos.all(todo => todo.completed))
  assert_true(backend.set_all_completed(true) is @shared.Changed(version=3))
  assert_true(backend.set_all_completed(false) is @shared.Changed(version=4))
  assert_true(backend.snapshot("").todos.all(todo => !todo.completed))
}
```

在项目根目录执行：

```sh
moon check --target js,native
moon -C backend test todo --target native
moon -C frontend test --target js
proton_cli dev
```

添加两个待办项，**Complete all** 应将两项全部完成，**Reopen all** 应重新打开两项。搜索到其中一项后重复操作，再清空过滤条件，应看到两项都发生变化。重复点击 Complete all 不应继续增加修订号。

如果后端变化但显示不更新，检查是否保留 `self.notify` 和窗口 attach/detach 钩子。如果新命令不可用，检查注册代码并重启后端。

## 界面如何保持最新

模板的 `todo_app` 创建 `list_todos` 查询，并用 `todos_changed` 使其失效。应用内的查询辅助包先订阅，再获取数据，在输入变化时取消被替代的旧请求。

修改响应刷新发起操作的界面，事件则使观察者的数据失效。两者可能重叠，所以辅助包跟踪请求代次，避免旧结果覆盖新的搜索。这些是 `frontend/internal/query` 中的应用代码，不是另一个服务器，也不是 Proton 的公共状态管理框架。

## 构建完成后的应用

停止开发进程，执行：

```sh
proton_cli build
proton_cli package --dry-run
proton_cli package --release
```

在不运行开发服务器的情况下启动打包应用，重复验证两个按钮。平台格式和签名见[构建与分发](../command-line-interface/packaging.md)。

本示例不包含持久化存储。后续添加时，应将加载、校验和写入放在后端，并保持相同的前端命令与事件接口。
