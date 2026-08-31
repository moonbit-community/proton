#ifndef PROTON_ENGINE_CEF_COMMON_BROWSER_LIFECYCLE_H
#define PROTON_ENGINE_CEF_COMMON_BROWSER_LIFECYCLE_H

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"

#include <stddef.h>
#include <stdint.h>

typedef enum {
  PROTON_BROWSER_ROLE_MAIN = 0,
  PROTON_BROWSER_ROLE_VIEW = 1,
  PROTON_BROWSER_ROLE_DEVTOOLS = 2,
} proton_browser_role_t;

typedef enum {
  PROTON_BROWSER_CREATING = 0,
  PROTON_BROWSER_LIVE = 1,
  PROTON_BROWSER_CLOSING = 2,
  PROTON_BROWSER_CLOSED = 3,
  PROTON_BROWSER_CREATION_FAILED = 4,
} proton_browser_lifecycle_state_t;

typedef struct proton_browser_lifecycle proton_browser_lifecycle_t;
typedef struct proton_browser_registry proton_browser_registry_t;

typedef cef_client_t *(*proton_browser_client_factory_fn)(
    void *context, proton_browser_lifecycle_t *lifecycle);

proton_browser_registry_t *
proton_browser_registry_create(proton_browser_client_factory_fn client_factory,
                               void *context);
void proton_browser_registry_begin_shutdown(
    proton_browser_registry_t *registry);
int proton_browser_registry_shutdown_ready(
    const proton_browser_registry_t *registry);
void proton_browser_registry_destroy(proton_browser_registry_t *registry);

proton_browser_lifecycle_t *
proton_browser_lifecycle_create(proton_browser_registry_t *registry,
                                proton_browser_role_t role, void *owner,
                                proton_browser_lifecycle_t *devtools_parent);
void proton_browser_lifecycle_set_client(proton_browser_lifecycle_t *lifecycle,
                                         cef_client_t *client);
void proton_browser_lifecycle_creation_failed(
    proton_browser_lifecycle_t *lifecycle);
void proton_browser_lifecycle_adopt_created(
    proton_browser_lifecycle_t *lifecycle, cef_browser_t *browser);
void proton_browser_lifecycle_on_after_created(
    proton_browser_lifecycle_t *lifecycle, cef_browser_t *browser);
void proton_browser_lifecycle_request_close(
    proton_browser_lifecycle_t *lifecycle, int force_close);
void proton_browser_lifecycle_note_close_requested(
    proton_browser_lifecycle_t *lifecycle, int force_close);
void proton_browser_lifecycle_on_before_close(
    proton_browser_lifecycle_t *lifecycle, cef_browser_t *browser);

proton_browser_role_t
proton_browser_lifecycle_role(const proton_browser_lifecycle_t *lifecycle);
proton_browser_lifecycle_state_t
proton_browser_lifecycle_state(const proton_browser_lifecycle_t *lifecycle);
void *
proton_browser_lifecycle_owner(const proton_browser_lifecycle_t *lifecycle);
void *
proton_browser_lifecycle_context(const proton_browser_lifecycle_t *lifecycle);
void proton_browser_lifecycle_clear_owner(
    proton_browser_lifecycle_t *lifecycle);
cef_browser_t *
proton_browser_lifecycle_browser(const proton_browser_lifecycle_t *lifecycle);
int proton_browser_lifecycle_browser_id(
    const proton_browser_lifecycle_t *lifecycle);

int32_t
proton_browser_lifecycle_devtools_command(proton_browser_lifecycle_t *lifecycle,
                                          const char *command, char *error,
                                          size_t error_len);

#endif
