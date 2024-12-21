package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"regexp"
)

func main() {
	newVersion := os.Getenv("NEW_VERSION")
	filePath := os.Getenv("FILE_PATH")
	if newVersion == "" || filePath == "" {
		log.Fatal("Environment variables NEW_VERSION and FILE_PATH must be set")
	}
	content, err := ioutil.ReadFile(filePath)
	if err != nil {
		log.Fatalf("Error reading file: %v", err)
	}

	// Adjusted regex to handle potential spaces around the "="
	re := regexp.MustCompile(`(?m)^(\s*TRACKED_GIT_VERSION\s*=\s*")([^"]*)(".*)$`)
	updatedContent := re.ReplaceAllString(string(content), `${1}`+newVersion+`${3}`)
	fmt.Print(updatedContent)
	if err = ioutil.WriteFile(filePath, []byte(updatedContent), 0644); err != nil {
		log.Fatalf("Error writing to file: %v", err)
	}
}
