#!/bin/sh
set -eu

mkdir -p ./data/mongodb
podman-compose up -d
