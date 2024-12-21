package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/Netflix/go-env"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/codeartifact"
	"github.com/gorilla/mux"
)

type Config struct {
	Region         string `env:"PROXY_REGION,required=true"`
	AccountId      string `env:"PROXY_ACCOUNT_ID,required=true"`
	Domain         string `env:"PROXY_DOMAIN,required=true"`
	Repository     string `env:"PROXY_REPOSITORY,required=true"`
	Username       string `env:"ProxyUsername"`
	Password       string `env:"ProxyPassword"`
	AllowAnonymous bool   `env:"PROXY_ALLOW_ANONYMOUS"`
	ServerPort     string `env:"PROXY_SERVER_PORT,default=5000"`
}

var (
	authToken  string
	tokenMutex sync.RWMutex
	config     Config
	client     *codeartifact.CodeArtifact
)

func updateAuthToken() {
	input := &codeartifact.GetAuthorizationTokenInput{
		Domain:          aws.String(config.Domain),
		DomainOwner:     aws.String(config.AccountId),
		DurationSeconds: aws.Int64(43200),
	}

	result, err := client.GetAuthorizationToken(input)
	if err != nil {
		log.Fatalf("Failed to update auth token: %v", err)
	}

	tokenMutex.Lock()
	authToken = aws.StringValue(result.AuthorizationToken)
	tokenMutex.Unlock()

	log.Println("Got new token")
}

func generateURL(path string) string {
	if strings.HasPrefix(path, "/") {
		path = path[1:]
	}
	tokenMutex.RLock()
	defer tokenMutex.RUnlock()
	return fmt.Sprintf(
		"https://aws:%s@%s-%s.d.codeartifact.%s.amazonaws.com/pypi/%s/simple/%s",
		authToken,
		config.Domain,
		config.AccountId,
		config.Region,
		config.Repository,
		path,
	)
}

func proxyHandler(w http.ResponseWriter, r *http.Request) {
	path := mux.Vars(r)["path"]
	log.Printf("%s %s\n", r.Method, r.URL.Path)

	switch r.Method {
	case http.MethodGet:
		resp, err := http.Get(generateURL(path))
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		defer func(Body io.ReadCloser) {
			err := Body.Close()
			if err != nil {
				log.Printf("Failed to close response body: %v", err)
			}
		}(resp.Body)
		w.WriteHeader(resp.StatusCode)
		_, err = io.Copy(w, resp.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

	case http.MethodPost:
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Failed to read request body", http.StatusBadRequest)
			return
		}
		resp, err := http.Post(generateURL(path), "application/json", strings.NewReader(string(body)))
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		defer func(Body io.ReadCloser) {
			err := Body.Close()
			if err != nil {
				log.Printf("Failed to close response body: %v", err)
			}
		}(resp.Body)
		w.WriteHeader(resp.StatusCode)
		_, err = io.Copy(w, resp.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

func basicAuthMiddleware(next http.Handler) http.Handler {
	if config.AllowAnonymous {
		return next
	}

	if config.Username == "" || config.Password == "" {
		log.Fatal("Username and password must be set if anonymous access is not allowed")
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, p, ok := r.BasicAuth()
		if !ok || u != config.Username || p != config.Password {
			w.Header().Set("WWW-Authenticate", `Basic realm="Restricted"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	// Load config
	_, err := env.UnmarshalFromEnviron(&config)
	if err != nil {
		log.Fatalf("Failed to load environment variables: %v", err)
	}

	// Create AWS session
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(config.Region),
	})
	if err != nil {
		log.Fatalf("Failed to create AWS session: %v", err)
	}
	client = codeartifact.New(sess)

	// Initialize token
	updateAuthToken()

	// Set up periodic token refresh
	go func() {
		for range time.Tick(6 * time.Hour) {
			updateAuthToken()
		}
	}()

	// Set up routes
	r := mux.NewRouter()
	r.HandleFunc("/{path:.*}", proxyHandler).Methods(http.MethodGet, http.MethodPost)

	// Add Basic Auth if required
	handler := basicAuthMiddleware(r)

	// Start server
	log.Printf("Server starting on port %s\n", config.ServerPort)
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%s", config.ServerPort), handler))
}
