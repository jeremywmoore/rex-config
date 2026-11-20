-- Rex configuration. Reload with `rex config reload`.

-- Opens browser links from a devbox on this Mac. Creates (or recreates) the
-- local `opener` session with two panes, each a retry loop from opener.sh:
--   opener   opener listening on TCP 127.0.0.1:PORT
--   forward  `rex -S HOST forward new -R PORT:PORT` back to that opener, plus
--            `-L OAUTH_PORT:localhost:OAUTH_PORT` so MCP OAuth redirects in
--            this Mac's browser reach agents on HOST (oauth_port=0 skips it)
--   agent    an idle `ssh -A HOST` so Rex shells on HOST get a forwarded SSH
--            agent through ~/.ssh/agent.sock (Rex's tunnel forwards none)
-- The devbox side is the opener-bridge systemd user service in the dotfiles.
-- Run it with `rex do opener_start` or "Start Opener Forward" in the palette.
rex.action{
  name        = "opener_start",
  title       = "Start Opener Forward",
  description = "Restart the opener daemon and the Rex reverse forward that lets a devbox open links in this Mac's browser.",
  keywords    = "opener browser devbox forward xdg-open",
  args        = { host = "string?", port = "integer?", oauth_port = "integer?" },
  run         = function(ctx, args)
    local host = args.host or "devbox-j.moore"
    local port = tostring(args.port or 62222)
    local oauth_port = tostring(args.oauth_port or 61337)
    local script = os.getenv("HOME") .. "/.config/rex/opener.sh"
    local shell = "com.superlogical.terminal.shell"

    -- Restart rather than reuse, so a stale pane never hides a dead loop.
    local list, err = rex.call("session.list")
    if err ~= nil then error(err, 0) end
    for _, s in ipairs(list.sessions or {}) do
      if s.label == "opener" then
        -- The server only takes session calls from an attached caller.
        local _, aerr = rex.call("session.attach", { session_id = s.session_id })
        if aerr ~= nil then error(aerr, 0) end
        local _, derr = rex.call("session.destroy", { session_id = s.session_id })
        if derr ~= nil then error(derr, 0) end
      end
    end

    local function pane(label, command)
      return { block = {
        flavor  = shell,
        label   = label,
        options = { command = command, exit = { on_completion = false } },
      } }
    end

    local created, cerr = rex.call("session.create", {
      label = "opener",
      initial_windows = { {
        window_label = "opener",
        layout = { split = {
          direction = "vertical",
          ratio     = 0.5,
          before    = pane("opener", { "sh", script, "daemon", port }),
          after     = { split = {
            direction = "horizontal",
            ratio     = 0.5,
            before    = pane("forward", { "sh", script, "forward", host, port, oauth_port }),
            after     = pane("agent", { "sh", script, "agent", host }),
          } },
        } },
      } },
    })
    if cerr ~= nil then error(cerr, 0) end
    return { session_id = created.session_id, host = host, port = port, oauth_port = oauth_port }
  end,
}
