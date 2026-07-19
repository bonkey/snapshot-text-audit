version := `git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"`
dist := "dist"

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

install: universal
    install -m 0755 .build/apple/Products/Release/snapshot-text-audit /usr/local/bin/snapshot-text-audit
    @echo "installed → /usr/local/bin/snapshot-text-audit"

uninstall:
    rm -f /usr/local/bin/snapshot-text-audit

# Tarball + checksum in {{dist}}/, named for the current tag.
package: test universal
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{dist}}" && mkdir -p "{{dist}}"
    staging=$(mktemp -d)
    cp .build/apple/Products/Release/snapshot-text-audit "$staging/"
    cp README.md LICENSE "$staging/"
    tar -czf "{{dist}}/snapshot-text-audit-{{version}}-macos-universal.tar.gz" -C "$staging" .
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
    just package
    gh release create "{{TAG}}" \
        --title "{{TAG}}" \
        --generate-notes \
        dist/snapshot-text-audit-{{TAG}}-macos-universal.tar.gz \
        dist/checksums.txt
    git push origin "{{TAG}}"
    @echo "released {{TAG}}"

clean:
    rm -rf .build "{{dist}}"
