package main

import (
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
)

// Test GenerateURL
func TestGenerateURL(t *testing.T) {
	tokenMutex = sync.RWMutex{}
	tokenMutex.Lock()
	authToken = "test-token"
	tokenMutex.Unlock()

	config = Config{
		Domain:     "test-domain",
		AccountId:  "123456789012",
		Region:     "us-east-1",
		Repository: "test-repo",
	}

	url := generateURL("some/package")
	expected := "https://aws:test-token@test-domain-123456789012.d.codeartifact.us-east-1.amazonaws.com/pypi/test-repo/simple/some/package"
	assert.Equal(t, expected, url, "Generated URL should match")
}

//
//// Test ProxyHandler GET
//func TestProxyHandlerGet(t *testing.T) {
//	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
//		assert.Equal(t, "/some/package", r.URL.Path, "Path should match")
//		w.WriteHeader(http.StatusOK)
//		_, _ = w.Write([]byte("mock response"))
//	}))
//	defer ts.Close()
//
//	// Override generateURL to point to the test server
//	generateURL = func(path string) string {
//		return ts.URL + path
//	}
//
//	r := httptest.NewRequest(http.MethodGet, "/some/package", nil)
//	w := httptest.NewRecorder()
//
//	handler := http.HandlerFunc(proxyHandler)
//	handler.ServeHTTP(w, r)
//
//	resp := w.Result()
//	body, _ := io.ReadAll(resp.Body)
//	assert.Equal(t, http.StatusOK, resp.StatusCode, "Status code should match")
//	assert.Equal(t, "mock response", string(body), "Response body should match")
//}
//
//// Test ProxyHandler POST
//func TestProxyHandlerPost(t *testing.T) {
//	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
//		assert.Equal(t, "/some/package", r.URL.Path, "Path should match")
//		assert.Equal(t, "application/json", r.Header.Get("Content-Type"), "Content-Type should match")
//		w.WriteHeader(http.StatusCreated)
//		_, _ = w.Write([]byte("post response"))
//	}))
//	defer ts.Close()
//
//	// Override generateURL to point to the test server
//	generateURL = func(path string) string {
//		return ts.URL + path
//	}
//
//	body := strings.NewReader(`{"key": "value"}`)
//	r := httptest.NewRequest(http.MethodPost, "/some/package", body)
//	r.Header.Set("Content-Type", "application/json")
//	w := httptest.NewRecorder()
//
//	handler := http.HandlerFunc(proxyHandler)
//	handler.ServeHTTP(w, r)
//
//	resp := w.Result()
//	respBody, _ := io.ReadAll(resp.Body)
//	assert.Equal(t, http.StatusCreated, resp.StatusCode, "Status code should match")
//	assert.Equal(t, "post response", string(respBody), "Response body should match")
//}
//
//// Test BasicAuthMiddleware
//func TestBasicAuthMiddleware(t *testing.T) {
//	config = Config{
//		AllowAnonymous: false,
//	}
//	secret = "testpass"
//
//	r := mux.NewRouter()
//	r.HandleFunc("/secure", func(w http.ResponseWriter, r *http.Request) {
//		w.WriteHeader(http.StatusOK)
//	})
//
//	handler := basicAuthMiddleware(r)
//
//	t.Run("Authorized", func(t *testing.T) {
//		r := httptest.NewRequest(http.MethodGet, "/secure", nil)
//		r.SetBasicAuth("user", "testpass")
//		w := httptest.NewRecorder()
//		handler.ServeHTTP(w, r)
//		assert.Equal(t, http.StatusOK, w.Result().StatusCode, "Authorized user should get 200")
//	})
//
//	t.Run("Unauthorized", func(t *testing.T) {
//		r := httptest.NewRequest(http.MethodGet, "/secure", nil)
//		r.SetBasicAuth("user", "wrongpass")
//		w := httptest.NewRecorder()
//		handler.ServeHTTP(w, r)
//		assert.Equal(t, http.StatusUnauthorized, w.Result().StatusCode, "Unauthorized user should get 401")
//	})
//}
