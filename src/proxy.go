package main

import (
	"compress/gzip"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
)

var originTracker = make(map[string]*url.URL)
var mutex = &sync.Mutex{}

// ProxyRequestHandler intercepts requests and forwards them to the correct server, adding headers and handling the request
func ProxyRequestHandler(w http.ResponseWriter, r *http.Request) {
	mutex.Lock()
	// Store the original host header for each request
	originTracker[r.RemoteAddr] = r.URL
	originTracker[r.RemoteAddr].Host = r.Host
	originTracker[r.RemoteAddr].Scheme = r.URL.Scheme

	if r.Header.Get("X-Forwarded-Proto") == "https" {
		originTracker[r.RemoteAddr].Scheme = "https"
	} else {
		originTracker[r.RemoteAddr].Scheme = "http"
	}

	// Get the remote URL from the host
	remote := hostQuickLookup[r.Host]
	rep := repositoryQuickLookup[r.Host]
	token := domainTokens[rep.CodeArtifactDomain]

	// Parse the target URL and forward request
	u, _ := url.Parse(remote)
	r.Host = u.Host

	// Set the Authorization header with the CodeArtifact Authorization Token
	r.SetBasicAuth("aws", token)

	log.Printf("Sending request to %s%s", strings.Trim(remote, "/"), r.URL.RequestURI())
	mutex.Unlock()

	// Forward the request to the remote server
	resp, err := forwardRequest(u, r)
	if err != nil {
		http.Error(w, "Error forwarding request", http.StatusInternalServerError)
		return
	}

	// Modify the response if necessary
	err = ProxyResponseHandler()(resp)
	if err != nil {
		http.Error(w, "Error processing response", http.StatusInternalServerError)
		return
	}

	// Copy the response headers and body back to the client
	for key, values := range resp.Header {
		for _, value := range values {
			w.Header().Add(key, value)
		}
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

// forwardRequest manually forwards the request to the target server
func forwardRequest(target *url.URL, r *http.Request) (*http.Response, error) {
	client := &http.Client{}
	t := target.String()
	if strings.HasSuffix(t, "/") {
		t = t[:len(t)-1]
	}

	newURL := t + r.URL.RequestURI()
	if strings.HasSuffix(newURL, "/") {
		newURL = newURL[:len(newURL)-1]
	}

	req, err := http.NewRequest(r.Method, newURL, r.Body)
	if err != nil {
		return nil, err
	}

	// Copy the headers from the incoming request to the new request
	for key, values := range r.Header {
		for _, value := range values {
			req.Header.Add(key, value)
		}
	}

	// Send the request to the target server
	return client.Do(req)
}

// ProxyResponseHandler processes the response from the remote server
func ProxyResponseHandler() func(*http.Response) error {
	return func(r *http.Response) error {
		log.Printf("Received %d response from %s", r.StatusCode, r.Request.URL.String())

		contentType := r.Header.Get("Content-Type")

		mutex.Lock()
		originalUrl := originTracker[r.Request.RemoteAddr]
		delete(originTracker, r.Request.RemoteAddr)

		u, _ := url.Parse(r.Request.Host)
		hostname := u.Host + ":443"
		mutex.Unlock()

		// Rewrite the 301 to point from CodeArtifact URL to the proxy instead..
		if r.StatusCode == 301 || r.StatusCode == 302 {
			location, _ := r.Location()

			// Only attempt to rewrite the location if the host matches the CodeArtifact host
			if location.Host == u.Host {
				location.Host = originalUrl.Host
				location.Scheme = originalUrl.Scheme
				location.Path = strings.Replace(location.Path, u.Path, "", 1)

				r.Header.Set("Location", location.String())
			}
		}

		// Fixes for NPM-related requests
		if strings.HasPrefix(r.Request.UserAgent(), "npm") ||
			strings.HasPrefix(r.Request.UserAgent(), "pnpm") ||
			strings.HasPrefix(r.Request.UserAgent(), "yarn") ||
			strings.HasPrefix(r.Request.UserAgent(), "Bun") {

			if !strings.Contains(contentType, "application/json") && !strings.Contains(contentType, "application/vnd.npm.install-v1+json") {
				return nil
			}

			var body io.ReadCloser
			if r.Header.Get("Content-Encoding") == "gzip" {
				body, _ = gzip.NewReader(r.Body)
				r.Header.Del("Content-Encoding")
			} else {
				body = r.Body
			}

			// Modify the response content
			oldContentResponse, _ := ioutil.ReadAll(body)
			oldContentResponseStr := string(oldContentResponse)

			mutex.Lock()
			resolvedHostname := strings.Replace("", u.Host, hostname, -1)
			newUrl := fmt.Sprintf("%s://%s/", originalUrl.Scheme, originalUrl.Host)

			newResponseContent := strings.Replace(oldContentResponseStr, resolvedHostname, newUrl, -1)
			mutex.Unlock()

			r.Body = ioutil.NopCloser(strings.NewReader(newResponseContent))
			r.ContentLength = int64(len(newResponseContent))
			r.Header.Set("Content-Length", strconv.Itoa(len(newResponseContent)))
		}

		return nil
	}
}
