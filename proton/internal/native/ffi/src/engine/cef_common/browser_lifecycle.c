#include "browser_lifecycle.h"

#include "proton_native.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct proton_browser_lifecycle {
  proton_browser_registry_t *registry;
  proton_browser_role_t role;
  proton_browser_lifecycle_state_t state;
  void *owner;
  cef_browser_t *browser;
  cef_client_t *client;
  int browser_id;
  int force_close;
  proton_browser_lifecycle_t *devtools_parent;
  proton_browser_lifecycle_t *devtools;
  proton_browser_lifecycle_t *next;
};

struct proton_browser_registry {
  proton_browser_lifecycle_t *browsers;
  proton_browser_client_factory_fn client_factory;
  void *context;
  int shutting_down;
};

static void proton_browser_lifecycle_set_message(char *error, size_t error_len,
                                                 const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
  }
}

static void proton_browser_lifecycle_release_browser(
    proton_browser_lifecycle_t *lifecycle) {
  if (lifecycle != NULL && lifecycle->browser != NULL) {
    lifecycle->browser->base.release(
        (cef_base_ref_counted_t *)lifecycle->browser);
    lifecycle->browser = NULL;
    lifecycle->browser_id = 0;
  }
}

static void proton_browser_lifecycle_close_bound_browser(
    proton_browser_lifecycle_t *lifecycle) {
  if (lifecycle == NULL || lifecycle->browser == NULL) {
    return;
  }
  cef_browser_host_t *host = lifecycle->browser->get_host(lifecycle->browser);
  if (host != NULL) {
    host->close_browser(host, lifecycle->force_close);
    host->base.release((cef_base_ref_counted_t *)host);
  }
}

proton_browser_registry_t *
proton_browser_registry_create(proton_browser_client_factory_fn client_factory,
                               void *context) {
  proton_browser_registry_t *registry =
      (proton_browser_registry_t *)calloc(1, sizeof(*registry));
  if (registry != NULL) {
    registry->client_factory = client_factory;
    registry->context = context;
  }
  return registry;
}

void proton_browser_registry_begin_shutdown(
    proton_browser_registry_t *registry) {
  if (registry == NULL) {
    return;
  }
  registry->shutting_down = 1;
  for (proton_browser_lifecycle_t *browser = registry->browsers;
       browser != NULL; browser = browser->next) {
    if (browser->role == PROTON_BROWSER_ROLE_DEVTOOLS) {
      proton_browser_lifecycle_request_close(browser, 1);
    }
  }
  for (proton_browser_lifecycle_t *browser = registry->browsers;
       browser != NULL; browser = browser->next) {
    if (browser->role != PROTON_BROWSER_ROLE_DEVTOOLS) {
      proton_browser_lifecycle_request_close(browser, 1);
    }
  }
}

int proton_browser_registry_shutdown_ready(
    const proton_browser_registry_t *registry) {
  if (registry == NULL) {
    return 1;
  }
  for (const proton_browser_lifecycle_t *browser = registry->browsers;
       browser != NULL; browser = browser->next) {
    if (browser->state != PROTON_BROWSER_CLOSED &&
        browser->state != PROTON_BROWSER_CREATION_FAILED) {
      return 0;
    }
  }
  return 1;
}

void proton_browser_registry_destroy(proton_browser_registry_t *registry) {
  if (registry == NULL) {
    return;
  }
  proton_browser_lifecycle_t *browser = registry->browsers;
  while (browser != NULL) {
    proton_browser_lifecycle_t *next = browser->next;
    proton_browser_lifecycle_release_browser(browser);
    if (browser->client != NULL) {
      browser->client->base.release((cef_base_ref_counted_t *)browser->client);
      browser->client = NULL;
    }
    free(browser);
    browser = next;
  }
  free(registry);
}

proton_browser_lifecycle_t *
proton_browser_lifecycle_create(proton_browser_registry_t *registry,
                                proton_browser_role_t role, void *owner,
                                proton_browser_lifecycle_t *devtools_parent) {
  if (registry == NULL || registry->shutting_down) {
    return NULL;
  }
  proton_browser_lifecycle_t *lifecycle =
      (proton_browser_lifecycle_t *)calloc(1, sizeof(*lifecycle));
  if (lifecycle == NULL) {
    return NULL;
  }
  lifecycle->registry = registry;
  lifecycle->role = role;
  lifecycle->state = PROTON_BROWSER_CREATING;
  lifecycle->owner = owner;
  lifecycle->devtools_parent = devtools_parent;
  lifecycle->next = registry->browsers;
  registry->browsers = lifecycle;
  if (devtools_parent != NULL && role == PROTON_BROWSER_ROLE_DEVTOOLS) {
    devtools_parent->devtools = lifecycle;
  }
  return lifecycle;
}

