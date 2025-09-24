# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Research repository for Model Context Protocol (MCP) registry deployment and management in Kubernetes environments. This appears to be an early-stage project focused on understanding and implementing MCP registry infrastructure patterns.

## Technology Stack

- **Primary Language**: Go (based on .gitignore configuration)
- **Target Environment**: Kubernetes
- **Focus Area**: Model Context Protocol registry infrastructure

## Development Setup

This repository is in early development phase. When Go modules are initialized, typical commands will include:

```bash
# Initialize Go module (when ready)
go mod init

# Build the project
go build ./...

# Run tests
go test ./...

# Run tests with coverage
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# Format code
go fmt ./...

# Vet code
go vet ./...
```

## Repository Structure

Currently minimal structure:
- `README.md` - Project description focusing on MCP registry Kubernetes research
- `.gitignore` - Go-specific ignore patterns with coverage and test artifacts
- `LICENSE` - MIT license

## Research Focus Areas

Based on the repository description, this project will likely explore:
- Model Context Protocol registry deployment patterns
- Kubernetes-native MCP registry management
- Infrastructure as code for MCP registries
- Registry scaling and high availability in K8s environments