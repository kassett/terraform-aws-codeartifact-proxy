FROM golang:1.23.3 AS base

WORKDIR /app
COPY src/ /app
RUN rm -rf /app/utils
RUN rm -rf /app/*_test.go
RUN go mod download
RUN go build -o codeArtifactProxy

CMD ["/app/codeArtifactProxy"]