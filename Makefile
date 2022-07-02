DOCKER := docker run --rm -it -v $(PWD):/app:rw,delegated -w /app -e CARGO_HOME=/app/.cargo rust:1.62.0-slim-bullseye

.PHONY: shell
shell:
	@$(DOCKER) bash

.PHONY: format
format:
	@$(DOCKER) sh -c 'rustup component add rustfmt 2>/dev/null && cargo fmt'
