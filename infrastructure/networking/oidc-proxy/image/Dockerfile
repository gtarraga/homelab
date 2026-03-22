FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod .
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/oidc-proxy ./main.go

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/oidc-proxy /oidc-proxy
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/oidc-proxy"]
