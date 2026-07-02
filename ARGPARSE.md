# argparse — 命令行参数解析库

轻量级命令行参数解析器，支持位置参数、选项、别名和自动生成帮助信息。

## API

### `ArgumentParser` 类

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `program_name` | `string` | `"PROGRAM"` | 程序名称（显示在帮助信息中） |
| `description` | `string` | `null` | 程序描述（显示在帮助信息末尾） |
| `indent` | `int` | `4` | 帮助信息缩进空格数 |

### 方法

#### `add_argument(key, required, help_text)`

添加位置参数。

| 参数 | 类型 | 说明 |
|------|------|------|
| `key` | `string` | 参数名称（不能包含 `-`） |
| `required` | `boolean` | 是否必选 |
| `help_text` | `string` | 帮助说明 |

返回 `this`，支持链式调用。

#### `add_option(key, store, required, help_text)`

添加选项。

| 参数 | 类型 | 说明 |
|------|------|------|
| `key` | `string` | 选项名称（必须包含 `-`，如 `--port`） |
| `store` | `boolean` | `true` 为布尔开关（无需值），`false` 为键值对 |
| `required` | `boolean` | 是否必选 |
| `help_text` | `string` | 帮助说明 |

返回 `this`，支持链式调用。

#### `set_defaults(key, val)`

设置参数/选项的默认值。

| 参数 | 类型 | 说明 |
|------|------|------|
| `key` | `string` | 参数或选项名称 |
| `val` | `any` | 默认值 |

返回 `this`，支持链式调用。

#### `set_option_alias(key, alias)`

为选项设置别名。

| 参数 | 类型 | 说明 |
|------|------|------|
| `key` | `string` | 原选项名称 |
| `alias` | `string` | 别名（如 `-h`） |

返回 `this`，支持链式调用。

#### `parse_args(args)`

解析命令行参数。

| 参数 | 类型 | 说明 |
|------|------|------|
| `args` | `array` | 命令行参数数组（`context.cmd_args`） |

返回 `hash_map`，键为参数/选项名称（去掉 `-` 前缀），值为解析结果。

如果指定了 `--help`，会打印帮助信息并退出。

#### `print_help()`

打印帮助信息到标准输出。

## 使用示例

### 基本用法

```covscript
import argparse

var parser = new argparse.ArgumentParser
parser.program_name = "my_tool"
parser.description = "A simple tool"

parser.add_argument("input", true, "Input file path")
parser.add_argument("output", false, "Output file path")
parser.set_defaults("output", "out.txt")

parser.add_option("--verbose", true, false, "Enable verbose output")
parser.set_option_alias("--verbose", "-v")

parser.add_option("--port", false, true, "Port number")
parser.set_defaults("--port", 8080)
parser.set_option_alias("--port", "-p")

var args = parser.parse_args(context.cmd_args)

system.out.println("Input: " + args.input)
system.out.println("Output: " + args.output)
system.out.println("Verbose: " + args.verbose)
system.out.println("Port: " + args.port)
```

### 运行效果

```
$ my_tool input.txt -v -p 9090
Input: input.txt
Output: out.txt
Verbose: true
Port: 9090
```

### 帮助信息

```
$ my_tool --help
Usage: my_tool input [output=out.txt] [--verbose] [-p 8080]

Arguments:
    input                                   Input file path
    [output=out.txt]                        Output file path
    [--verbose, -v]                         Enable verbose output
    [--port 8080, -p]                       Port number

A simple tool
```

## 选项类型

### 布尔开关（store = true）

无需值，出现即生效。例如 `--verbose`：

```covscript
parser.add_option("--verbose", true, false, "Verbose mode")
```

命令行：`--verbose` → `args.verbose = true`

### 键值对（store = false）

需要一个值。例如 `--port 8080`：

```covscript
parser.add_option("--port", false, false, "Port number")
parser.set_defaults("--port", 8080)
```

命令行：`--port 9090` → `args.port = 9090`

## 错误处理

| 情况 | 异常信息 |
|------|---------|
| 位置参数名称包含 `-` | `ArgumentParser: arguments can not contains "-"` |
| 选项名称不包含 `-` | `ArgumentParser: options must contains "-"` |
| 未定义的选项 | `ArgumentParser: option "xxx" not supported.` |
| 参数过多 | `ArgumentParser: too much arguments.` |
| 必选参数缺失 | `ArgumentParser: argument "xxx" required.` |
| 必选选项缺失 | `ArgumentParser: option "xxx" required.` |
