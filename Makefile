.PHONY: help test test-unit test-integration test-e2e test-fast test-coverage test-auth test-servers test-search test-health test-core install-dev lint format check-deps clean dev-test ci-test publish-dockerhub publish-dockerhub-component publish-dockerhub-version publish-dockerhub-no-mirror publish-local compose-up-agents compose-down-agents compose-logs-agents uv-update-locks npm-update-locks

# Default target
help:
	@echo "MCP Registry Testing Commands"
	@echo ""
	@echo "Setup:"
	@echo "  install-dev     Install development dependencies"
	@echo "  check-deps      Check if test dependencies are installed"
	@echo ""
	@echo "Testing:"
	@echo "  test            Run full test suite with coverage"
	@echo "  test-unit       Run unit tests only"
	@echo "  test-integration Run integration tests only"
	@echo "  test-e2e        Run end-to-end tests only"
	@echo "  test-fast       Run fast tests (exclude slow tests)"
	@echo "  test-coverage   Generate coverage reports"
	@echo ""
	@echo "Domain Testing:"
	@echo "  test-auth       Run authentication domain tests"
	@echo "  test-servers    Run server management domain tests"
	@echo "  test-search     Run search domain tests"
	@echo "  test-health     Run health monitoring domain tests"
	@echo "  test-core       Run core infrastructure tests"
	@echo ""
	@echo "Code Quality:"
	@echo "  lint            Run linting checks"
	@echo "  format          Format code"
	@echo "  clean           Clean up test artifacts"
	@echo ""
	@echo ""
	@echo "Docker Compose:"
	@echo "  ./build_and_run.sh          Build and run the local stack"
	@echo "  ./build_and_run.sh --help   Show stack startup options"
	@echo ""
	@echo "DockerHub Publishing:"
	@echo "  publish-dockerhub           Publish all images to DockerHub"
	@echo "  publish-dockerhub-component Publish specific component (COMPONENT=name)"
	@echo "  publish-dockerhub-version   Publish with version tag (VERSION=v1.0.0)"
	@echo "  publish-dockerhub-no-mirror Publish without external images"
	@echo "  publish-local               Build locally without pushing"
	@echo ""
	@echo "Local A2A Agent Development:"
	@echo "  compose-up-agents           Start A2A agents with docker-compose"
	@echo "  compose-down-agents         Stop A2A agents"
	@echo "  compose-logs-agents         Follow A2A agent logs in real-time"
	@echo ""
	@echo "Dependency Management:"
	@echo "  uv-update-locks             Refresh every uv.lock under the repo with a 7-day"
	@echo "                              supply-chain quarantine (UV_EXCLUDE_NEWER=now-7d)"
	@echo "  npm-update-locks            Refresh every package-lock.json under the repo with a 7-day"
	@echo "                              supply-chain quarantine (CUTOFF_EPOCH=now-7d)"

# Installation
install-dev:
	@echo "📦 Installing development dependencies..."
	pip install -e .[dev]

check-deps:
	@python scripts/test.py check

# Full test suite
test:
	@python scripts/test.py full

# Test types
test-unit:
	@python scripts/test.py unit

test-integration:
	@python scripts/test.py integration

test-e2e:
	@python scripts/test.py e2e

test-fast:
	@python scripts/test.py fast

test-coverage:
	@python scripts/test.py coverage

# Domain-specific tests
test-auth:
	@python scripts/test.py auth

test-servers:
	@python scripts/test.py servers

test-search:
	@python scripts/test.py search

test-health:
	@python scripts/test.py health

test-core:
	@python scripts/test.py core

# Code quality
lint:
	@echo "🔍 Running linting checks..."
	@python -m bandit -r registry/ -f json || true
	@echo "✅ Linting complete"

format:
	@echo "🎨 Formatting code..."
	@python -m black registry/ tests/ --diff --color
	@echo "✅ Code formatting complete"

# Cleanup
clean:
	@echo "🧹 Cleaning up test artifacts..."
	@rm -rf htmlcov/
	@rm -rf tests/reports/
	@rm -rf .coverage
	@rm -rf coverage.xml
	@rm -rf .pytest_cache/
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@echo "✅ Cleanup complete"

# Development workflow
dev-test: clean install-dev test-fast
	@echo "🚀 Development test cycle complete!"

# CI/CD workflow
ci-test: clean check-deps test test-coverage
	@echo "🏗️ CI/CD test cycle complete!"

# ========================================
# DockerHub Publishing
# ========================================

