FROM golang:1.26.10-alpine AS build
WORKDIR /src
COPY go.mod .
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/oidc-proxy ./main.go

FROM gcr.io/distroless/static:nonroot@sha256:516757106de35205efb70b91ba03f6f1298424a0678c603255cf2852a7000087
COPY --from=build /out/oidc-proxy /oidc-proxy
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/oidc-proxy"]
