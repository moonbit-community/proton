#if defined(__APPLE__)
#include "libcef_dll/wrapper/libcef_dll_dylib.cc"
#include "libcef_dll/wrapper/cef_scoped_library_loader_mac.mm"
#endif

#if defined(__cplusplus)
extern "C"
#endif
void proton_cef_loader_link_anchor(void) {}
