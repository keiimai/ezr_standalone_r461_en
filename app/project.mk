# --- make commands the project adds (Layers 4–5 extension point) (LAYERS.md "Extension points for Layers 4–5") ---
.PHONY: ezr-test ezr-test-launcher ezr-build-amd64 ezr-test-amd64

EZR_NAME  := $(shell sed -n 's/^name: //p' docker-compose.yml)
EZR_AMD64 := $(EZR_NAME):dev-amd64
EZR_RUN   := docker run --rm --user rstudio -e HOME=/home/rstudio -v "$(CURDIR):/app" -w /app
EZR_TEST  := Rscript -e "testthat::test_dir('tests/testthat', filter = 'project_ezr', reporter = 'summary', stop_on_failure = TRUE)"

ezr-test:  ## Run only the EZR start test in a throwaway container, with the image built by make build
	docker compose run --rm --user rstudio task $(EZR_TEST)

ezr-build-amd64:  ## Build an amd64 image as on Windows (emulated on this Mac, so it takes time)
	docker build --platform linux/amd64 --target dev -t $(EZR_AMD64) .

ezr-test-amd64:  ## Run the EZR start test with the image built by ezr-build-amd64
	$(EZR_RUN) --platform linux/amd64 $(EZR_AMD64) $(EZR_TEST)

ezr-test-launcher:  ## Run the tests of the standalone start flow (launcher/standalone.py) on the host (no virtual machine is started)
	PYTHONDONTWRITEBYTECODE=1 python3 -I -B ../tests/test_standalone.py
