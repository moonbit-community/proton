///|
struct LocaleRequest {} derive(ToJson, FromJson)

///|
pub extend LocaleRequest with ToJson::{to_json}

///|
pub extend LocaleRequest with FromJson::{from_json}

///|
struct LocaleSnapshot {
  locale : String
  preferred_languages : Array[String]
} derive(ToJson, FromJson)

///|
pub extend LocaleSnapshot with ToJson::{to_json}

///|
pub extend LocaleSnapshot with FromJson::{from_json}

///|
let i18n_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/i18n",
  js_namespace="i18n",
)

///|
let current_locale : @proton_contract.Command[LocaleRequest, LocaleSnapshot] = i18n_contract.command(
  "current",
)

///|
fn i18n_extension() -> @proton_extension.Extension {
  @proton_extension.typed(i18n_contract, [current_locale.contract_route()], fn(
    registrar,
  ) raise {
    registrar.bind(current_locale, (context, _request) => LocaleSnapshot::{
      locale: context.locale().to_string(),
      preferred_languages: context
      .preferred_languages()
      .map(locale => locale.to_string()),
    })
  })
}

///|
fn menu_bar() -> @proton.MenuBar {
  @proton.MenuBar::new(menus=[
    @proton.Menu::role(@proton.MenuRole::Edit),
    @proton.Menu::role(@proton.MenuRole::Window),
    @proton.Menu::role(@proton.MenuRole::Help, items=[
      @proton.MenuItem::command("help.locale", "语言环境契约"),
    ]),
  ])
}

///|
#cfg(platform="windows")
async fn main {
  let locale = @proton.Locale::parse("zh-CN") catch {
    error => abort(error.message())
  }
  @proton.html("Proton 国际化", resource, width=860, height=600, debug=true)
  .locale(locale)
  .expose(i18n_extension())
  .run_or_abort()
}

///|
#cfg(not(platform="windows"))
async fn main {
  let locale = @proton.Locale::parse("zh-CN") catch {
    error => abort(error.message())
  }
  @proton.html("Proton 国际化", resource, width=860, height=600, debug=true)
  .locale(locale)
  .menu(menu_bar())
  .expose(i18n_extension())
  .run_or_abort()
}
