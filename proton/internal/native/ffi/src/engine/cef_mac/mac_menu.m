#if defined(__APPLE__)

#include "mac_menu.h"

#include "../../proton_event.h"
#include "../../proton_engine.h"
#include "mac_window.h"

#import <Cocoa/Cocoa.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_proton_app_menu_installed = 0;
static proton_engine_runtime_t *g_menu_runtime = NULL;

@class ProtonMenuCommandTarget;
static ProtonMenuCommandTarget *g_menu_command_target = nil;

static void proton_engine_set_message(char *error,
                                      size_t error_len,
                                      const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
  }
}

static void proton_engine_enqueue_menu_command(
    NSString *command_id,
    proton_window_id_t focused_window);

@interface ProtonMenuCommandTarget : NSObject
- (void)performMenuCommand:(id)sender;
@end

@implementation ProtonMenuCommandTarget
- (void)performMenuCommand:(id)sender {
  id represented = nil;
  if ([sender respondsToSelector:@selector(representedObject)]) {
    represented = [sender representedObject];
  }
  if ([represented isKindOfClass:[NSString class]]) {
    proton_window_id_t focused_window =
        proton_engine_window_public_id_for_native_window([NSApp keyWindow]);
    proton_engine_enqueue_menu_command((NSString *)represented,
                                       focused_window);
  }
}
@end

