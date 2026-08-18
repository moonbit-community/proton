#include "../src/engine/cef_common/cookie_state_lifetime.h"

#include <assert.h>

static void test_cleanup_without_visitor_releases_state(void) {
  proton_cookie_state_ref_count_t refs;
  proton_cookie_state_detached_t detached;

  proton_cookie_state_lifetime_init(&refs, &detached);
  proton_cookie_state_lifetime_detach(&detached);

  assert(proton_cookie_state_lifetime_is_detached(&detached));
  assert(proton_cookie_state_lifetime_release(&refs));
}

static void test_cleanup_waits_for_visitor_release(void) {
  proton_cookie_state_ref_count_t refs;
  proton_cookie_state_detached_t detached;

  proton_cookie_state_lifetime_init(&refs, &detached);
  proton_cookie_state_lifetime_retain(&refs);
  proton_cookie_state_lifetime_detach(&detached);

  assert(proton_cookie_state_lifetime_is_detached(&detached));
  assert(!proton_cookie_state_lifetime_release(&refs));
  assert(proton_cookie_state_lifetime_release(&refs));
}

static void test_completed_visitor_releases_before_cleanup(void) {
  proton_cookie_state_ref_count_t refs;
  proton_cookie_state_detached_t detached;

  proton_cookie_state_lifetime_init(&refs, &detached);
  proton_cookie_state_lifetime_retain(&refs);

  assert(!proton_cookie_state_lifetime_release(&refs));
  assert(!proton_cookie_state_lifetime_is_detached(&detached));
  proton_cookie_state_lifetime_detach(&detached);
  assert(proton_cookie_state_lifetime_release(&refs));
}

int main(void) {
  test_cleanup_without_visitor_releases_state();
  test_cleanup_waits_for_visitor_release();
  test_completed_visitor_releases_before_cleanup();
  return 0;
}
