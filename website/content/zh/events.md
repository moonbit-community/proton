# 向前端发送事件

[English](../events.html)

后端需要通知前端状态变化时，可以使用事件。本章继续修改[从前端调用后端](commands-events.md)中的问候示例：按钮仍然调用命令，但页面显示的消息改为来自事件。

## 声明事件

在 **`app/main.mbt`** 中，将下面的声明放在已有的 `greet` 描述符附近、`main` 函数之外：

```moonbit
///|
let greeted : @proton_contract.Event[String] =
  @proton_contract.event("greeted")
```

事件名为 `greeted`，载荷是字符串，没有响应类型：发送事件并不要求前端返回一个值。

## 发送给调用方

在 `.commands(...)` 中，将已有的 `registrar.bind(greet, ...)` 调用替换为：

```moonbit
registrar.bind(greet, (context, request) => {
  let message = "Hello, " + request.name + "!"
  context.emit_to_caller(greeted, message)
  message
})
```

`context.emit_to_caller` 将事件发送给调用此命令的页面。最后的 `message` 仍是命令响应。响应和事件是两次独立交付，不要依赖它们之间的特定到达顺序。

## 先监听，再触发操作

将 HTML 字符串中 `<script>` 与 `</script>` 之间的内容替换为下面的 JavaScript。在 MoonBit 多行字符串里，与前例一样为每行加上 `#|` 前缀：

```javascript
let stopListening;
document.querySelector("#greet").onclick = async () => {
  const result = document.querySelector("#result");
  const app = window.__MoonBit__.app;
  try {
    if (!stopListening) {
      stopListening = app.on("greeted", ({ payload }) => {
        result.textContent = "Event: " + payload;
      });
    }
    await app.greet({ name: document.querySelector("#name").value });
  } catch (error) {
    result.textContent = String(error);
  }
};
window.addEventListener("pagehide", () => {
  stopListening?.();
});
```

启动应用，输入名字后点击 **Greet**，预期显示“Event: Hello, Ada!”。再次点击会更新内容，而不会新增一个监听器。

第一次点击先注册监听，再调用命令，避免示例在订阅前就发送第一条通知。`app.on` 返回取消订阅函数。这里保留到页面离开；基于组件的界面则应在所属组件销毁时释放它。

## 在命令之外通知窗口

后台工作有时需要在发起它的命令已经结束后继续通知窗口。Todo 模板在 `window_lifecycle(on_ready=...)` 中保存 `context.events()`，在 `on_close` 中移除目标。保存的 `WindowEventEmitter` 可以在窗口存活期间发送类型化事件。

需要明确选择接收目标，不要保留已经关闭窗口的 emitter，也不要把每个事件都当作全局广播。建立和移除关联的完整过程见 [Todo 示例](isomorphic.md)。

## 事件与状态

监听器不在时可能错过事件。对于应用状态，应通过事件使数据失效，再查询最新快照。Todo 应用会先订阅，再做首次查询，并在 `todos_changed` 时刷新。

需要确认请求的操作结果时，使用命令响应；需要通知观察者时，使用事件。如果业务要求持久交付或重放，应在应用状态模型中实现，不应假定事件 bridge 提供这些保证。
