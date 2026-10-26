.PHONY: validate configure build assemble-vendor

PROFILE ?= kiosk

validate:
	./scripts/validate.sh

configure:
	./scripts/build.sh --profile $(PROFILE) --configure-only

build:
	./scripts/build.sh --profile $(PROFILE)

assemble-vendor:
	./scripts/assemble-sd-image.sh --profile $(PROFILE) --mode vendor-chain
