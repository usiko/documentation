#!/bin/sh
# Builds /etc/nginx/.htpasswd from BASIC_AUTH_USER / BASIC_AUTH_PASSWORD env
# vars (set via .env, never committed). Runs on every container start.
# Leaves an empty file (no valid user) when unset, so every request outside
# the ALLOWED_CIDR range gets a 401 until real credentials are provided.
set -eu

HTPASSWD_FILE=/etc/nginx/.htpasswd

if [ -n "${BASIC_AUTH_USER:-}" ] && [ -n "${BASIC_AUTH_PASSWORD:-}" ]; then
  SALT="$(openssl rand -hex 4)"
  HASH="$(openssl passwd -apr1 -salt "$SALT" "$BASIC_AUTH_PASSWORD")"
  echo "${BASIC_AUTH_USER}:${HASH}" > "$HTPASSWD_FILE"
else
  : > "$HTPASSWD_FILE"
fi
