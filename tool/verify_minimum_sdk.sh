#!/usr/bin/env bash

set -euo pipefail

readonly repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly profile="${1:-}"
readonly work_root="$(mktemp -d "${TMPDIR:-/tmp}/kache-minimum-sdk.XXXXXX")"

cleanup() {
  rm -rf "$work_root"
}
trap cleanup EXIT

prepare_package() {
  local package="$1"
  local source="$repo_root/packages/$package"
  local destination="$work_root/$package"

  mkdir -p "$destination"
  cp -R "$source/lib" "$destination/lib"
  cp -R "$source/test" "$destination/test"
  awk '$0 != "resolution: workspace"' "$source/pubspec.yaml" \
    >"$destination/pubspec.yaml"

  case "$package" in
    kache)
      ;;
    kache_flutter_hooks)
      cat >"$destination/pubspec_overrides.yaml" <<EOF
dependency_overrides:
  kache:
    path: ../kache
  kache_flutter:
    path: ../kache_flutter
EOF
      ;;
    kache_hooks_riverpod)
      cat >"$destination/pubspec_overrides.yaml" <<EOF
dependency_overrides:
  kache:
    path: ../kache
  kache_riverpod:
    path: ../kache_riverpod
EOF
      ;;
    kache_provider)
      cat >"$destination/pubspec_overrides.yaml" <<EOF
dependency_overrides:
  kache:
    path: ../kache
  kache_flutter:
    path: ../kache_flutter
EOF
      ;;
    *)
      cat >"$destination/pubspec_overrides.yaml" <<EOF
dependency_overrides:
  kache:
    path: ../kache
EOF
      ;;
  esac
}

run_dart_package() {
  local package="$1"
  (
    cd "$work_root/$package"
    dart pub get
    dart analyze lib
    dart test
  )
}

run_flutter_package() {
  local package="$1"
  shift
  (
    cd "$work_root/$package"
    flutter pub get
    flutter analyze lib
    flutter test "$@"
  )
}

case "$profile" in
  flutter-3.24)
    for package in \
      kache \
      kache_bloc \
      kache_connectivity_plus \
      kache_flutter \
      kache_hive_ce \
      kache_provider; do
      prepare_package "$package"
    done
    run_dart_package kache
    run_dart_package kache_bloc
    run_dart_package kache_hive_ce
    run_flutter_package kache_flutter
    run_flutter_package kache_connectivity_plus
    run_flutter_package kache_provider
    ;;
  dart-3.7)
    for package in kache kache_riverpod; do
      prepare_package "$package"
    done
    run_dart_package kache_riverpod
    ;;
  flutter-3.32)
    for package in \
      kache \
      kache_flutter \
      kache_flutter_hooks \
      kache_riverpod \
      kache_hooks_riverpod; do
      prepare_package "$package"
    done
    run_flutter_package kache_flutter_hooks
    run_flutter_package kache_hooks_riverpod
    ;;
  *)
    echo "Usage: $0 {flutter-3.24|dart-3.7|flutter-3.32}" >&2
    exit 64
    ;;
esac
