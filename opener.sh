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
*)
  echo "usage: $0 daemon PORT | forward HOST PORT" >&2
  exit 2
  ;;
esac
