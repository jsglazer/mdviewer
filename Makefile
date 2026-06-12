# devkit Swift toolchain — the cross-language stand-in for npm scripts.
#   make lint          SwiftLint (style + correctness)
#   make format        rewrite sources with swift-format
#   make format-check  verify formatting (no rewrite)
#   make build         Release build, no code signing
#   make test          run the test target (if one exists)
#   make check         format-check + lint + build (the full local gate)
#
# Project + scheme are auto-detected; override on the command line, e.g.:
#   make build SCHEME=MyApp CONFIG=Debug

PROJECT  ?= $(shell find . -maxdepth 3 -name '*.xcodeproj' -not -path '*/.*' | head -1)
SCHEME   ?= $(shell xcodebuild -list -project "$(PROJECT)" 2>/dev/null | awk '/Schemes:/{f=1; next} f && NF {gsub(/^ +/,""); print; exit}')
CONFIG   ?= Release
DEST     ?= platform=macOS
SWIFTSRC ?= $(shell find . -name '*.swift' -not -path '*/.build/*' -not -path '*/DerivedData/*' -not -path '*/.git/*')

.PHONY: lint format format-check build test check info

info:
	@echo "PROJECT = $(PROJECT)"
	@echo "SCHEME  = $(SCHEME)"
	@echo "files   = $(words $(SWIFTSRC)) swift file(s)"

lint:
	swiftlint lint --strict

format:
	swift format format --in-place $(SWIFTSRC)

format-check:
	swift format lint --strict $(SWIFTSRC)

build:
	set -o pipefail; xcodebuild build -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-configuration $(CONFIG) -destination '$(DEST)' CODE_SIGNING_ALLOWED=NO

test:
	set -o pipefail; xcodebuild test -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-destination '$(DEST)' CODE_SIGNING_ALLOWED=NO

check: format-check lint build
