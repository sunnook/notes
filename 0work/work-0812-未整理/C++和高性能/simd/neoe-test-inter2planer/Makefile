
OPT_LEVEL ?= -O2
VECT_FLAG ?= -fno-tree-vectorize

# aarch64-linux-gnueabihf-f5plus-objdump -d -S build/inter2planer.o > inter2planer_O3.asm
# 提取 inter2plan0 的汇编代码
# sed -n '/<priv_ao_copy_inter2plan0>:/,/^$/p' inter2planer_O3.asm > inter2plan0_only.asm

# make clean
# make OPT_LEVEL=-O0 VECT_FLAG=
# mv app app-O0-

# make clean
# make OPT_LEVEL=-O2 VECT_FLAG=-fno-tree-vectorize
# mv app app-O2-fno

# make clean
# make OPT_LEVEL=-O3 VECT_FLAG=-ftree-vectorize
# mv app app-O3-ftree

# make clean
# make OPT_LEVEL=-O3 VECT_FLAG=-fno-tree-vectorize
# mv app app-O3-fno

# ==============================================================================
# 编译器与编译选项配置
# ==============================================================================
CC := aarch64-linux-gnueabihf-f5plus-gcc
CXX := aarch64-linux-gnueabihf-f5plus-g++

# 编译选项
BUILD_OPERATION := -march=armv8-a -g $(OPT_LEVEL) $(VECT_FLAG) -mtune=cortex-a53 -fno-builtin -fno-common -Wformat=1

# C 和 C++ 共享编译选项，并添加头文件依赖生成选项 (-MMD -MP)
CFLAGS := $(BUILD_OPERATION) -MMD -MP -Wall
CXXFLAGS := $(BUILD_OPERATION) -MMD -MP -Wall

# 链接选项
LDFLAGS := 

# 需要链接的库 (例如：-lpthread -lm)
LDLIBS := 

# ==============================================================================
# 项目目录与文件配置 (请根据实际情况修改)
# ==============================================================================
# 源文件目录 (可以写多个目录，用空格隔开)
SRC_DIR := src

# 输出可执行文件名称
TARGET := app

# 中间文件存放目录
BUILD_DIR := build

# ==============================================================================
# 以下为自动推导部分，一般无需修改
# ==============================================================================
# 递归查找所有 .c 和 .cpp 文件
C_SRCS := $(shell find $(SRC_DIR) -name '*.c')
CXX_SRCS := $(shell find $(SRC_DIR) -name '*.cpp')

# 将源文件路径替换为对应的 .o 目标文件路径
C_OBJS := $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(C_SRCS))
CXX_OBJS := $(patsubst $(SRC_DIR)/%.cpp,$(BUILD_DIR)/%.o,$(CXX_SRCS))
OBJS := $(C_OBJS) $(CXX_OBJS)

# 自动生成的依赖文件
DEPS := $(OBJS:.o=.d)

# 默认目标
.PHONY: all clean

all: $(TARGET)

# 链接生成最终可执行文件
$(TARGET): $(OBJS)
	@mkdir -p $(dir $@)
	$(CXX) $(LDFLAGS) $^ -o $@ $(LDLIBS)

# 编译 C 文件
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

# 编译 C++ 文件
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -c $< -o $@

# 清理编译产物
clean:
	rm -rf $(BUILD_DIR) $(TARGET)

# 引入头文件依赖
-include $(DEPS)
