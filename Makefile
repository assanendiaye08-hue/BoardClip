# BoardClip — build & packaging
.PHONY: build test run release bundle dmg cert clean

build:
	swift build

test:
	./Scripts/test.sh

run:
	./Scripts/run.sh debug

release:
	./Scripts/bundle.sh release

bundle:
	./Scripts/bundle.sh debug

dmg:
	./Scripts/make-dmg.sh

cert:
	./Scripts/make-cert.sh

clean:
	rm -rf .build build
