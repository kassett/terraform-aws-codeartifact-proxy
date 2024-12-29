package main

import (
	"fmt"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/codeartifact"
	"log"
	"net/http"
	"strings"
	"time"
)

var (
	repositorySettings    []RepositoryConfig
	repositoryQuickLookup map[string]RepositoryConfig
	hostQuickLookup       map[string]string
	healthCheckPath       string
	port                  int
	region                string
	accountId             string
	anonymousAccess       bool
	username              string
	password              string
	refreshCadence        int

	domainTokens       map[string]string
	codeArtifactClient *codeartifact.CodeArtifact
)

func refreshAuthTokens() {
	domainMap := map[string]string{}
	for _, rep := range repositorySettings {
		domainMap[rep.CodeArtifactDomain] = ""
	}

	for domain, _ := range domainTokens {
		input := &codeartifact.GetAuthorizationTokenInput{
			Domain:          aws.String(domain),
			DomainOwner:     aws.String(accountId),
			DurationSeconds: aws.Int64(43200),
		}

		result, err := codeArtifactClient.GetAuthorizationToken(input)
		if err != nil {
			log.Fatalf("Failed to update auth token: %v", err)
		}

		domainTokens[domain] = aws.StringValue(result.AuthorizationToken)

		log.Println("Got new token for domain:", domain)
	}

	// Now let's get the AWS generated repository URLs
	for _, rep := range repositorySettings {
		// Generate the repository endpoint as before
		input := &codeartifact.GetRepositoryEndpointInput{
			Domain:     aws.String(rep.CodeArtifactDomain),
			Repository: aws.String(rep.CodeArtifactRepository),
			Format:     aws.String(rep.PackageManagerFormat),
		}

		output, err := codeArtifactClient.GetRepositoryEndpoint(input)
		if err != nil {
			log.Fatal("Unable to get a repository endpoint: ", err)
		}

		endpoint := output.RepositoryEndpoint
		if !strings.HasPrefix(*endpoint, "https://") {
			log.Fatalf("Endpoint %s is not HTTPS. "+
				"Handling such a repository is not currently supported.", *endpoint)
		}

		for _, host := range rep.Hosts {
			hostQuickLookup[host] = *endpoint
		}
	}
}

func main() {
	session := unmarshallConfig()
	codeArtifactClient = codeartifact.New(session)

	domainTokens = make(map[string]string)
	hostQuickLookup = make(map[string]string)
	repositoryQuickLookup = make(map[string]RepositoryConfig)

	// Set the initial domainTokens map so there
	// is something to for refreshTokens to iterate on
	for _, rep := range repositorySettings {
		domainTokens[rep.CodeArtifactDomain] = ""
		for _, host := range rep.Hosts {
			repositoryQuickLookup[host] = rep
		}
	}

	refreshAuthTokens()
	// Set up a goroutine to refresh the auth tokens every 6 hours
	go func() {
		for range time.Tick(time.Duration(refreshCadence) * time.Second) {
			refreshAuthTokens()
		}
	}()

	fmt.Println("Starting server on port:", port)
	http.HandleFunc("/", ProxyRequestHandler)
	err := http.ListenAndServe(fmt.Sprintf(":%d", port), nil)
	if err != nil {
		log.Fatal(err)
	}
}
