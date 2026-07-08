BINARY   := elap
DEST     := /usr/local/bin/$(BINARY)
RELEASE  := .build/release/$(BINARY)

## Build the release binary
build:
	swift build -c release
	@echo "Binary: $(RELEASE)"

## Install the binary to /usr/local/bin
install: build
	install -d /usr/local/bin
	install -m 755 "$(RELEASE)" "$(DEST)"
	@echo "Installed: $(DEST)"

## Remove the installed binary
uninstall:
	rm -f "$(DEST)"
	@echo "Removed: $(DEST)"

## Remove the build directory
clean:
	rm -rf .build
	@echo "Cleaned"

## Assemble dist/ELAP.app (menu bar app + bundled CLI)
app:
	./scripts/make-app.sh

.PHONY: build install uninstall clean app

# Universal binary: swift build -c release --arch arm64 --arch x86_64 → output in .build/apple/Products/Release/elap
