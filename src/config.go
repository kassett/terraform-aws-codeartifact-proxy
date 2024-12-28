package main

import (
	"encoding/json"
	"github.com/Netflix/go-env"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/secretsmanager"
	"log"
	"os"
)

type EnvVars struct {
	CapRegion          string `env:"CAP_REGION,required=true"`
	CapAccountId       string `env:"CAP_ACCOUNT_ID,required=true"`
	CapAllowAnonymous  bool   `env:"CAP_ALLOW_ANONYMOUS,require=true"`
	CapPort            int    `env:"CAP_PORT,default=5000"`
	CapConfigPath      string `env:"CAP_CONFIG_PATH,default=/app/config.json"`
	CapHealthCheckPath string `env:"CAP_HEALTH_CHECK_PATH,default=/health"`
	CapAuthSecret      string `env:"CAP_AUTH_SECRET"`
}

// RepositoryConfig This proxy can support multiple packages managers, but each must have a different host
type RepositoryConfig struct {
	Hosts                  []string `json:"hosts"`
	CodeArtifactDomain     string   `json:"code_artifact_domain"`
	CodeArtifactRepository string   `json:"code_artifact_repository"`
	PackageManagerFormat   string   `json:"package_manager_format"`
}

// unmarshallConfig initializes configuration and returns an AWS session
func unmarshallConfig() *session.Session {
	var config EnvVars

	// Load environment variables
	_, err := env.UnmarshalFromEnviron(&config)
	if err != nil {
		log.Fatalf("Failed to load environment variables: %v", err)
	}

	// Set global variables
	configPath := config.CapConfigPath
	healthCheckPath = config.CapHealthCheckPath
	anonymousAccess = config.CapAllowAnonymous
	port = config.CapPort
	region = config.CapRegion
	accountId = config.CapAccountId

	// Read the JSON configuration file
	bytes, err := os.ReadFile(configPath)
	if err != nil {
		log.Fatalf("Error reading file %s: %v. "+
			"Ensure the entrypoint executed successfully and "+
			"the config path matches the entrypoint destination path.", configPath, err)
	}

	// Unmarshal the JSON file into repositorySettings
	err = json.Unmarshal(bytes, &repositorySettings)
	if err != nil {
		log.Fatalf("Error unmarshalling JSON: %v", err)
	}

	// Create AWS session
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(region),
	})
	if err != nil {
		log.Fatalf("Error creating an AWS session: %v", err)
	}

	// Fetch secret from AWS Secrets Manager if CAP_AUTH_SECRET is set
	if anonymousAccess && config.CapAuthSecret != "" {
		secretsClient := secretsmanager.New(sess)
		input := &secretsmanager.GetSecretValueInput{
			SecretId: aws.String(config.CapAuthSecret),
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
	}

	return sess
}
