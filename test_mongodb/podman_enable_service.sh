#!/bin/sh
set -eu

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [service-name]" >&2
  exit 1
fi

service_name="${1:-podman-compose-mongodb}"
case "$service_name" in
  *.service) ;;
  *) service_name="${service_name}.service" ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
compose_file="${script_dir}/podman-compose.yml"
service_dir="${HOME}/.config/systemd/user"
service_file="${service_dir}/${service_name}"
podman_compose_path=$(command -v podman-compose)

if [ ! -f "$compose_file" ]; then
  echo "podman-compose.yml not found: $compose_file" >&2
  exit 1
fi

mkdir -p "$service_dir"

cat > "$service_file" <<EOF_SERVICE
[Unit]
Description=Podman Compose ${service_name%.service}
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${script_dir}
ExecStartPre=/usr/bin/mkdir -p ${script_dir}/data/mongodb
ExecStart=${podman_compose_path} --in-pod false up -d
ExecStop=${podman_compose_path} --in-pod false down
TimeoutStartSec=0

[Install]
WantedBy=default.target
EOF_SERVICE

systemctl --user daemon-reload
systemctl --user enable --now "$service_name"

systemctl --user status "$service_name" --no-pager
