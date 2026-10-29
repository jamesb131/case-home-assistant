.PHONY: validate sd-probe recovery-probe bootrom-probe configure build assemble-vendor

PROFILE ?= kiosk

validate:
	./scripts/validate.sh

sd-probe:
	./scripts/build-sd-probe-container.sh

recovery-probe:
	./scripts/build-recovery-signature-probe-container.sh

bootrom-probe:
	./scripts/build-bootrom-sram-probe-container.sh

configure:
	./scripts/build.sh --profile $(PROFILE) --configure-only

build:
	./scripts/build.sh --profile $(PROFILE)

assemble-vendor:
	./scripts/assemble-sd-image.sh --profile $(PROFILE) --mode vendor-chain
