#include "proton_linux_menu.h"

#include <stdio.h>
#include <string.h>

typedef struct {
  char command[64];
  char role[64];
} activation_state_t;

static void command_activated(const char *command_id, void *user_data) {
  activation_state_t *state = (activation_state_t *)user_data;
  snprintf(state->command, sizeof(state->command), "%s", command_id);
}

static void role_activated(const char *role, void *user_data) {
  activation_state_t *state = (activation_state_t *)user_data;
  snprintf(state->role, sizeof(state->role), "%s", role);
}

static int expect_valid(const char *name, const char *json) {
  char error[256] = {0};
  proton_linux_menu_bar_t *menu =
      proton_linux_menu_bar_parse(json, error, sizeof(error));
  if (menu == NULL) {
    fprintf(stderr, "%s should be valid: %s\n", name, error);
    return 1;
  }
  proton_linux_menu_bar_destroy(menu);
  return 0;
}

static int expect_invalid(const char *name,
                          const char *json,
                          const char *message) {
  char error[256] = {0};
  proton_linux_menu_bar_t *menu =
      proton_linux_menu_bar_parse(json, error, sizeof(error));
  if (menu != NULL) {
    proton_linux_menu_bar_destroy(menu);
    fprintf(stderr, "%s should be invalid\n", name);
    return 1;
  }
  if (strstr(error, message) == NULL) {
    fprintf(stderr, "%s expected error containing %s, got %s\n", name,
            message, error);
    return 1;
  }
  return 0;
}

static int expect_widget_accelerator(void) {
  char error[256] = {0};
  proton_linux_menu_bar_t *definition = proton_linux_menu_bar_parse(
      "{\"abi_version\":1,\"menus\":[{\"label\":\"Smoke\","
      "\"items\":[{\"kind\":\"command\",\"id\":\"smoke.command\","
      "\"label\":\"Smoke Command\",\"key\":\"s\"},"
      "{\"kind\":\"role\",\"role\":\"close\",\"label\":\"Close\","
      "\"key\":\"w\"},{\"kind\":\"role\",\"role\":\"hide_others\","
      "\"label\":\"Hide Others\",\"key\":\"h\"}]}]}",
      error, sizeof(error));
  if (definition == NULL) {
    fprintf(stderr, "widget menu should parse: %s\n", error);
    return 1;
  }

  activation_state_t state = {0};
  GtkAccelGroup *accelerators = gtk_accel_group_new();
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget *menu = proton_linux_menu_bar_create_widget(
      definition, accelerators, command_activated, role_activated, &state,
      error, sizeof(error));
  if (menu == NULL) {
    fprintf(stderr, "widget menu should build: %s\n", error);
    gtk_widget_destroy(window);
    g_object_unref(accelerators);
    proton_linux_menu_bar_destroy(definition);
    return 1;
  }
  gtk_window_add_accel_group(GTK_WINDOW(window), accelerators);
  gtk_container_add(GTK_CONTAINER(window), menu);
  gtk_widget_show_all(window);
  while (gtk_events_pending()) {
    gtk_main_iteration();
  }
  const gboolean command_was_activated = gtk_accel_groups_activate(
      G_OBJECT(window), GDK_KEY_s, GDK_CONTROL_MASK);
  int failed = !command_was_activated ||
               strcmp(state.command, "smoke.command") != 0;
  if (!command_was_activated ||
      strcmp(state.command, "smoke.command") != 0) {
    fprintf(stderr, "Ctrl+S should activate smoke.command, got %s\n",
            state.command);
  }
  const gboolean role_was_activated = gtk_accel_groups_activate(
      G_OBJECT(window), GDK_KEY_w, GDK_CONTROL_MASK);
  if (!role_was_activated || strcmp(state.role, "close") != 0) {
    fprintf(stderr, "Ctrl+W should activate close, got %s\n", state.role);
    failed = 1;
  }
  state.role[0] = '\0';
  const gboolean hide_others_was_activated = gtk_accel_groups_activate(
      G_OBJECT(window), GDK_KEY_h, GDK_CONTROL_MASK | GDK_MOD1_MASK);
  if (!hide_others_was_activated || strcmp(state.role, "hide_others") != 0) {
    fprintf(stderr, "Ctrl+Alt+H should activate hide_others, got %s\n",
            state.role);
    failed = 1;
  }
  gtk_widget_destroy(window);
  g_object_unref(accelerators);
  proton_linux_menu_bar_destroy(definition);
  return failed;
}

int main(int argc, char **argv) {
  int failures = 0;
  failures += expect_valid(
      "commands separators and roles",
      "{\"abi_version\":1,\"menus\":[{\"label\":\"Developer\","
      "\"items\":[{\"kind\":\"command\",\"id\":\"devtools\","
      "\"label\":\"Open DevTools\",\"key\":\"d\"},"
      "{\"kind\":\"separator\"},{\"kind\":\"role\","
      "\"role\":\"close\",\"label\":\"Close\",\"key\":\"w\"}]}]}");
  failures += expect_valid("empty custom menu set",
                           "{\"abi_version\":1,\"menus\":[]}");
  failures += expect_valid(
      "empty labels match macOS menu semantics",
      "{\"abi_version\":1,\"menus\":[{\"label\":\"\","
      "\"items\":[{\"kind\":\"command\",\"id\":\"\","
      "\"label\":\"\"}]}]}");
  failures += expect_invalid(
      "missing command id",
      "{\"abi_version\":1,\"menus\":[{\"label\":\"File\","
      "\"items\":[{\"kind\":\"command\",\"label\":\"Open\"}]}]}",
      "requires label and id");
  failures += expect_invalid(
      "unsupported role",
      "{\"abi_version\":1,\"menus\":[{\"label\":\"File\","
      "\"items\":[{\"kind\":\"role\",\"role\":\"explode\"}]}]}",
      "role is unsupported");
  failures += expect_invalid(
      "non-array items",
      "{\"abi_version\":1,\"menus\":[{\"label\":\"File\","
      "\"items\":{}}]}",
      "requires label and items");
  if (gtk_init_check(&argc, &argv)) {
    failures += expect_widget_accelerator();
  } else {
    fprintf(stderr, "GTK display unavailable; skipping widget accelerator test\n");
  }
  return failures == 0 ? 0 : 1;
}
