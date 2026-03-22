package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

const (
	kubeAPIServer = "https://kubernetes.default.svc"
	saDir         = "/var/run/secrets/kubernetes.io/serviceaccount"

	pathOpenIDConfig = "/.well-known/openid-configuration"
	pathJWKS         = "/openid/v1/jwks"

	listenAddr           = ":8080"
	readHeaderTimeout    = 5 * time.Second
	upstreamTimeout      = 10 * time.Second
	transportIdleTimeout = 90 * time.Second
)

func main() {
	client, err := newKubeClient()
	if err != nil {
		log.Fatalf("create kube client: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc(pathOpenIDConfig, proxyHandler(client, pathOpenIDConfig))
	mux.HandleFunc(pathJWKS, proxyHandler(client, pathJWKS))
	mux.HandleFunc("/healthz", healthHandler)

	server := &http.Server{
		Addr:              listenAddr,
		Handler:           mux,
		ReadHeaderTimeout: readHeaderTimeout,
	}

	log.Printf("listening on %s", server.Addr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server error: %v", err)
	}
}

func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func proxyHandler(client *http.Client, path string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}

		body, statusCode, contentType, err := fetchFromKube(r.Context(), client, path)
		if err != nil {
			http.Error(w, fmt.Sprintf("upstream error: %v", err), http.StatusBadGateway)
			return
		}

		if contentType != "" {
			w.Header().Set("Content-Type", contentType)
		}
		w.WriteHeader(statusCode)
		_, _ = w.Write(body)
	}
}

func fetchFromKube(ctx context.Context, client *http.Client, path string) ([]byte, int, string, error) {
	tokenBytes, err := os.ReadFile(saDir + "/token")
	if err != nil {
		return nil, 0, "", fmt.Errorf("read service account token: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, kubeAPIServer+path, nil)
	if err != nil {
		return nil, 0, "", fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(tokenBytes)))

	resp, err := client.Do(req)
	if err != nil {
		return nil, 0, "", fmt.Errorf("kube API request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, 0, "", fmt.Errorf("read response body: %w", err)
	}

	return body, resp.StatusCode, resp.Header.Get("Content-Type"), nil
}

func newKubeClient() (*http.Client, error) {
	caCert, err := os.ReadFile(saDir + "/ca.crt")
	if err != nil {
		return nil, fmt.Errorf("read cluster CA: %w", err)
	}

	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(caCert) {
		return nil, fmt.Errorf("parse cluster CA PEM")
	}

	transport := &http.Transport{
		TLSClientConfig: &tls.Config{
			MinVersion: tls.VersionTLS12,
			RootCAs:    pool,
		},
		MaxIdleConns:        4,
		IdleConnTimeout:     transportIdleTimeout,
		DisableCompression:  true,
		ForceAttemptHTTP2:   true,
	}

	return &http.Client{
		Timeout:   upstreamTimeout,
		Transport: transport,
	}, nil
}
