#include "menu.h"

#include "../../proton_engine.h"
#include "window.h"

#import <Cocoa/Cocoa.h>

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_proton_app_menu_installed = 0;
static proton_engine_menu_signal_callback_t g_menu_signal_callback = NULL;
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
static void proton_engine_reset_menu_commands(void);

void proton_engine_menu_set_signal_callback(
    proton_engine_menu_signal_callback_t callback) {
  g_menu_signal_callback = callback;
}

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
                                             NSMenu *submenu) {
  NSMenuItem *item = proton_engine_add_menu_item(main_menu, title, nil, @"");
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

static NSString *proton_engine_menu_string(NSDictionary *object,
                                           NSString *key) {
  id value = [object objectForKey:key];
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  return (NSString *)value;
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
                                              NSDictionary *item,
                                              NSString *app_name,
                                              char *error,
                                              size_t error_len) {
  NSString *kind = proton_engine_menu_string(item, @"kind");
  if ([kind isEqualToString:@"separator"]) {
    [menu addItem:[NSMenuItem separatorItem]];
    return 1;
  }
  if ([kind isEqualToString:@"command"]) {
    NSString *label = proton_engine_menu_string(item, @"label");
    NSString *command_id = proton_engine_menu_string(item, @"id");
    NSString *key = proton_engine_menu_string(item, @"key");
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
  if ([kind isEqualToString:@"role"]) {
    NSString *role = proton_engine_menu_string(item, @"role");
    SEL selector = proton_engine_menu_role_selector(role);
    if (selector == NULL) {
      proton_engine_set_message(error, error_len, "menu role is unsupported");
      return 0;
    }
    NSString *label = proton_engine_menu_string(item, @"label");
    NSString *key = proton_engine_menu_string(item, @"key");
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

static NSMenu *proton_engine_create_custom_menu(NSDictionary *definition,
                                                NSString *app_name,
                                                char *error,
                                                size_t error_len) {
  NSString *label = proton_engine_menu_string(definition, @"label");
  NSArray *items = [definition objectForKey:@"items"];
  if (label == nil || ![items isKindOfClass:[NSArray class]]) {
    proton_engine_set_message(error, error_len,
                              "menu requires label and items");
    return nil;
  }
  NSMenu *menu = [[NSMenu alloc] initWithTitle:label];
  for (id item in items) {
    if (![item isKindOfClass:[NSDictionary class]] ||
        !proton_engine_add_custom_menu_item(
            menu, (NSDictionary *)item, app_name, error, error_len)) {
      return nil;
    }
  }
  return menu;
}

static BOOL proton_engine_menu_definitions_include_label(NSArray *menus,
                                                         NSString *label) {
  for (id item in menus) {
    if ([item isKindOfClass:[NSDictionary class]]) {
      NSString *value = proton_engine_menu_string((NSDictionary *)item, @"label");
      if (value != nil && [value caseInsensitiveCompare:label] == NSOrderedSame) {
        return YES;
      }
    }
  }
  return NO;
}

static int proton_engine_install_menu_definitions(NSArray *menus,
                                                  char *error,
                                                  size_t error_len) {
  NSString *app_name = proton_engine_application_name();
  NSMenu *main_menu = [[NSMenu alloc] initWithTitle:@""];
  NSMenu *window_menu = nil;
  proton_engine_add_top_level_menu(
      main_menu, app_name, proton_engine_create_app_menu(app_name));

  for (id definition in menus) {
    if (![definition isKindOfClass:[NSDictionary class]]) {
      proton_engine_set_message(error, error_len, "menu definition is invalid");
      return 0;
    }
    NSString *label = proton_engine_menu_string((NSDictionary *)definition, @"label");
    NSMenu *menu = proton_engine_create_custom_menu(
        (NSDictionary *)definition, app_name, error, error_len);
    if (menu == nil || label == nil) {
      return 0;
    }
    proton_engine_add_top_level_menu(main_menu, label, menu);
    if ([label caseInsensitiveCompare:@"Window"] == NSOrderedSame) {
      window_menu = menu;
    }
  }

  if (!proton_engine_menu_definitions_include_label(menus, @"Edit")) {
    proton_engine_add_top_level_menu(
        main_menu, @"Edit", proton_engine_create_edit_menu());
  }
  if (!proton_engine_menu_definitions_include_label(menus, @"Window")) {
    window_menu = proton_engine_create_window_menu();
    proton_engine_add_top_level_menu(main_menu, @"Window", window_menu);
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
  (void)proton_engine_install_menu_definitions(@[], error, sizeof(error));
}

int32_t proton_engine_menu_set_json_on_main(
    const char *menu_json,
    char *error,
    size_t error_len) {
  NSData *data =
      [NSData dataWithBytes:menu_json length:strlen(menu_json)];
  NSError *json_error = nil;
  id parsed = [NSJSONSerialization JSONObjectWithData:data
                                             options:0
                                               error:&json_error];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    proton_engine_set_message(error, error_len,
                              "menu config must be a JSON object");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  id menus = [(NSDictionary *)parsed objectForKey:@"menus"];
  if (![menus isKindOfClass:[NSArray class]]) {
    proton_engine_set_message(error, error_len,
                              "menu config requires menus array");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!proton_engine_install_menu_definitions(
          (NSArray *)menus, error, error_len)) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  return PROTON_OK;
}

// App-menu command ids waiting for the host to poll them. Menu actions
// arrive through AppKit while the host only speaks the runtime poll protocol,
// so this queue bridges the two.
#define PROTON_ENGINE_MAX_MENU_COMMANDS 32
#define PROTON_ENGINE_MAX_MENU_COMMAND_BYTES 256
typedef struct {
  char command_id[PROTON_ENGINE_MAX_MENU_COMMAND_BYTES];
  proton_window_id_t focused_window;
} proton_engine_menu_command_t;
static proton_engine_menu_command_t
    g_menu_commands[PROTON_ENGINE_MAX_MENU_COMMANDS];
static uint32_t g_menu_command_head = 0;
static uint32_t g_menu_command_count = 0;
static pthread_mutex_t g_menu_command_lock = PTHREAD_MUTEX_INITIALIZER;

static void proton_engine_enqueue_menu_command(
    NSString *command_id,
    proton_window_id_t focused_window) {
  if (g_menu_runtime == NULL) {
    return;
  }
  const char *utf8 = command_id != nil ? [command_id UTF8String] : "";
  if (utf8 == NULL || strlen(utf8) >= PROTON_ENGINE_MAX_MENU_COMMAND_BYTES) {
    return;
  }
  pthread_mutex_lock(&g_menu_command_lock);
  if (g_menu_command_count < PROTON_ENGINE_MAX_MENU_COMMANDS) {
    uint32_t index =
        (g_menu_command_head + g_menu_command_count) %
        PROTON_ENGINE_MAX_MENU_COMMANDS;
    snprintf(g_menu_commands[index].command_id,
             PROTON_ENGINE_MAX_MENU_COMMAND_BYTES, "%s", utf8);
    g_menu_commands[index].focused_window = focused_window;
    g_menu_command_count++;
  }
  pthread_mutex_unlock(&g_menu_command_lock);
  if (g_menu_signal_callback != NULL) {
    g_menu_signal_callback(PROTON_WAIT_PLATFORM);
  }
}

static void proton_engine_reset_menu_commands(void) {
  pthread_mutex_lock(&g_menu_command_lock);
  g_menu_command_head = 0;
  g_menu_command_count = 0;
  pthread_mutex_unlock(&g_menu_command_lock);
}

void proton_engine_menu_set_runtime(proton_engine_runtime_t *runtime) {
  g_menu_runtime = runtime;
  proton_engine_reset_menu_commands();
}

void proton_engine_menu_clear_runtime(proton_engine_runtime_t *runtime) {
  if (g_menu_runtime == runtime) {
    g_menu_runtime = NULL;
    proton_engine_reset_menu_commands();
  }
}

int32_t proton_engine_take_menu_command(proton_engine_runtime_t *runtime,
                                        char *buffer,
                                        size_t buffer_len,
                                        proton_window_id_t *out_focused_window,
                                        int32_t *out_present) {
  if (out_focused_window == NULL || out_present == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_focused_window = PROTON_INVALID_HANDLE;
  *out_present = 0;
  if (runtime == NULL || runtime != g_menu_runtime) {
    return PROTON_OK;
  }
  pthread_mutex_lock(&g_menu_command_lock);
  if (g_menu_command_count > 0) {
    const proton_engine_menu_command_t *command =
        &g_menu_commands[g_menu_command_head];
    const char *command_id = command->command_id;
    size_t command_len = strlen(command_id);
    if (buffer == NULL || buffer_len <= command_len) {
      pthread_mutex_unlock(&g_menu_command_lock);
      return PROTON_ERR_BUFFER_TOO_SMALL;
    }
    memcpy(buffer, command_id, command_len + 1);
    *out_focused_window = command->focused_window;
    g_menu_command_head =
        (g_menu_command_head + 1) % PROTON_ENGINE_MAX_MENU_COMMANDS;
    g_menu_command_count--;
    *out_present = 1;
  }
  pthread_mutex_unlock(&g_menu_command_lock);
  return PROTON_OK;
}
