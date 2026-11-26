set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

sync:
    @kugi sync

doctor:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just doctor; else echo "kugi: $(kugi version)"; echo "kizu: $(kizu version)"; echo "zig:  $(zig version)"; echo "just: $(just --version)"; echo "tlc:  $(command -v tlc)"; fi

build-ghostty:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just build-ghostty; else ./core/scripts/build-ghostty; fi

kizu-lint:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just kizu-lint; else for package in core core/host core/spec; do kizu lint "$package"; done; fi

kizu-fmt-check:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just kizu-fmt-check; else for file in $(find core -name '*.kizu' -type f | sort); do kizu fmt "$file" | diff -u "$file" -; done; fi

comment-lint:
    @python3 scripts/comment-lint

check:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just check; else for package in core core/host core/spec; do kizu check "$package"; done; fi

test:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just test; else ./core/scripts/test; fi

spec-table:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just spec-table; else ./core/scripts/spec-table; fi

spec-table-check:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just spec-table-check; else ./core/scripts/spec-table --check; fi

spec-verify:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just spec-verify; else ./core/scripts/spec-verify; fi

swift-lint:
    @swift_format="$(env -u SDKROOT -u DEVELOPER_DIR /usr/bin/xcrun --find swift-format)"; "$swift_format" lint --strict --recursive --configuration .swift-format app

fmt:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just fmt; else for file in $(find core -name '*.kizu' -type f | sort); do kizu fmt --write "$file"; done; swift_format="$(env -u SDKROOT -u DEVELOPER_DIR /usr/bin/xcrun --find swift-format)"; "$swift_format" format --in-place --recursive --configuration .swift-format app; shell_scripts=(); while IFS= read -r f; do shell_scripts+=("$f"); done < <(rg -l '^#!.*(bash|/sh)' scripts core/scripts --glob '*' | sort); shfmt -w -i 2 -ci "${shell_scripts[@]}"; fi

fmt-check:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just fmt-check; else just kizu-fmt-check && just swift-lint; shell_scripts=(); while IFS= read -r f; do shell_scripts+=("$f"); done < <(rg -l '^#!.*(bash|/sh)' scripts core/scripts --glob '*' | sort); shfmt -d -i 2 -ci "${shell_scripts[@]}"; fi

repo-lint:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just repo-lint; else typos && shell_scripts=() && while IFS= read -r f; do shell_scripts+=("$f"); done < <(rg -l '^#!.*(bash|/sh)' scripts core/scripts --glob '*' | sort) && shellcheck "${shell_scripts[@]}"; fi

verify:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just verify; else python3 scripts/verify; fi

verify-full:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just verify-full; else python3 scripts/verify --with-spec; fi

ci:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just ci; else python3 scripts/verify --with-build; fi

ci-full:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just ci-full; else python3 scripts/verify --with-spec --with-build; fi

build:
    @./scripts/native-build

app:
    @./scripts/native-app

install:
    @./scripts/install-app

relaunch:
    @./scripts/install-app --relaunch

ui-snapshot *args:
    @bin="app/.build/Kasugai"; [[ -x "$bin" ]] || ./scripts/native-build; "$bin" ui-snapshot {{args}}

dev-app:
    @./scripts/native-dev-app

dev-relaunch *args:
    @./scripts/dev-relaunch {{args}}

watch-dev *args:
    @./scripts/watch-dev {{args}}

daemon-status:
    @bin="/Applications/Kasugai.app/Contents/MacOS/kasugaid"; [[ -x "$bin" ]] || bin="app/.build/Kasugai"; "$bin" daemon-status

daemon-restart *args:
    @bin="/Applications/Kasugai.app/Contents/MacOS/kasugaid"; [[ -x "$bin" ]] || bin="app/.build/Kasugai"; "$bin" daemon-restart {{args}}

dev-daemon-status:
    @bin="app/.build/dev/Kasugai Dev.app/Contents/MacOS/kasugaid-dev"; [[ -x "$bin" ]] || bin="app/.build/Kasugai-dev"; KASUGAI_DAEMON_SOCKET="$HOME/Library/Application Support/Kasugai-Dev/run/daemon.sock" "$bin" daemon-status

dev-daemon-restart *args:
    @bin="app/.build/dev/Kasugai Dev.app/Contents/MacOS/kasugaid-dev"; [[ -x "$bin" ]] || bin="app/.build/Kasugai-dev"; KASUGAI_DAEMON_SOCKET="$HOME/Library/Application Support/Kasugai-Dev/run/daemon.sock" "$bin" daemon-restart {{args}}

run:
    @if [[ -z "${KUGI_ACTIVE:-}" ]]; then exec kugi exec -- env KUGI_ACTIVE=1 just run; else app="$(./scripts/native-app | tail -n 1)"; open "$app"; fi

clean:
    @rm -rf core/target app/.build
