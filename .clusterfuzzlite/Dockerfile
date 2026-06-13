# ClusterFuzzLite build environment for mdview's Swift fuzz targets.
# Uses the same open-source Swift toolchain image as OSS-Fuzz so libFuzzer is
# available (it is not in the macOS Xcode toolchain). Fuzzing runs in GitHub
# Actions on PRs — see .github/workflows/cflite_pr.yml.
FROM gcr.io/oss-fuzz-base/base-builder-swift

COPY . $SRC/mdview
WORKDIR $SRC/mdview
COPY .clusterfuzzlite/build.sh $SRC/
