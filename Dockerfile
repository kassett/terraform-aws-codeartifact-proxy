FROM golang:1.23.3 AS base

WORKDIR /app
COPY codeArtifactProxy /app/
RUN rm /app/*_test.go
RUN go mod download
RUN go build -o codeArtifactProxy

CMD ["/app/codeArtifactProxy"]