void proton_browser_lifecycle_set_client(proton_browser_lifecycle_t *lifecycle,
                                         cef_client_t *client) {
  if (lifecycle != NULL && lifecycle->client == NULL) {
    lifecycle->client = client;
  }
}

void proton_browser_lifecycle_creation_failed(
    proton_browser_lifecycle_t *lifecycle) {
  if (lifecycle == NULL || lifecycle->state == PROTON_BROWSER_CLOSED) {
    return;
  }
  lifecycle->state = PROTON_BROWSER_CREATION_FAILED;
  if (lifecycle->devtools_parent != NULL &&
      lifecycle->devtools_parent->devtools == lifecycle) {
    lifecycle->devtools_parent->devtools = NULL;
  }
}

void proton_browser_lifecycle_adopt_created(
    proton_browser_lifecycle_t *lifecycle, cef_browser_t *browser) {
  if (lifecycle == NULL || browser == NULL) {
    return;
  }
  if (lifecycle->browser == browser) {
    browser->base.release((cef_base_ref_counted_t *)browser);
    return;
  }
  if (lifecycle->browser != NULL) {
    browser->base.release((cef_base_ref_counted_t *)browser);
    return;
  }
  lifecycle->browser = browser;
  lifecycle->browser_id = browser->get_identifier(browser);
  if (lifecycle->state == PROTON_BROWSER_CREATING) {
    lifecycle->state = PROTON_BROWSER_LIVE;
  } else if (lifecycle->state == PROTON_BROWSER_CLOSING) {
    proton_browser_lifecycle_close_bound_browser(lifecycle);
  }
}

void proton_browser_lifecycle_on_after_created(
    proton_browser_lifecycle_t *lifecycle, cef_browser_t *browser) {
  if (lifecycle == NULL || browser == NULL || lifecycle->browser != NULL) {
    return;
  }
  browser->base.add_ref((cef_base_ref_counted_t *)browser);
  lifecycle->browser = browser;
  lifecycle->browser_id = browser->get_identifier(browser);
  if (lifecycle->state == PROTON_BROWSER_CREATING) {
    lifecycle->state = PROTON_BROWSER_LIVE;
  } else if (lifecycle->state == PROTON_BROWSER_CLOSING) {
    proton_browser_lifecycle_close_bound_browser(lifecycle);
  }
}

void proton_browser_lifecycle_request_close(
    proton_browser_lifecycle_t *lifecycle, int force_close) {
  if (lifecycle == NULL || lifecycle->state == PROTON_BROWSER_CLOSED ||
      lifecycle->state == PROTON_BROWSER_CREATION_FAILED) {
    return;
  }
  if (lifecycle->devtools != NULL) {
    proton_browser_lifecycle_request_close(lifecycle->devtools, force_close);
  }
  if (lifecycle->state == PROTON_BROWSER_CLOSING) {
    if (force_close && !lifecycle->force_close) {
      lifecycle->force_close = 1;
      proton_browser_lifecycle_close_bound_browser(lifecycle);
    }
    return;
  }
  lifecycle->state = PROTON_BROWSER_CLOSING;
  if (force_close) {
    lifecycle->force_close = 1;
  }
  proton_browser_lifecycle_close_bound_browser(lifecycle);
}

void proton_browser_lifecycle_note_close_requested(
    proton_browser_lifecycle_t *lifecycle, int force_close) {
  if (lifecycle == NULL || lifecycle->state == PROTON_BROWSER_CLOSED ||
      lifecycle->state == PROTON_BROWSER_CREATION_FAILED) {
    return;
  }
  if (lifecycle->devtools != NULL) {
    proton_browser_lifecycle_request_close(lifecycle->devtools, force_close);
  }
  if (lifecycle->state == PROTON_BROWSER_CLOSING) {
    if (force_close) {
      lifecycle->force_close = 1;
    }
    return;
  }
  lifecycle->state = PROTON_BROWSER_CLOSING;
  if (force_close) {
    lifecycle->force_close = 1;
  }
}

void proton_browser_lifecycle_on_before_close(
    proton_browser_lifecycle_t *lifecycle, cef_browser_t *browser) {
  if (lifecycle == NULL || lifecycle->state == PROTON_BROWSER_CLOSED) {
    return;
  }
  if (browser != NULL && lifecycle->browser != NULL &&
      browser->get_identifier(browser) != lifecycle->browser_id) {
    return;
  }
  if (lifecycle->devtools != NULL) {
    proton_browser_lifecycle_request_close(lifecycle->devtools, 1);
  }
  proton_browser_lifecycle_release_browser(lifecycle);
  lifecycle->state = PROTON_BROWSER_CLOSED;
  if (lifecycle->devtools_parent != NULL &&
      lifecycle->devtools_parent->devtools == lifecycle) {
    lifecycle->devtools_parent->devtools = NULL;
  }
}

