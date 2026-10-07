CC      ?= gcc
CSTD    := -std=c11 -D_POSIX_C_SOURCE=200809L
WARN    := -Wall -Wextra -Werror
CFLAGS  ?= -O2 -g
override CFLAGS += $(CSTD) $(WARN) -Iinclude
LDLIBS  := -lm

LIB_SRC := src/geo.c src/graph.c src/heap.c src/nearest.c src/search.c
TESTS   := test_heap test_graph test_algos
TEST_DEFS := -DFIXTURE_DIR='"tests/fixtures"' -DREAL_GRAPH_DIR='"../graph/ucsc"'
SAN     := -fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all

GRAPH   ?= ../graph/ucsc

.PHONY: all test valgrind bench smoke clean

all: route

route: $(LIB_SRC) src/main.c $(wildcard include/*.h)
	$(CC) $(CFLAGS) -o $@ $(LIB_SRC) src/main.c $(LDLIBS)

# Unit tests, built with AddressSanitizer + UBSan (catches leaks and UB).
build/asan/%: tests/%.c $(LIB_SRC) $(wildcard include/*.h tests/*.h)
	@mkdir -p build/asan
	$(CC) $(CFLAGS) $(SAN) $(TEST_DEFS) -o $@ $< $(LIB_SRC) $(LDLIBS)

test: $(addprefix build/asan/,$(TESTS))
	@for t in $(TESTS); do echo "== $$t"; ./build/asan/$$t || exit 1; done
	@echo "All tests passed."

# Same tests, plain build, run under valgrind.
build/plain/%: tests/%.c $(LIB_SRC) $(wildcard include/*.h tests/*.h)
	@mkdir -p build/plain
	$(CC) $(CFLAGS) $(TEST_DEFS) -o $@ $< $(LIB_SRC) $(LDLIBS)

valgrind: $(addprefix build/plain/,$(TESTS))
	@for t in $(TESTS); do echo "== valgrind $$t"; \
	  valgrind -q --leak-check=full --error-exitcode=1 ./build/plain/$$t || exit 1; done

bench: route
	./route $(GRAPH) --bench 1000

# End-to-end check: route between two campus points with both algorithms.
smoke: route
	./route $(GRAPH) 36.9995 -122.0630 36.9915 -122.0525 --algo dijkstra
	./route $(GRAPH) 36.9995 -122.0630 36.9915 -122.0525 --algo astar --json | head -c 300; echo

clean:
	rm -rf build route
