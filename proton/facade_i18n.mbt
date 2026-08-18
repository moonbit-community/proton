///|
priv enum FrameworkLanguage {
  English
  SimplifiedChinese
}

///|
priv struct FrameworkCatalog {
  startup_failure_title : String
  startup_failure_summary : String
  application_error_title : String
  application_error_summary : String
  file_menu : String
  edit_menu : String
  view_menu : String
  window_menu : String
  help_menu : String
  quit_prefix : String
  hide_prefix : String
  hide_others : String
  show_all : String
  close : String
  minimize : String
  zoom : String
  undo : String
  redo : String
  cut : String
  copy : String
  paste : String
  select_all : String
  dialog_ok : String
  dialog_cancel : String
  titlebar_minimize : String
  titlebar_maximize : String
  titlebar_restore : String
  titlebar_close : String
}

///|
fn framework_language(locale : @locale.Locale) -> FrameworkLanguage {
  if locale.language() == "zh" && locale.region() == Some("CN") {
    SimplifiedChinese
  } else {
    English
  }
}

///|
fn framework_catalog(
  preferences : @locale.LocalePreferences,
) -> FrameworkCatalog {
  match framework_language(preferences.locale()) {
    English =>
      FrameworkCatalog::{
        startup_failure_title: "Application Startup Failed",
        startup_failure_summary: "The application could not start.",
        application_error_title: "Application Error",
        application_error_summary: "The application encountered an error.",
        file_menu: "File",
        edit_menu: "Edit",
        view_menu: "View",
        window_menu: "Window",
        help_menu: "Help",
        quit_prefix: "Quit ",
        hide_prefix: "Hide ",
        hide_others: "Hide Others",
        show_all: "Show All",
        close: "Close",
        minimize: "Minimize",
        zoom: "Zoom",
        undo: "Undo",
        redo: "Redo",
        cut: "Cut",
        copy: "Copy",
        paste: "Paste",
        select_all: "Select All",
        dialog_ok: "OK",
        dialog_cancel: "Cancel",
        titlebar_minimize: "Minimize",
        titlebar_maximize: "Maximize",
        titlebar_restore: "Restore",
        titlebar_close: "Close",
      }
    SimplifiedChinese =>
      FrameworkCatalog::{
        startup_failure_title: "应用启动失败",
        startup_failure_summary: "应用无法启动。",
        application_error_title: "应用错误",
        application_error_summary: "应用遇到错误。",
        file_menu: "文件",
        edit_menu: "编辑",
        view_menu: "显示",
        window_menu: "窗口",
        help_menu: "帮助",
        quit_prefix: "退出 ",
        hide_prefix: "隐藏 ",
        hide_others: "隐藏其他应用",
        show_all: "全部显示",
        close: "关闭窗口",
        minimize: "最小化",
        zoom: "缩放",
        undo: "撤销",
        redo: "重做",
        cut: "剪切",
        copy: "拷贝",
        paste: "粘贴",
        select_all: "全选",
        dialog_ok: "确定",
        dialog_cancel: "取消",
        titlebar_minimize: "最小化",
        titlebar_maximize: "最大化",
        titlebar_restore: "还原",
        titlebar_close: "关闭",
      }
  }
}

///|
fn startup_failure_title(preferences : @locale.LocalePreferences) -> String {
  framework_catalog(preferences).startup_failure_title
}

///|
fn startup_failure_summary(preferences : @locale.LocalePreferences) -> String {
  framework_catalog(preferences).startup_failure_summary
}

///|
fn application_error_title(preferences : @locale.LocalePreferences) -> String {
  framework_catalog(preferences).application_error_title
}

///|
fn application_error_summary(preferences : @locale.LocalePreferences) -> String {
  framework_catalog(preferences).application_error_summary
}

///|
fn framework_failure_message(summary : String, detail : String) -> String {
  if detail.is_empty() {
    summary
  } else {
    summary + "\n\n" + detail
  }
}
