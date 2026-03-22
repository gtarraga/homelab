package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
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
	publicIssuerEnv      = "PUBLIC_ISSUER_URL"
)

func main() {
	client, err := newKubeClient()
	if err != nil {
		log.Fatalf("create kube client: %v", err)
	}

	publicIssuerURL, err := loadPublicIssuerURL()
	if err != nil {
		log.Fatalf("load public issuer URL: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc(pathOpenIDConfig, proxyHandler(client, pathOpenIDConfig, publicIssuerURL))
	mux.HandleFunc(pathJWKS, proxyHandler(client, pathJWKS, ""))
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

func proxyHandler(client *http.Client, path string, publicIssuerURL string) http.HandlerFunc {
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

		if path == pathOpenIDConfig && publicIssuerURL != "" && statusCode == http.StatusOK {
			body, err = rewriteOpenIDConfig(body, publicIssuerURL)
			if err != nil {
				http.Error(w, fmt.Sprintf("rewrite openid config: %v", err), http.StatusBadGateway)
				return
			}
		}

		if contentType != "" {
			w.Header().Set("Content-Type", contentType)
		}
		w.WriteHeader(statusCode)
		_, _ = w.Write(body)
	}
}

func loadPublicIssuerURL() (string, error) {
	issuerURL := strings.TrimSpace(os.Getenv(publicIssuerEnv))
	if issuerURL == "" {
		return "", nil
	}

	parsedURL, err := url.Parse(issuerURL)
	if err != nil {
		return "", fmt.Errorf("parse %s: %w", publicIssuerEnv, err)
	}
	if parsedURL.Scheme != "https" {
		return "", fmt.Errorf("%s must use https", publicIssuerEnv)
	}
	if parsedURL.Host == "" {
		return "", fmt.Errorf("%s must include host", publicIssuerEnv)
	}
	if parsedURL.Path != "" && parsedURL.Path != "/" {
		return "", fmt.Errorf("%s must not include path", publicIssuerEnv)
	}

	return strings.TrimRight(issuerURL, "/"), nil
}

func rewriteOpenIDConfig(body []byte, issuerURL string) ([]byte, error) {
	var config map[string]json.RawMessage
	if err := json.Unmarshal(body, &config); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}

	issuerValue, err := json.Marshal(issuerURL)
	if err != nil {
		return nil, fmt.Errorf("marshal issuer: %w", err)
	}
	jwksValue, err := json.Marshal(issuerURL + pathJWKS)
	if err != nil {
		return nil, fmt.Errorf("marshal jwks uri: %w", err)
	}

	config["issuer"] = issuerValue
	config["jwks_uri"] = jwksValue

	rewrittenBody, err := json.Marshal(config)
	if err != nil {
		return nil, fmt.Errorf("encode response: %w", err)
	}

	return rewrittenBody, nil
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
		MaxIdleConns:       4,
		IdleConnTimeout:    transportIdleTimeout,
		DisableCompression: true,
		ForceAttemptHTTP2:  true,
	}

	return &http.Client{
		Timeout:   upstreamTimeout,
		Transport: transport,
	}, nil
}
