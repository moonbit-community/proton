# Troubleshooting

## Chrome refuses the connection

Verify that Chrome was started with `--remote-debugging-port` and that the port
matches your `MBT_CDP_TARGET` or parsed target string.

## `/json/list` has no page target

Open a normal tab in the debugging browser, or pass a direct page WebSocket URL.

## A typed command is hard to construct

Start with `send_schema_command` and a JSON params object, then move to the
generated typed builder once the field names and optional values are clear.

## A command works in one browser but not another

Fetch `/json/protocol` with `discover_protocol` and use
`protocol_schema_diff` or `send_remote_schema_command` to check whether the
remote browser advertises the command.
