.PHONY: tools test test-chapter test-one test-deep test-integration clean lint fmt help

MODE ?= dry-run
CH   ?= chapter1_core
TEST ?=
OUT  := out
GO   := go

help:
	@echo "Targets:"
	@echo "  tools             - install required tools (go, terraform check)"
	@echo "  test              - run all regression tests (MODE=$(MODE))"
	@echo "  test-chapter      - run a specific chapter (CH=chapter1_core)"
	@echo "  test-one          - run a specific test (TEST=TestIssue02_...)"
	@echo "  test-deep         - run deep audit regression tests"
	@echo "  test-integration  - shorthand for MODE=integration test"
	@echo "  lint              - go vet"
	@echo "  fmt               - go fmt ./..."
	@echo "  clean             - remove out/"

tools:
	@command -v go >/dev/null 2>&1 || { echo "go not found"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "terraform not found"; exit 1; }
	@$(GO) mod download
	@echo "Tools OK"

$(OUT):
	@mkdir -p $(OUT)

test: $(OUT)
	MODE=$(MODE) $(GO) test ./tests/... -v -timeout 60m -json | tee $(OUT)/results.json
	@scripts/junit_from_json.sh $(OUT)/results.json $(OUT)/junit.xml || true

test-chapter: $(OUT)
	MODE=$(MODE) $(GO) test ./tests/$(CH)/... -v -timeout 60m

test-one: $(OUT)
	@if [ -z "$(TEST)" ]; then echo "set TEST=..."; exit 1; fi
	MODE=$(MODE) $(GO) test ./tests/... -run "^$(TEST)$$" -v -timeout 60m

test-deep: $(OUT)
	MODE=$(MODE) $(GO) test ./tests/deep/... -v -timeout 60m

test-integration:
	$(MAKE) test MODE=integration

lint:
	$(GO) vet ./...

fmt:
	$(GO) fmt ./...

clean:
	rm -rf $(OUT)
