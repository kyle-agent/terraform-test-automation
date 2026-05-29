.PHONY: tools test test-chapter test-one test-deep test-integration discover loop coverage merge clean lint fmt help

MODE ?= dry-run
CH   ?= chapter1_core
TEST ?=
ITER ?= 3
OUT  := out
OUTABS := $(abspath $(OUT))
GO   := go

help:
	@echo "Targets:"
	@echo "  tools             - install required tools (go, terraform check)"
	@echo "  discover          - list dynamically-discovered chapters & scenarios"
	@echo "  test              - run all regression tests, fanned out per chapter (MODE=$(MODE))"
	@echo "  test-chapter      - run a specific chapter (CH=chapter1_core)"
	@echo "  test-one          - run a specific test (TEST=TestIssue02_...)"
	@echo "  test-deep         - run deep audit regression tests"
	@echo "  test-integration  - shorthand for MODE=integration test"
	@echo "  loop              - iterative regression loop (ITER=$(ITER) [CH=...])"
	@echo "  coverage          - resource-surface coverage report (out/coverage.md)"
	@echo "  merge             - merge per-shard results into out/results.json + junit"
	@echo "  lint              - go vet"
	@echo "  fmt               - go fmt ./..."
	@echo "  clean             - remove out/"

tools:
	@command -v go >/dev/null 2>&1 || { echo "go not found"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "terraform not found"; exit 1; }
	@command -v jq >/dev/null 2>&1 || { echo "jq not found"; exit 1; }
	@$(GO) mod download
	@echo "Tools OK"

$(OUT):
	@mkdir -p $(OUT)

discover:
	@scripts/discover.sh list

# `test` fans out one go-test invocation per dynamically-discovered chapter,
# each writing to its own out/<chapter>/ so parallel reporters never clobber a
# shared results.json. merge_results.sh then folds the shards into the canonical
# out/results.json + out/junit.xml and exits non-zero on any regression.
test: $(OUT)
	@rm -rf $(OUTABS)/*/ 2>/dev/null || true
	@for ch in $$(scripts/discover.sh chapters | jq -r '.include[].chapter'); do \
	  echo "== $$ch =="; \
	  OUTPUT_DIR=$(OUTABS)/$$ch MODE=$(MODE) $(GO) test ./tests/$$ch/... -count=1 -timeout 60m \
	    -json > $(OUTABS)/$$ch.gotest.jsonl 2>&1 || true; \
	done
	@scripts/merge_results.sh $(OUTABS)

test-chapter: $(OUT)
	OUTPUT_DIR=$(OUTABS)/$(CH) MODE=$(MODE) $(GO) test ./tests/$(CH)/... -v -count=1 -timeout 60m

test-one: $(OUT)
	@if [ -z "$(TEST)" ]; then echo "set TEST=..."; exit 1; fi
	OUTPUT_DIR=$(OUTABS) MODE=$(MODE) $(GO) test ./tests/... -run "^$(TEST)$$" -v -count=1 -timeout 60m

test-deep: $(OUT)
	OUTPUT_DIR=$(OUTABS)/deep MODE=$(MODE) $(GO) test ./tests/deep/... -v -count=1 -timeout 60m

test-integration:
	$(MAKE) test MODE=integration

# Iterative / repeated regression run with flaky-vs-regression classification.
# Loops all chapters by default; restrict with LOOP_CH=<chapter>.
LOOP_CH ?=
loop: $(OUT)
	MODE=$(MODE) scripts/regression_loop.sh $(ITER) $(LOOP_CH)

coverage: $(OUT)
	OUTPUT_DIR=$(OUTABS)/coverage MODE=$(MODE) $(GO) test ./tests/coverage/... -v -count=1
	@echo "---"; cat $(OUTABS)/coverage/coverage.md 2>/dev/null | head -20 || true

merge: $(OUT)
	@scripts/merge_results.sh $(OUTABS)

lint:
	$(GO) vet ./...

fmt:
	$(GO) fmt ./...

clean:
	rm -rf $(OUT)
