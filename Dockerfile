FROM golang:latest AS base

WORKDIR /app
COPY codeArtifactProxy /app/
RUN go mod download
RUN go build -o codeArtifactProxy

CMD ["/app/codeArtifactProxy"]