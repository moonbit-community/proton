///|
extern "C" fn proton_mac_engine_link_anchor() -> Unit = "proton_mac_engine_link_anchor"

///|
pub fn ensure_linked() -> Unit {
  proton_mac_engine_link_anchor()
}
