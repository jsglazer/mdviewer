#!/bin/bash -eu
# OSS-Fuzz build script for mdview Swift fuzz targets.
# Runs inside the base-builder-swift Docker image (Linux, open-source Swift toolchain).
# Each fuzz target is a library source compiled with swiftc so libFuzzer can supply
# main() via -sanitize=fuzzer,address.  We inject a thin LLVMFuzzerTestOneInput
# wrapper for each target so the library files stay @_silgen_name-free and can be
# linked together cleanly in the local SmokeTest binary.

cd /src/mdview/Fuzz

declare -A TARGETS=(
    [FuzzDocument]="Sources/FuzzDocument/FuzzDocument.swift"
    [FuzzImagePath]="Sources/FuzzImagePath/FuzzImagePath.swift"
    [FuzzDiffing]="Sources/FuzzDiffing/FuzzDiffing.swift"
)

# Map target name → public function name called by the entry point
declare -A ENTRY=(
    [FuzzDocument]="fuzzDocument"
    [FuzzImagePath]="fuzzImagePath"
    [FuzzDiffing]="fuzzDiffing"
)

TMPDIR_FUZZ=$(mktemp -d)
trap 'rm -rf "$TMPDIR_FUZZ"' EXIT

for target in "${!TARGETS[@]}"; do
    src="${TARGETS[$target]}"
    fn="${ENTRY[$target]}"

    # Write a thin entry-point shim for this target
    shim="$TMPDIR_FUZZ/${target}_entry.swift"
    cat > "$shim" <<SWIFT
@_silgen_name("LLVMFuzzerTestOneInput")
public func LLVMFuzzerTestOneInput(_ start: UnsafePointer<UInt8>, _ count: Int) -> CInt {
    return ${fn}(start, count)
}
SWIFT

    swiftc \
        -parse-as-library \
        -sanitize=fuzzer,address \
        -O \
        "$src" \
        "$shim" \
        -o "$OUT/$target"

    # Zip seed corpus if present
    corpus_name=$(echo "$target" | sed 's/Fuzz//' | tr '[:upper:]' '[:lower:]')
    corpus_dir="corpus/$corpus_name"
    if [ -d "$corpus_dir" ] && [ -n "$(ls -A "$corpus_dir" 2>/dev/null)" ]; then
        zip -j "$OUT/${target}_seed_corpus.zip" "$corpus_dir"/*
        echo "  corpus: $OUT/${target}_seed_corpus.zip"
    fi

    echo "  built: $OUT/$target"
done
