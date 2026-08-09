#!/usr/bin/env bash
# Repository-owned test harness for the extracted behavior contract.

PASS=0
FAIL=0

_pass() {
  PASS=$((PASS + 1))
  printf '  PASS: %s\n' "$1"
}

_fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL: %s\n' "$1" >&2
}

_assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    _pass "$desc"
  else
    _fail "$desc (expected '$expected', got '$actual')"
  fi
}

_assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    _pass "$desc"
  else
    _fail "$desc (expected to contain '$expected', got '$actual')"
  fi
}

_assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if [[ "$actual" != *"$unexpected"* ]]; then
    _pass "$desc"
  else
    _fail "$desc (should not contain '$unexpected')"
  fi
}

_assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    _pass "$desc"
  else
    _fail "$desc (file not found: $path)"
  fi
}

_assert_file_missing() {
  local desc="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    _pass "$desc"
  else
    _fail "$desc (file should not exist: $path)"
  fi
}

_assert_file_content() {
  local desc="$1" expected="$2" path="$3" actual
  if [[ ! -f "$path" ]]; then
    _fail "$desc (file not found: $path)"
    return
  fi
  actual=$(cat "$path")
  _assert_eq "$desc" "$expected" "$actual"
}

# All suite directories are descendants of one validated root. Keeping the
# deletion target narrow matters because several migration fixtures manipulate
# symlinks and intentionally exercise failure paths.
_GSTACK_REGISTER_TEST_ROOT=$(mktemp -d \
  "${TMPDIR:-/tmp}/gstack-register-test.XXXXXXXX") || {
  printf 'gstack-register test: could not create temporary root\n' >&2
  exit 1
}
case "$_GSTACK_REGISTER_TEST_ROOT" in
  "${TMPDIR:-/tmp}"/gstack-register-test.*) ;;
  *)
    printf 'gstack-register test: unsafe temporary root: %s\n' \
      "$_GSTACK_REGISTER_TEST_ROOT" >&2
    exit 1
    ;;
esac
[[ -d "$_GSTACK_REGISTER_TEST_ROOT" ]] || {
  printf 'gstack-register test: temporary root is missing: %s\n' \
    "$_GSTACK_REGISTER_TEST_ROOT" >&2
  exit 1
}

_gstack_register_test_cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$_GSTACK_REGISTER_TEST_ROOT"
  exit "$status"
}
trap _gstack_register_test_cleanup EXIT

_tmpdir() {
  local path
  path=$(mktemp -d "$_GSTACK_REGISTER_TEST_ROOT/suite.XXXXXXXX") || {
    printf 'gstack-register test: could not create suite directory\n' >&2
    return 1
  }
  case "$path" in
    "$_GSTACK_REGISTER_TEST_ROOT"/*) ;;
    *)
      printf 'gstack-register test: unsafe suite directory: %s\n' "$path" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$path"
}

_mock_bin() {
  _tmpdir
}

_test_summary() {
  printf '\n================================\n'
  printf 'Results: %s passed, %s failed\n' "$PASS" "$FAIL"
  printf '================================\n'
  [[ "$FAIL" -eq 0 ]] && exit 0
  exit 1
}