proton_browser_role_t
proton_browser_lifecycle_role(const proton_browser_lifecycle_t *lifecycle) {
  return lifecycle != NULL ? lifecycle->role : PROTON_BROWSER_ROLE_MAIN;
}

proton_browser_lifecycle_state_t
proton_browser_lifecycle_state(const proton_browser_lifecycle_t *lifecycle) {
  return lifecycle != NULL ? lifecycle->state : PROTON_BROWSER_CLOSED;
}

void *
proton_browser_lifecycle_owner(const proton_browser_lifecycle_t *lifecycle) {
  return lifecycle != NULL ? lifecycle->owner : NULL;
}

void *
proton_browser_lifecycle_context(const proton_browser_lifecycle_t *lifecycle) {
  return lifecycle != NULL && lifecycle->registry != NULL
             ? lifecycle->registry->context
             : NULL;
}

void proton_browser_lifecycle_clear_owner(
    proton_browser_lifecycle_t *lifecycle) {
  if (lifecycle != NULL) {
    lifecycle->owner = NULL;
  }
}

cef_browser_t *
proton_browser_lifecycle_browser(const proton_browser_lifecycle_t *lifecycle) {
  return lifecycle != NULL ? lifecycle->browser : NULL;
}

cef_client_t *
proton_browser_lifecycle_client(const proton_browser_lifecycle_t *lifecycle) {
  return lifecycle != NULL ? lifecycle->client : NULL;
}

int proton_browser_lifecycle_browser_id(
    const proton_browser_lifecycle_t *lifecycle) {
  return lifecycle != NULL ? lifecycle->browser_id : 0;
}

int32_t
proton_browser_lifecycle_devtools_command(proton_browser_lifecycle_t *lifecycle,
                                          const char *command, char *error,
                                          size_t error_len) {
  if (lifecycle == NULL || lifecycle->browser == NULL || command == NULL) {
    proton_browser_lifecycle_set_message(error, error_len,
                                         "browser lifecycle is unavailable");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_browser_host_t *host = lifecycle->browser->get_host(lifecycle->browser);
  if (host == NULL) {
    proton_browser_lifecycle_set_message(error, error_len,
                                         "browser host is unavailable");
    return PROTON_ERR_ENGINE;
  }
  proton_browser_lifecycle_t *devtools = lifecycle->devtools;
  int devtools_active = devtools != NULL &&
                        devtools->state != PROTON_BROWSER_CLOSED &&
                        devtools->state != PROTON_BROWSER_CREATION_FAILED;
  int close = strcmp(command, "close_devtools") == 0 ||
              (strcmp(command, "toggle_devtools") == 0 && devtools_active);
  if (close) {
    if (devtools_active && devtools->state != PROTON_BROWSER_CLOSING) {
      proton_browser_lifecycle_note_close_requested(devtools, 1);
      host->close_dev_tools(host);
    }
    host->base.release((cef_base_ref_counted_t *)host);
    return PROTON_OK;
  }

  if (devtools_active) {
    if (devtools->state == PROTON_BROWSER_CLOSING) {
      host->base.release((cef_base_ref_counted_t *)host);
      proton_browser_lifecycle_set_message(error, error_len,
                                           "DevTools are closing");
      return PROTON_ERR_BUSY;
    }
    host->base.release((cef_base_ref_counted_t *)host);
    return PROTON_OK;
  }

  {
    proton_browser_registry_t *registry = lifecycle->registry;
    devtools = proton_browser_lifecycle_create(
        registry, PROTON_BROWSER_ROLE_DEVTOOLS, NULL, lifecycle);
    if (devtools == NULL || registry->client_factory == NULL) {
      proton_browser_lifecycle_creation_failed(devtools);
      host->base.release((cef_base_ref_counted_t *)host);
      proton_browser_lifecycle_set_message(
          error, error_len, "failed to allocate DevTools lifecycle");
      return PROTON_ERR_ENGINE;
    }
    cef_client_t *client =
        registry->client_factory(registry->context, devtools);
    if (client == NULL) {
      proton_browser_lifecycle_creation_failed(devtools);
      host->base.release((cef_base_ref_counted_t *)host);
      proton_browser_lifecycle_set_message(error, error_len,
                                           "failed to create DevTools client");
      return PROTON_ERR_ENGINE;
    }
    proton_browser_lifecycle_set_client(devtools, client);
  }

  cef_window_info_t window_info = {0};
  cef_browser_settings_t settings = {0};
  window_info.size = sizeof(window_info);
  settings.size = sizeof(settings);
  host->show_dev_tools(host, &window_info, devtools->client, &settings, NULL);
  host->base.release((cef_base_ref_counted_t *)host);
  return PROTON_OK;
}
