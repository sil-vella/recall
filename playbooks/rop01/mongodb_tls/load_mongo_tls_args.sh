#!/usr/bin/env bash
# Populate MONGO_TLS_ARGS for mongodump/mongorestore (--ssl) or mongosh (--tls).
# shellcheck shell=bash

load_mongo_tls_dump_args() {
  MONGO_TLS_ARGS=()
  local arg
  while IFS= read -r arg; do
    [[ -n "${arg}" ]] && MONGO_TLS_ARGS+=("${arg}")
  done < <(mongo_tls_dump_args)
}

load_mongo_tls_shell_args() {
  MONGO_TLS_ARGS=()
  local arg
  while IFS= read -r arg; do
    [[ -n "${arg}" ]] && MONGO_TLS_ARGS+=("${arg}")
  done < <(mongo_tls_shell_args)
}

# Default loader — mongodump/mongorestore
load_mongo_tls_args() {
  load_mongo_tls_dump_args
}
