#!/bin/sh
# A stand-in for Julia in dyad-ui-shot's tests.
#   FAKE_JULIA_MODE=deps   answer the language server's dependency listing
#                          with "no Dyad dependencies" (anything else: exit 0)
#   FAKE_JULIA_MODE=sleep  hang: record this process and its child in
#                          $FAKE_JULIA_PIDS, then wait on a long sleep
[ -n "$FAKE_JULIA_LOG" ] && echo "$*" >> "$FAKE_JULIA_LOG"
case "$FAKE_JULIA_MODE" in
  sleep)
    sleep 600 &
    echo "$$ $!" >> "$FAKE_JULIA_PIDS"
    wait
    ;;
  *)
    case "$*" in
      *list-dyad-dependencies*)
        printf 'status = true\ndyad_dependencies = []\ndyad_names = []\n'
        ;;
    esac
    ;;
esac