static NSString *proton_engine_application_name(void) {
  NSString *name =
      [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
  if (name == nil || [name length] == 0) {
    name = [[NSProcessInfo processInfo] processName];
  }
  if (name == nil || [name length] == 0) {
    name = @"Proton";
  }
  return name;
}

static NSMenuItem *proton_engine_add_menu_item(NSMenu *menu,
                                               NSString *title,
                                               SEL action,
                                               NSString *key) {
  return [menu addItemWithTitle:title action:action keyEquivalent:key];
}

static void proton_engine_add_top_level_menu(NSMenu *main_menu,
                                             NSString *title,
                                             NSMenu *submenu,
                                             BOOL first) {
  NSMenuItem *item = first
                         ? [main_menu insertItemWithTitle:title
                                                  action:nil
                                           keyEquivalent:@""
                                                 atIndex:0]
                         : proton_engine_add_menu_item(
                               main_menu, title, nil, @"");
  [main_menu setSubmenu:submenu forItem:item];
}

static NSMenu *proton_engine_create_app_menu(NSString *app_name) {
  NSMenu *app_menu = [[NSMenu alloc] initWithTitle:app_name];
  proton_engine_add_menu_item(
      app_menu, [NSString stringWithFormat:@"Hide %@", app_name],
      @selector(hide:), @"h");
  NSMenuItem *hide_others = proton_engine_add_menu_item(
      app_menu, @"Hide Others", @selector(hideOtherApplications:), @"h");
  [hide_others setKeyEquivalentModifierMask:
                   NSEventModifierFlagOption | NSEventModifierFlagCommand];
  proton_engine_add_menu_item(app_menu, @"Show All",
                              @selector(unhideAllApplications:), @"");
  [app_menu addItem:[NSMenuItem separatorItem]];
  proton_engine_add_menu_item(
      app_menu, [NSString stringWithFormat:@"Quit %@", app_name],
      @selector(terminate:), @"q");
  return app_menu;
}

static NSMenu *proton_engine_create_edit_menu(void) {
  NSMenu *edit_menu = [[NSMenu alloc] initWithTitle:@"Edit"];
  proton_engine_add_menu_item(edit_menu, @"Undo", @selector(undo:), @"z");
  proton_engine_add_menu_item(edit_menu, @"Redo", @selector(redo:), @"Z");
  [edit_menu addItem:[NSMenuItem separatorItem]];
  proton_engine_add_menu_item(edit_menu, @"Cut", @selector(cut:), @"x");
  proton_engine_add_menu_item(edit_menu, @"Copy", @selector(copy:), @"c");
  proton_engine_add_menu_item(edit_menu, @"Paste", @selector(paste:), @"v");
  proton_engine_add_menu_item(edit_menu, @"Select All", @selector(selectAll:),
                              @"a");
  return edit_menu;
}

static NSMenu *proton_engine_create_window_menu(void) {
  NSMenu *window_menu = [[NSMenu alloc] initWithTitle:@"Window"];
  proton_engine_add_menu_item(window_menu, @"Minimize",
                              @selector(performMiniaturize:), @"m");
  proton_engine_add_menu_item(window_menu, @"Zoom", @selector(performZoom:),
                              @"");
  proton_engine_add_menu_item(window_menu, @"Close", @selector(performClose:),
                              @"w");
  return window_menu;
}

static NSString *proton_engine_menu_text(const char *value) {
  return value != NULL ? [NSString stringWithUTF8String:value] : nil;
}

static SEL proton_engine_menu_role_selector(NSString *role) {
  if ([role isEqualToString:@"quit"]) {
    return @selector(terminate:);
  }
  if ([role isEqualToString:@"hide"]) {
    return @selector(hide:);
  }
  if ([role isEqualToString:@"hide_others"]) {
    return @selector(hideOtherApplications:);
  }
  if ([role isEqualToString:@"show_all"]) {
    return @selector(unhideAllApplications:);
  }
  if ([role isEqualToString:@"close"]) {
    return @selector(performClose:);
  }
  if ([role isEqualToString:@"minimize"]) {
    return @selector(performMiniaturize:);
  }
  if ([role isEqualToString:@"zoom"]) {
    return @selector(performZoom:);
  }
  if ([role isEqualToString:@"undo"]) {
    return @selector(undo:);
  }
  if ([role isEqualToString:@"redo"]) {
    return @selector(redo:);
  }
  if ([role isEqualToString:@"cut"]) {
    return @selector(cut:);
  }
  if ([role isEqualToString:@"copy"]) {
    return @selector(copy:);
  }
  if ([role isEqualToString:@"paste"]) {
    return @selector(paste:);
  }
  if ([role isEqualToString:@"select_all"]) {
    return @selector(selectAll:);
  }
  return NULL;
}

static NSString *proton_engine_menu_role_label(NSString *role,
                                               NSString *app_name) {
  if ([role isEqualToString:@"quit"]) {
    return [NSString stringWithFormat:@"Quit %@", app_name];
  }
  if ([role isEqualToString:@"hide"]) {
    return [NSString stringWithFormat:@"Hide %@", app_name];
  }
  if ([role isEqualToString:@"hide_others"]) {
    return @"Hide Others";
  }
  if ([role isEqualToString:@"show_all"]) {
    return @"Show All";
  }
  if ([role isEqualToString:@"close"]) {
    return @"Close";
  }
  if ([role isEqualToString:@"minimize"]) {
    return @"Minimize";
  }
  if ([role isEqualToString:@"zoom"]) {
    return @"Zoom";
  }
  if ([role isEqualToString:@"select_all"]) {
    return @"Select All";
  }
  NSString *first = [[role substringToIndex:1] uppercaseString];
  NSString *rest = [[role substringFromIndex:1] stringByReplacingOccurrencesOfString:@"_"
                                                                          withString:@" "];
  return [first stringByAppendingString:rest];
}

static NSString *proton_engine_menu_role_key(NSString *role) {
  if ([role isEqualToString:@"quit"]) {
    return @"q";
  }
  if ([role isEqualToString:@"hide"] || [role isEqualToString:@"hide_others"]) {
    return @"h";
  }
  if ([role isEqualToString:@"close"]) {
    return @"w";
  }
  if ([role isEqualToString:@"minimize"]) {
    return @"m";
  }
  if ([role isEqualToString:@"undo"]) {
    return @"z";
  }
  if ([role isEqualToString:@"redo"]) {
    return @"Z";
  }
  if ([role isEqualToString:@"cut"]) {
    return @"x";
  }
  if ([role isEqualToString:@"copy"]) {
    return @"c";
  }
  if ([role isEqualToString:@"paste"]) {
    return @"v";
  }
  if ([role isEqualToString:@"select_all"]) {
    return @"a";
  }
  return @"";
}

static int proton_engine_add_custom_menu_item(NSMenu *menu,
                                              const proton_menu_item_t *item,
                                              NSString *app_name,
                                              char *error,
                                              size_t error_len) {
  if (item->kind == PROTON_MENU_ITEM_SEPARATOR) {
    [menu addItem:[NSMenuItem separatorItem]];
    return 1;
  }
  if (item->kind == PROTON_MENU_ITEM_COMMAND) {
    NSString *label = proton_engine_menu_text(item->label);
    NSString *command_id = proton_engine_menu_text(item->id);
    NSString *key = proton_engine_menu_text(item->key);
    if (label == nil || command_id == nil) {
      proton_engine_set_message(error, error_len,
                                "menu command requires label and id");
      return 0;
    }
    if (g_menu_command_target == nil) {
      g_menu_command_target = [ProtonMenuCommandTarget new];
    }
    NSMenuItem *menu_item = proton_engine_add_menu_item(
        menu, label, @selector(performMenuCommand:), key != nil ? key : @"");
    [menu_item setTarget:g_menu_command_target];
    [menu_item setRepresentedObject:command_id];
    return 1;
  }
  if (item->kind == PROTON_MENU_ITEM_ROLE) {
    NSString *role = proton_engine_menu_text(item->role);
    SEL selector = proton_engine_menu_role_selector(role);
    if (selector == NULL) {
      proton_engine_set_message(error, error_len, "menu role is unsupported");
      return 0;
    }
    NSString *label = proton_engine_menu_text(item->label);
    NSString *key = proton_engine_menu_text(item->key);
    NSMenuItem *menu_item = proton_engine_add_menu_item(
        menu, label != nil ? label : proton_engine_menu_role_label(role, app_name),
        selector, key != nil ? key : proton_engine_menu_role_key(role));
    if ([role isEqualToString:@"hide_others"]) {
      [menu_item setKeyEquivalentModifierMask:
                     NSEventModifierFlagOption | NSEventModifierFlagCommand];
    }
    return 1;
  }
  proton_engine_set_message(error, error_len, "menu item kind is unsupported");
  return 0;
}

static NSMenu *proton_engine_create_custom_menu(const proton_menu_t *definition,
                                                NSString *app_name,
                                                char *error,
                                                size_t error_len) {
  NSString *label = proton_engine_menu_text(definition->label);
  if (label == nil) {
    proton_engine_set_message(error, error_len,
                              "menu requires label and items");
    return nil;
  }
  NSMenu *menu = [[NSMenu alloc] initWithTitle:label];
  for (size_t index = 0; index < definition->item_count; index++) {
    if (!proton_engine_add_custom_menu_item(
            menu, &definition->items[index], app_name, error, error_len)) {
      return nil;
    }
  }
  return menu;
}

static BOOL proton_engine_menu_definitions_include_role(
    const proton_menu_bar_t *menu_bar, proton_menu_role_t role) {
  for (size_t index = 0; index < menu_bar->menu_count; index++) {
    if (menu_bar->menus[index].role == role) {
      return YES;
    }
  }
  return NO;
}

static int proton_engine_install_menu_definitions(
    const proton_menu_bar_t *menu_bar, char *error, size_t error_len) {
  NSString *app_name = proton_engine_application_name();
  NSMenu *main_menu = [[NSMenu alloc] initWithTitle:@""];
  NSMenu *window_menu = nil;

  for (size_t index = 0; index < menu_bar->menu_count; index++) {
    const proton_menu_t *definition = &menu_bar->menus[index];
    NSString *label = proton_engine_menu_text(definition->label);
    NSMenu *menu = proton_engine_create_custom_menu(
        definition, app_name, error, error_len);
    if (menu == nil || label == nil) {
      return 0;
    }
    proton_engine_add_top_level_menu(
        main_menu, label, menu,
        definition->role == PROTON_MENU_ROLE_APPLICATION);
    if (definition->role == PROTON_MENU_ROLE_WINDOW) {
      window_menu = menu;
    }
  }

  if (!proton_engine_menu_definitions_include_role(
          menu_bar, PROTON_MENU_ROLE_APPLICATION)) {
    proton_engine_add_top_level_menu(
        main_menu, app_name, proton_engine_create_app_menu(app_name), YES);
  }
  if (!proton_engine_menu_definitions_include_role(
          menu_bar, PROTON_MENU_ROLE_EDIT)) {
    proton_engine_add_top_level_menu(
        main_menu, @"Edit", proton_engine_create_edit_menu(), NO);
  }
  if (!proton_engine_menu_definitions_include_role(
          menu_bar, PROTON_MENU_ROLE_WINDOW)) {
    window_menu = proton_engine_create_window_menu();
    proton_engine_add_top_level_menu(
        main_menu, @"Window", window_menu, NO);
  }

  [NSApp setMainMenu:main_menu];
  if (window_menu != nil) {
    [NSApp setWindowsMenu:window_menu];
  }
  g_proton_app_menu_installed = 1;
  return 1;
}

void proton_engine_menu_install_default(void) {
  if (g_proton_app_menu_installed) {
    return;
  }
  char error[256] = {0};
  const proton_menu_bar_t empty_menu = {0};
  (void)proton_engine_install_menu_definitions(&empty_menu, error,
                                               sizeof(error));
}

int32_t proton_engine_menu_set_on_main(const proton_menu_bar_t *menu_bar,
                                       char *error, size_t error_len) {
  if (menu_bar == NULL) {
    proton_engine_set_message(error, error_len, "menu config is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!proton_engine_install_menu_definitions(menu_bar, error, error_len)) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  return PROTON_OK;
}

static void proton_engine_enqueue_menu_command(
    NSString *command_id,
    proton_window_id_t focused_window) {
  if (g_menu_runtime == NULL) {
    return;
  }
  const char *utf8 = command_id != nil ? [command_id UTF8String] : "";
  proton_event_t *event = proton_event_create(PROTON_EVENT_MENU_COMMAND);
  if (utf8 == NULL || event == NULL ||
      !proton_event_set_text(&event->text_a, utf8)) {
    proton_event_destroy(event);
    return;
  }
  event->window = focused_window;
  (void)proton_event_publish(event);
}

void proton_engine_menu_set_runtime(proton_engine_runtime_t *runtime) {
  g_menu_runtime = runtime;
}

void proton_engine_menu_clear_runtime(proton_engine_runtime_t *runtime) {
  if (g_menu_runtime == runtime) {
    g_menu_runtime = NULL;
  }
}

#endif
