///|
/// A second consumer of the generated application's internal query module.
/// The backend lists real, disposable directories created by the smoke test.
fn directory_browser() -> @rabbita.Val[@html.Html] {
  let directory = @query.create(@shared.list_directory, initial="alpha")
  directory.state.view(state => {
    let content = match state.data() {
      Some((path, entries)) => @html.div([
        @html.p(class="directory-path", "Directory: " + path),
        if entries.is_empty() {
          @html.p("Empty directory.")
        } else {
          @html.ul(entries.map(name => @html.li(class="directory-entry", name)))
        },
      ])
      None => @html.nothing
    }
    @html.div([
      @html.h1("Directory browser"),
      @html.div(["alpha", "beta", "empty", "missing", "slow"].map(path => {
        @html.button(on_click=(directory.set_input)(path), "Open " + path)
      })),
      @html.button(on_click=directory.refresh, "Reload directory"),
      match state {
        @query.Loading(input~, ..) => @html.p(class="query-status", "Loading " + input),
        @query.Failed(input~, error~, ..) =>
          @html.p(class="query-error", "Cannot read " + input + ": " + error.message()),
        @query.Ready(..) => @html.nothing
      },
      content,
    ])
  })
}

///|
fn app() -> @rabbita.Val[@html.Html] {
  let (visible, set_visible) = @rabbita.create_variable(true)
  let content = visible.switch_by(
    shown => if shown {
      directory_browser()
    } else {
      @rabbita.Val::constant(@html.p("Directory browser closed."))
    },
    by=shown => shown.to_string(),
  )
  content.view2(visible, (content, shown) => @html.div(class="app-shell", [
    @html.button(on_click=set_visible(value => !value), if shown { "Close browser" } else { "Open browser" }),
    content,
  ]))
}

///|
#warnings("-alert_unstable")
fn main {
  @rabbita.new(app).mount("app")
}
