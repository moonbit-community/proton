# Traffic light position

Run `moon -C examples run 79_traffic_light_position --target native` after CEF setup.
The macOS Overlay window starts with its native button group at (16, 18) logical
pixels from the top left. Use the controls to change/reset its position and test
resize, visibility, minimize/restore, and fullscreen transitions. The standard
buttons retain their system actions. Windows and Linux accept position changes
as no-ops and return no custom position.

Check that the buttons do not jump to a default position during restore, remain
clickable after moving, and regain the custom position after exiting fullscreen.
The readout reports the configured position, not the buttons' measured bounds.
