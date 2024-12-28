package main

import (
	"encoding/json"
	"fmt"
	"github.com/aws/aws-sdk-go/service/secretsmanager"
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
	Region          string `env:"PROXY_REGION,required=true"`
	AccountId       string `env:"PROXY_ACCOUNT_ID,required=true"`
	Domain          string `env:"PROXY_DOMAIN,required=true"`
	Repository      string `env:"PROXY_REPOSITORY,required=true"`
	SecretId        string `env:"PROXY_SECRET_ID"`
	AllowAnonymous  bool   `env:"PROXY_ALLOW_ANONYMOUS"`
	ServerPort      string `env:"PROXY_SERVER_PORT,default=5000"`
	HealthCheckPath string `env:"PROXY_HEALTH_CHECK_PATH,default=/health"`
}

var (
	authToken  string
	tokenMutex sync.RWMutex
	config     Config
	client     *codeartifact.CodeArtifact
	username   string
	password   string
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

func fetchSecret(sess *session.Session) (string, string) {
	if config.SecretId == "" {
		log.Println("No SecretId provided. Skipping secret fetch.")
		return "", ""
	}

	secretsClient := secretsmanager.New(sess)
	input := &secretsmanager.GetSecretValueInput{
		SecretId: aws.String(config.SecretId),
	}

	result, err := secretsClient.GetSecretValue(input)
	if err != nil {
		log.Fatalf("Failed to retrieve secret: %v", err)
	}

	log.Println("Fetched secret from Secrets Manager")

	secretString := aws.StringValue(result.SecretString)
	keyValue := make(map[string]string)
	err = json.Unmarshal([]byte(secretString), &keyValue)
	if err != nil {
		log.Fatalf("Failed to parse secret: %v", err)
	}

	username, usernameExists := keyValue["username"]
	password, passwordExists := keyValue["password"]
	if !usernameExists || !passwordExists || username == "" || password == "" {
		log.Fatalf("Username or password not found or empty in secret")
	}

	return username, password
}

func proxyHandler(w http.ResponseWriter, r *http.Request) {
	path := mux.Vars(r)["path"]

	// Log the origin host
	log.Printf("Origin Host: %s", r.Host)

	log.Printf("%s %s\n", r.Method, r.URL.Path)

	switch r.Method {
	case http.MethodGet:
		resp, err := http.Get(generateURL(path))
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		defer resp.Body.Close()
		w.WriteHeader(resp.StatusCode)
		_, err = io.Copy(w, resp.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
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
		defer resp.Body.Close()
		w.WriteHeader(resp.StatusCode)
		_, err = io.Copy(w, resp.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

func basicAuthMiddleware(next http.Handler) http.Handler {
	if config.AllowAnonymous {
		return next
	}

	if username == "" || password == "" {
		log.Fatal("Username and password must be set if anonymous access is not allowed")
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, p, ok := r.BasicAuth()
		if !ok || u != username || p != password {
			w.Header().Set("WWW-Authenticate", `Basic realm="Restricted"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func healthCheckHandler(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok"}`))
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

	if config.SecretId != "" {
		username, password = fetchSecret(sess)
	}

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
	r.HandleFunc(config.HealthCheckPath, healthCheckHandler).Methods(http.MethodGet) // Unauthenticated route

	authenticatedRoutes := r.PathPrefix("/").Subrouter()
	authenticatedRoutes.HandleFunc("/{path:.*}", proxyHandler).Methods(http.MethodGet, http.MethodPost)
	r.PathPrefix("/").Handler(basicAuthMiddleware(authenticatedRoutes)) // Authenticated routes

	// Start server
	log.Printf("Server starting on port %s\n", config.ServerPort)
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%s", config.ServerPort), r))
}