publish-dockerhub:
	@echo "Publishing all images to DockerHub..."
	./scripts/publish_containers.sh --dockerhub

publish-dockerhub-component:
	@echo "Publishing $(COMPONENT) to DockerHub..."
	./scripts/publish_containers.sh --dockerhub --component $(COMPONENT)

publish-dockerhub-version:
	@echo "Publishing all images to DockerHub with version $(VERSION)..."
	./scripts/publish_containers.sh --dockerhub --version $(VERSION)

publish-dockerhub-no-mirror:
	@echo "Publishing all images to DockerHub (skipping external images)..."
	./scripts/publish_containers.sh --dockerhub --skip-mirror

publish-local:
	@echo "Building all images locally (no push)..."
	./scripts/publish_containers.sh --local

# ========================================
# Local A2A Agent Development
# ========================================

compose-up-agents:
	@echo "Starting A2A agents with docker-compose..."
	cd agents/a2a && docker-compose -f docker-compose.local.yml up -d
	@echo "Agents started:"
	@echo "  Flight Booking Agent: http://localhost:9002/ping"
	@echo "  Travel Assistant Agent: http://localhost:9001/ping"

compose-down-agents:
	@echo "Stopping A2A agents..."
	cd agents/a2a && docker-compose -f docker-compose.local.yml down

compose-logs-agents:
	@echo "Following A2A agent logs..."
	cd agents/a2a && docker-compose -f docker-compose.local.yml logs -f

# ========================================
# Dependency Management
# ========================================
# Refresh every uv.lock in the repo while excluding any package version
# published in the last 7 days (rolling supply-chain quarantine).
# Override the window with UV_EXCLUDE_NEWER_DAYS=N.
UV_EXCLUDE_NEWER_DAYS ?= 7

uv-update-locks:
	@set -e; \
	if date -u -v-$(UV_EXCLUDE_NEWER_DAYS)d +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then \
		CUTOFF=$$(date -u -v-$(UV_EXCLUDE_NEWER_DAYS)d +%Y-%m-%dT%H:%M:%SZ); \
	else \
		CUTOFF=$$(date -u -d '$(UV_EXCLUDE_NEWER_DAYS) days ago' +%Y-%m-%dT%H:%M:%SZ); \
	fi; \
	export UV_EXCLUDE_NEWER=$$CUTOFF; \
	echo "UV_EXCLUDE_NEWER=$$UV_EXCLUDE_NEWER ($(UV_EXCLUDE_NEWER_DAYS)-day quarantine)"; \
	skipped=""; \
	for lock in $$(find . -name uv.lock -not -path '*/.venv/*' -not -path '*/node_modules/*' -not -path '*/.claude/*' | sort); do \
		dir=$$(dirname $$lock); \
		echo ""; \
		echo "==> Updating $$dir"; \
		if ! (cd $$dir && uv lock --upgrade); then \
			echo "WARNING: could not resolve $$dir under the $(UV_EXCLUDE_NEWER_DAYS)-day quarantine"; \
			echo "         (a pinned floor likely requires a version newer than the cutoff);"; \
			echo "         keeping its existing lockfile and continuing."; \
			skipped="$$skipped $$dir"; \
		fi; \
	done; \
	echo ""; \
	if [ -n "$$skipped" ]; then \
		echo "Refreshed all resolvable uv.lock files with cutoff $$UV_EXCLUDE_NEWER."; \
		echo "Skipped (unchanged) due to quarantine conflicts:$$skipped"; \
	else \
		echo "All uv.lock files refreshed with cutoff $$UV_EXCLUDE_NEWER"; \
	fi

npm-update-locks:
	@set -e; \
	if date -u -v-$(UV_EXCLUDE_NEWER_DAYS)d +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then \
		CUTOFF=$$(date -u -v-$(UV_EXCLUDE_NEWER_DAYS)d +%Y-%m-%dT%H:%M:%SZ); \
	else \
		CUTOFF=$$(date -u -d '$(UV_EXCLUDE_NEWER_DAYS) days ago' +%Y-%m-%dT%H:%M:%SZ); \
	fi; \
	export CUTOFF_EPOCH=$$CUTOFF; \
	echo "CUTOFF_EPOCH=$$CUTOFF_EPOCH"; \
	for lock in $$(find . -name package-lock.json -not -path '*/.claude/*' | sort); do \
	  	dir=$$(dirname $$lock); \
		echo ""; \
		echo "==> Updating $$dir"; \
		(cd $$dir && npm update --package-lock-only); \
	done
