#if defined(__APPLE__)
#include "libcef_dll/wrapper/libcef_dll_dylib.cc"
#include "libcef_dll/wrapper/cef_scoped_library_loader_mac.mm"
#endif

extern "C" void proton_cef_loader_link_anchor(void) {}
