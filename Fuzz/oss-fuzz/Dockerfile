FROM gcr.io/oss-fuzz-base/base-builder-swift

RUN git clone --depth 1 https://github.com/jsglazer/mdviewer /src/mdview

WORKDIR /src/mdview/Fuzz
COPY build.sh $SRC/
