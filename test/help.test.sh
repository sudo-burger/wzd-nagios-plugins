#! /bin/bash

DIR=$(dirname "$0")
PROGNAME="$DIR"/../plugins/check_oracle.sh

function pass() {
  echo "PASS"
}

function fail() {
  echo "FAIL"
}

main() {
  local ret
  printf "Call with no args exits with 1: "
  "$PROGNAME" > /dev/null 2>&1
  ret="$?"
  case "$ret" in
    1) pass;;
    *) fail;;
  esac

  printf "Call with --help exits with 0: "
  "$PROGNAME" --help > /dev/null 2>&1
  ret="$?"
  case "$ret" in
    0) pass;;
    *) fail;;
  esac


}

main "$@"
