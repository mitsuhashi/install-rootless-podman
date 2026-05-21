#!/bin/sh
set -eu

mkdir -p ./data/mongodb
podman-compose --in-pod false up -d
