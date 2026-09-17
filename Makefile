CC = clang
CFLAGS = -O2 -Wall -Wextra -Werror
FRAMEWORKS = -framework AppKit -framework IOKit
.PHONY: all test clean
all: build/mouselock build/mouse-diagnose
build:
	mkdir -p build
build/mouselock: src/hid_guard.m src/bounds.h src/motion.h | build
	$(CC) $(CFLAGS) -Wno-deprecated-declarations -fobjc-arc src/hid_guard.m $(FRAMEWORKS) -o $@
build/mouse-diagnose: src/diagnose.m | build
	$(CC) $(CFLAGS) -fobjc-arc src/diagnose.m $(FRAMEWORKS) -o $@
test: | build
	$(CC) $(CFLAGS) tests/bounds_test.c -o build/bounds-test
	./build/bounds-test
	$(CC) $(CFLAGS) tests/motion_test.c -o build/motion-test
	./build/motion-test
clean:
	rm -rf build
