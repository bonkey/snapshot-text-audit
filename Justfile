dist := "dist"
artifact := "snapshot-text-audit-macos-universal.tar.gz"

default:
    @just --list

build:
    swift build -c release

test:
    swift test

# Debug binary, for iterating.
run *ARGS:
    swift run snapshot-text-audit {{ARGS}}

# Universal binary — Apple silicon and Intel in one file.
universal:
    swift build -c release --arch arm64 --arch x86_64
    @lipo -info .build/apple/Products/Release/snapshot-text-audit

# Defaults to a user-writable prefix so installing needs no sudo.
#   just prefix=/usr/local/bin install
prefix := env_var_or_default("PREFIX", home_directory() / ".local/bin")

install: universal
    @mkdir -p "{{prefix}}"
    install -m 0755 .build/apple/Products/Release/snapshot-text-audit "{{prefix}}/snapshot-text-audit"
    @echo "installed → {{prefix}}/snapshot-text-audit"
    @command -v snapshot-text-audit >/dev/null 2>&1 || echo "note: {{prefix}} is not on your PATH"

uninstall:
    rm -f "{{prefix}}/snapshot-text-audit"

# Tarball + checksum in {{dist}}/. The name carries no version so that
# /releases/latest/download/{{artifact}} is a stable URL.
package: test universal
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{dist}}" && mkdir -p "{{dist}}"
    staging=$(mktemp -d)
    cp .build/apple/Products/Release/snapshot-text-audit "$staging/"
    cp README.md LICENSE "$staging/"
    tar -czf "{{dist}}/{{artifact}}" -C "$staging" .
    rm -rf "$staging"
    (cd "{{dist}}" && shasum -a 256 *.tar.gz > checksums.txt)
    ls -lh "{{dist}}"

# Cut a release from this machine — no CI involved.
#   just release v1.0.0
release TAG: test
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! "{{TAG}}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        echo "tag must look like v1.2.3, got {{TAG}}" >&2; exit 1
    fi
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "working tree is dirty — commit or stash first" >&2; exit 1
    fi
    if git rev-parse "{{TAG}}" >/dev/null 2>&1; then
        echo "tag {{TAG}} already exists" >&2; exit 1
    fi
    git tag -a "{{TAG}}" -m "{{TAG}}"
    # Push before creating the release: gh would otherwise invent the tag from the
    # default branch head rather than use the annotated one just made here.
    git push origin "{{TAG}}"
    just package
    gh release create "{{TAG}}" \
        --title "{{TAG}}" \
        --generate-notes \
        "dist/{{artifact}}" \
        dist/checksums.txt
    echo "released {{TAG}} — https://github.com/bonkey/snapshot-text-audit/releases/tag/{{TAG}}"

clean:
    rm -rf .build "{{dist}}"
