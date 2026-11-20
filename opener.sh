#!/bin/sh
# Loops behind the `opener_start` Rex action (see init.lua). Each runs in its
# own pane and restarts its program when it exits, so the pair recovers by
# itself from devbox reboots and dropped connections.
#
#   opener.sh daemon PORT        opener on the laptop, listening on TCP PORT
#   opener.sh forward HOST PORT [OAUTH_PORT]
#                                Rex reverse forward: HOST's PORT -> this PORT.
#                                With OAUTH_PORT (not 0), also a local forward:
#                                this OAUTH_PORT -> HOST's localhost:OAUTH_PORT,
#                                for MCP OAuth callbacks to agents on HOST.
#   opener.sh agent HOST         ssh -A session to HOST that does nothing, so
#                                HOST's ~/.ssh/rc can keep ~/.ssh/agent.sock
#                                on a live forwarded agent for Rex shells.
#                                Rex's own tunnel (ssh -N) forwards no agent.
#
# On the devbox, the opener-bridge systemd user service (dotfiles home.nix)
# serves ~/.opener.sock and relays to 127.0.0.1:PORT.

set -u
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}

case ${1:-} in
daemon)
  port=$2
  cfg="$config_dir/opener/rex-tcp.yaml"
  mkdir -p "$(dirname "$cfg")"
  printf 'network: tcp\naddress: 127.0.0.1:%s\n' "$port" >"$cfg"
  while :; do
    opener --config "$cfg"
    echo "opener exited ($?); restarting in 2s"
    sleep 2
  done
  ;;
forward)
  host=$2 port=$3 oauth_port=${4:-0}
  set -- -R "127.0.0.1:$port:127.0.0.1:$port"
  if [ "$oauth_port" != 0 ]; then
    set -- "$@" -L "127.0.0.1:$oauth_port:localhost:$oauth_port"
  fi
  while :; do
    # Clear forwards left by an earlier run. Rerunning opener_start kills the
    # old loop without closing its blocks, and the host can keep counting
    # their client as connected, so the new forward fails with "address
    # already in use" instead of taking them over. Only this loop uses the
    # host's `opener` session, so closing everything in it is safe.
    rex -S "$host" forward close -s opener --all >/dev/null 2>&1
    rex -S "$host" forward new -s opener "$@"
    code=$?
    if [ "$code" -eq 3 ]; then
      # Exit 3: the host has no `opener` session to hold the forward.
      echo "creating the opener session on $host"
      rex -S "$host" new opener --window opener >/dev/null
    else
      echo "forward to $host exited ($code); retrying in 5s"
    fi
    sleep 5
  done
  ;;
agent)
  host=$2
  while :; do
    # $PPID expands on HOST to this session's sshd, so tail exits with the
    # connection instead of lingering. No forwards here: Rex's tunnel uses
    # ExitOnForwardFailure, and a clash would drop it (see README).
    ssh -A -n -T -o BatchMode=yes -o ServerAliveInterval=15 \
      -o ServerAliveCountMax=3 -o ControlMaster=no -o ControlPath=none \
      "$host" 'exec tail -f /dev/null --pid=$PPID'
    echo "agent session to $host exited ($?); retrying in 5s"
    sleep 5
  done
  ;;
*)
  echo "usage: $0 daemon PORT | forward HOST PORT [OAUTH_PORT] | agent HOST" >&2
  exit 2
  ;;
esac
