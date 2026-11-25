# devkit Swift toolchain — the cross-language stand-in for npm scripts.
#   make lint          SwiftLint (style + correctness)
#   make format        rewrite sources with swift-format
#   make format-check  verify formatting (no rewrite)
#   make build         Release build of every app scheme in SCHEMES, no code signing
#   make test          run the test target (if one exists)
#   make check         format-check + lint + build (the full local gate)
#   make editor-bundle rebuild the vendored CodeMirror bundle (needs Node; output is committed)
#   make fuzz          build all libFuzzer targets in Fuzz/ (requires -sanitize=fuzzer)
#
# The app links the local MarkdownRenderKit package. SCHEMES is explicit because the package
# adds its own scheme, which auto-detection would pick. Override on the command line, e.g.:
#   make build CONFIG=Debug

PROJECT  ?= mdview/mdview.xcodeproj
SCHEMES  ?= mdview
CONFIG   ?= Release
DEST     ?= platform=macOS
SWIFTSRC ?= $(shell find . -name '*.swift' -not -path '*/.build/*' -not -path '*/DerivedData/*' -not -path '*/.git/*' -not -path '*/node_modules/*')

.PHONY: lint format format-check build test check info fuzz fuzz-smoke editor-bundle

info:
	@echo "PROJECT = $(PROJECT)"
	@echo "SCHEMES = $(SCHEMES)"
	@echo "files   = $(words $(SWIFTSRC)) swift file(s)"

lint:
	swiftlint lint --strict

format:
	swift format format --in-place $(SWIFTSRC)

format-check:
	swift format lint --strict $(SWIFTSRC)

build:
	set -o pipefail; for scheme in $(SCHEMES); do \
		echo "==> xcodebuild $$scheme ($(CONFIG))"; \
		xcodebuild build -project "$(PROJECT)" -scheme "$$scheme" \
			-configuration $(CONFIG) -destination '$(DEST)' CODE_SIGNING_ALLOWED=NO || exit 1; \
	done

test:
	set -o pipefail; for scheme in $(SCHEMES); do \
		xcodebuild test -project "$(PROJECT)" -scheme "$$scheme" \
			-destination '$(DEST)' CODE_SIGNING_ALLOWED=NO || exit 1; \
	done

editor-bundle:
	cd Packages/MarkdownRenderKit/editor-src && npm ci && npm run build

check: format-check lint build

fuzz-smoke:
	cd Fuzz && swift run SmokeTest

fuzz:
	@echo "libFuzzer is not available in Xcode's macOS toolchain."
	@echo "Fuzz targets run in the OSS-Fuzz Docker environment (Linux + open-source Swift)."
	@echo "To test locally: make fuzz-smoke"
	@echo "To run in Docker: see Fuzz/oss-fuzz/README.md"
