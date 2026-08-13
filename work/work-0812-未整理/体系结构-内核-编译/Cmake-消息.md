
<think>
我们注意到用户的问题是关于CMake的`message`命令，特别是除了`STATUS`之外的其他选项。
 根据CMake文档，`message`命令有多个模式（mode）参数，用于控制消息的类型和显示方式。

 以下是常见的模式选项：
 1. `(none)` 或 `STATUS`：用于信息性消息。
 2. `WARNING`：显示警告消息，会继续执行。
 3. `AUTHOR_WARNING`：类似警告，但默认不显示（需开启`CMAKE_SUPPRESS_DEVELOPER_WARNINGS`）。
 4. `SEND_ERROR`：产生错误，继续处理，但跳过生成步骤。
 5. `FATAL_ERROR`：立即终止所有处理过程。
 6. `DEPRECATION`：如果启用了`CMAKE_ERROR_DEPRECATED`或`CMAKE_WARN_DEPRECATED`，则相应地处理。

 此外，还有`NOTICE`（CMake 3.15+）和`VERBOSE`（CMake 3.15+）等模式。

 因此，回答用户问题：除了`STATUS`，还有`WARNING`、`SEND_ERROR`、`FATAL_ERROR`等选项。

 下面给出一个使用示例：
</think>
在CMake中，`message()`命令支持多种消息类型（模式），除了`STATUS`外，常用的还有以下几种：

### 完整的message()模式列表：

| **模式** | **说明** | **终端显示效果** | **是否中断构建** |
|----------|-----------|------------------|------------------|
| `STATUS` | 状态信息 | 以 `--` 开头 | ❌ 不中断 |
| `VERBOSE` | 详细输出 (CMake 3.15+) | 默认不显示，需开启`CMAKE_MESSAGE_VERBOSE` | ❌ 不中断 |
| `DEBUG` | 调试信息 (CMake 3.17+) | 默认不显示，需开启`CMAKE_MESSAGE_LOG_LEVEL` | ❌ 不中断 |
| `TRACE` | 详细跟踪信息 (CMake 3.25+) | 默认不显示 | ❌ 不中断 |
| `WARNING` | **警告信息** | 黄色/高亮显示 | ❌ 不中断 |
| `AUTHOR_WARNING` | 开发者警告 | 类似警告 | ❌ 不中断 |
| `SEND_ERROR` | **可恢复错误** | 红色/高亮显示 | ❌ 继续构建但跳过生成 |
| `FATAL_ERROR` | **致命错误** | 红色/高亮显示 | ✅ 立即终止构建 |
| `DEPRECATION` | 弃用警告 | 根据策略显示 | ❌ 不中断 |
| `NOTICE` | 重要通知 (CMake 3.15+) | 普通显示 | ❌ 不中断 |

### 使用示例：
```cmake
message(STATUS "配置信息: ${PROJECT_NAME}")     # 状态信息
message(VERBOSE "详细编译参数: ${CMAKE_CXX_FLAGS}") # 仅在详细模式显示
message(WARNING "过时的功能将被移除!")          # 黄色警告
message(SEND_ERROR "无效的配置参数!")           # 错误但继续
message(FATAL_ERROR "不支持的平台!")            # 立即终止
```

### 高级用法：
1. **条件消息**：
   ```cmake
   if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
     message(STATUS "Linux平台检测通过")
   else()
     message(FATAL_ERROR "仅支持Linux平台")
   endif()
   ```

2. **带颜色输出**（CMake 3.18+）：
   ```cmake
   message(COLOR CYAN "重要提示: 使用GCC 12+编译器")
   ```

3. **日志级别控制**：
   ```bash
   cmake -DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE ..
   ```

### 最佳实践：
1. 使用`STATUS`显示常规进度信息
2. 用`WARNING`代替`SEND_ERROR`除非需要阻止生成步骤
3. 使用`FATAL_ERROR`处理不可恢复的错误
4. 为调试信息添加`VERBOSE`模式避免干扰正常输出

根据您的需求选择合适的消息级别，可以有效控制构建输出的信息量和严重程度。
