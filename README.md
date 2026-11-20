# rex-config

My [Rex](https://www.superlogical.com/rex/docs) customizations. This checkout
lives at `~/.config/rex`, where the Rex server on my Mac reads `init.lua`.

After editing, check and reload:

```sh
rex config check
rex config reload
```

## `opener_start` ("Start Opener Forward")

Lets a devbox open links in this Mac's browser, and lets MCP OAuth redirects
in this Mac's browser reach agents on the devbox. Run it with
`rex do opener_start`, or from the command palette. Run it again after the Mac
reboots, since restored panes come back as plain shells.

It (re)creates the local `opener` session with two panes, each a retry loop
from `opener.sh`:

- `opener`: [opener](https://github.com/superbrothers/opener) listening on
  TCP `127.0.0.1:62222`. The Homebrew launchd opener on `~/.opener.sock` is
  separate and untouched.
- `forward`: one `rex -S HOST forward new` process carrying
  - `-R 127.0.0.1:62222:127.0.0.1:62222`: devbox port to the opener above
  - `-L 127.0.0.1:61337:localhost:61337`: MCP OAuth callbacks to the devbox

  If the devbox has no `opener` session to hold the forwards (exit code 3), the
  loop creates one.
- `agent`: an idle `ssh -A HOST` session, so git in Rex shells on the devbox
  can use this Mac's SSH keys. Rex's own tunnel is `ssh -N`, which opens no
  session, so sshd never forwards an agent for it. The devbox's `~/.ssh/rc`
  points `~/.ssh/agent.sock` at a live forwarded agent, and its `.zshrc` sets
  `SSH_AUTH_SOCK` to that path in shells not started by sshd. The session adds
  no forwards, so it can't trip Rex's `ExitOnForwardFailure`.

Arguments, all optional: `host` (default `devbox-j.moore`), `port` (default
`62222`), `oauth_port` (default `61337`, `0` turns it off).

```
devbox xdg-open -> ~/.opener.sock -> opener-bridge (systemd, socat) -> 127.0.0.1:62222
  == rex forward -R ==> Mac 127.0.0.1:62222 -> opener -> browser
```

The devbox side, the `xdg-open` shim and the `opener-bridge` user service,
lives in [dotfiles](https://github.com/jeremywmoore/dotfiles) `home.nix`.

### Why not `ssh -R` / `LocalForward`?

Rex's SSH tunnel uses `ExitOnForwardFailure=yes` and inherits forwards from
`~/.ssh/config`. A `RemoteForward` of the opener socket or a `LocalForward` of
the OAuth port fails whenever another SSH connection already holds it, and Rex
then drops the whole connection. Carrying both over Rex's own forwards avoids
that, so `~/.ssh/config` for the devbox has no forwards.

### Limits

- The loops restart a forward that exits, not one that hangs. If links stop
  opening, rerun `rex do opener_start`.
- Any local process on either machine can send a URL to the TCP port.
