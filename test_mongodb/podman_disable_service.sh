#!/bin/sh
set -eu

remove_data=0
service_name="podman-compose-mongodb"
container_name="test_mongodb_rootless"

usage() {
  echo "Usage: $0 [--remove-data] [service-name]" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --remove-data)
      remove_data=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage
      exit 1
      ;;
    *)
      service_name="$1"
      ;;
  esac
  shift
done

case "$service_name" in
  *.service) ;;
  *) service_name="${service_name}.service" ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
service_file="${HOME}/.config/systemd/user/${service_name}"
service_link="${HOME}/.config/systemd/user/default.target.wants/${service_name}"

if [ -f "$service_file" ] || [ -L "$service_link" ]; then
  systemctl --user disable --now "$service_name" || true
else
  echo "Service is already disabled: ${service_name}"
fi

if [ -f "${script_dir}/podman-compose.yml" ]; then
  cd "$script_dir"
  if podman container exists "$container_name"; then
    podman-compose --in-pod false down
  else
    echo "Container already removed: ${container_name}"
  fi
fi

if [ -f "$service_file" ]; then
  rm -f "$service_file"
else
  echo "Service file already removed: ${service_file}"
fi

systemctl --user daemon-reload

if [ "$remove_data" -eq 1 ]; then
  rm -rf "${script_dir}/data/mongodb"
fi

if systemctl --user list-unit-files "$service_name" --no-legend | grep -q .; then
  systemctl --user status "$service_name" --no-pager || true
else
  echo "Service is not registered: ${service_name}"
fi

podman ps -a
