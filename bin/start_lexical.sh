#!/usr/bin/env bash

case $1 in
    iex)
        ELIXIR_COMMAND=iex
        ;;
    *)
        ELIXIR_COMMAND=elixir
        ;;
esac

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

"${ELIXIR_COMMAND}" \
    --cookie "lexical" \
    --no-halt \
    "${SCRIPT_DIR}/../bin/boot.exs"
