#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_SRC="$ROOT/build/packages"
REPO_OUT="$ROOT/build/repo"

rm -rf "$REPO_OUT"
mkdir -p "$REPO_OUT"

INDEX="$REPO_OUT/index.json"

printf '{\n  "schema": 1,\n  "updated": "%s",\n  "packages": {\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$INDEX"

first=1
for pkg_dir in "$PKG_SRC"/*/; do
  [ -d "$pkg_dir" ] || continue
  name="$(basename "$pkg_dir")"

  manifest="$pkg_dir/MANIFEST"
  if [ ! -f "$manifest" ]; then
    echo "skip: $name has no MANIFEST" >&2
    continue
  fi

  version="$(sed -n 's/^version=//p' "$manifest" | head -n1)"
  desc="$(sed -n 's/^desc=//p' "$manifest" | head -n1)"
  deps="$(sed -n 's/^deps=//p' "$manifest" | head -n1)"
  [ -z "$deps" ] && deps=""

  tar_name="${name}-${version}.tar.gz"
  tar_out="$REPO_OUT/$name"
  mkdir -p "$tar_out"

  if [ ! -d "$pkg_dir/files" ]; then
    echo "skip: $name has no files/ dir" >&2
    continue
  fi

  tar -czf "$tar_out/$tar_name" -C "$pkg_dir/files" .
  size="$(wc -c < "$tar_out/$tar_name" | tr -d ' ')"
  sha="$(sha256sum "$tar_out/$tar_name" | awk '{print $1}')"
  printf '%s\n' "$sha" > "$tar_out/$tar_name.sha256"

  deps_json="[]"
  if [ -n "$deps" ]; then
    deps_json="["
    first_d=1
    for d in $deps; do
      if [ $first_d -eq 0 ]; then deps_json="$deps_json,"; fi
      deps_json="$deps_json\"$d\""
      first_d=0
    done
    deps_json="$deps_json]"
  fi

  if [ $first -eq 0 ]; then printf ',\n' >> "$INDEX"; fi
  printf '    "%s": { "version": "%s", "size": %s, "sha256": "%s", "desc": "%s", "deps": %s }' \
    "$name" "$version" "$size" "$sha" "$desc" "$deps_json" >> "$INDEX"
  first=0
  echo "built: $name-$version ($size bytes)"
done

printf '\n  }\n}\n' >> "$INDEX"

echo "wrote: $INDEX"
