# Same Wealthfolio 3.5.2 app/frontend, rebuilt with fixed Rust certificate verification.
# Source is immutable and checksum verified; lock patch changes only three TLS crates.
FROM rust:1.91-alpine@sha256:45c1c35cd364b8055e9e86f8ecd3e8c874b2dcb658d8a4f94b5d111aa0d651a2 AS build
RUN apk add --no-cache build-base pkgconfig openssl-dev openssl-libs-static sqlite-dev clang lld cmake perl patch
WORKDIR /src
ADD --checksum=sha256:b1aeacfc5706dd71034204edfee53809e8831bd41826d8e51f0e82f17e51804f https://codeload.github.com/wealthfolio/wealthfolio/tar.gz/ead1bc5484a0987bf33eaa52f9549e121f3006d7 /tmp/source.tar.gz
RUN tar -xzf /tmp/source.tar.gz --strip-components=1 -C /src && rm /tmp/source.tar.gz
COPY apps/wealthfolio/image/Cargo.lock.patch /tmp/Cargo.lock.patch
RUN patch --fuzz=0 -p1 < /tmp/Cargo.lock.patch
COPY apps/wealthfolio/image/trust-probe.rs apps/server/src/bin/trust-probe.rs
ENV CARGO_BUILD_JOBS=2 OPENSSL_STATIC=1
RUN cargo build --release --locked -p wealthfolio-server --bin wealthfolio-server --bin trust-probe
# Tests use the same reqwest Client::new() and lock as the server, no app credentials.
RUN target/release/trust-probe

FROM ghcr.io/wealthfolio/wealthfolio:3.5.2@sha256:a830fdcf8294f1a7ae224eaf680b86007331c2fd3a739f1349681388e00d2c30
USER 0:0
COPY --from=build /src/target/release/wealthfolio-server /usr/local/bin/wealthfolio-server
COPY tools/certificates/filter-emudhra.sh /tmp/filter-emudhra.sh
RUN sh /tmp/filter-emudhra.sh \
 && rm -rf /etc/ssl/certs/* \
 && cp -R /patched-trust/system/. /etc/ssl/certs/ \
 && rm -rf /patched-trust /tmp/filter-emudhra.sh
USER 1000:1000
