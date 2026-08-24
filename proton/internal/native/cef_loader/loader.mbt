///|
extern "C" fn proton_cef_loader_link_anchor() -> Unit = "proton_cef_loader_link_anchor"

///|
pub fn ensure_linked() -> Unit {
  proton_cef_loader_link_anchor()
}
