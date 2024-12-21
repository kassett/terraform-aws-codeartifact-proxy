FROM golang:1.23.3 AS base

WORKDIR /app
COPY src/go.mod src/go.sum src/main.go /app/
RUN go mod download
RUN go build -o codeArtifactProxy

CMD ["/app/codeArtifactProxy"]