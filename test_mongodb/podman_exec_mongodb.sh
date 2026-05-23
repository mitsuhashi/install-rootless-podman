#!/bin/sh
set -eu

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

podman-compose exec mongodb mongosh -u "${MONGO_INITDB_ROOT_USERNAME:-root}" -p "${MONGO_INITDB_ROOT_PASSWORD:-example}" --eval 'db.stats()'
