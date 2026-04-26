.PHONY: build test app dmg clean

build:
	swift build

test:
	swift test

app:
	bash scripts/build-app.sh

dmg:
	bash scripts/build-dmg.sh

clean:
	swift package clean
