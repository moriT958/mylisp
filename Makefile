CC      ?= cc
TARGET  := mylisp
SRC_DIR := src
BUILD   ?= debug
OUT_DIR := build/$(BUILD)

# Example: make EXTRA_CFLAGS="-DDEBUG_STRESS_GC -DDEBUG_LOG_GC"
EXTRA_CFLAGS ?=

CFLAGS_COMMON := -std=c11 -Wall -Wextra -Wpedantic -MMD -MP

ifeq ($(BUILD),release)
  CFLAGS  := $(CFLAGS_COMMON) -O2 -DNDEBUG
  LDFLAGS :=
else
  CFLAGS  := $(CFLAGS_COMMON) -O0 -g -fsanitize=address,undefined -fno-omit-frame-pointer
  LDFLAGS := -fsanitize=address,undefined
endif

SRCS := $(wildcard $(SRC_DIR)/*.c)
OBJS := $(SRCS:$(SRC_DIR)/%.c=$(OUT_DIR)/%.o)
DEPS := $(OBJS:.o=.d)
BIN  := $(OUT_DIR)/$(TARGET)

.PHONY: all debug release run test format clean

all: $(BIN)

debug:
	@$(MAKE) --no-print-directory BUILD=debug

release:
	@$(MAKE) --no-print-directory BUILD=release

$(BIN): $(OBJS)
	$(CC) $(LDFLAGS) $^ -o $@

$(OUT_DIR)/%.o: $(SRC_DIR)/%.c | $(OUT_DIR)
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) -c $< -o $@

$(OUT_DIR):
	@mkdir -p $@

run: $(BIN)
	@$(BIN)

test: $(BIN)
	@./tests/run.sh $(BIN)

format:
	clang-format -i src/*.c src/*.h

clean:
	rm -rf build

-include $(DEPS)
