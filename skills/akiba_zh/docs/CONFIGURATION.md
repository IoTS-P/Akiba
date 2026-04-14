# Akiba 配置文件详解

## 概述

Akiba 使用 JSON 格式配置文件，通过 `-c` 参数指定。配置文件路径格式为 `<文件名>@<JSON路径>`，如 `config.json@main`。

**路径格式说明**：
- `config.json@main` → `config.json` 中 JSON 路径 `/main`
- `@@/MyModule` → 主配置文件中 JSON 路径 `/MyModule`（简写形式）

## 主配置文件结构

### 完整示例

```json
{
  "metadata": {
    "description": "Akiba Test"
  },
  "main": {
    "username": "akiba",
    "password": "akiba",
    "usingInstance": "akiba",
    "globalConsoleLogLevel": "INFO",
    "globalFileLogLevel": "INFO",
    "general": {
      "binariesRoot": "/data/binaries",
      "processor": "n/a",
      "autoAnalysisTimeout": 600,
      "threads": 1
    },
    "withGhidraProject": {
      "projectRoot": "./ghidra_projects",
      "name": "analyzed_base",
      "mode": "new",
      "forkTo": null,
      "continueLog": null,
      "overwriteLog": true,
      "saveProject": true,
      "noCreateProgram": false
    },
    "sqlSource": {
      "serverIP": "127.0.0.1",
      "serverPort": "31777",
      "useSnapshot": "current",
      "constraint": "",
      "disableUpdate": false
    },
    "dbImports": ["test_results"],
    "tasks": [
      {
        "mainClassName": "org.iotsplab.akiba.module.MyModule",
        "configKey": "@@/MyModule",
        "consoleLogLevel": "debug",
        "fileLogLevel": "debug",
        "timeout": 600
      }
    ]
  },
  "MyModule": {
    "configField1": "value1"
  }
}
```

## 配置项详解

### metadata

任务元信息，当前无实际功能，仅用于描述。

```json
"metadata": {
  "description": "任务描述文本"
}
```

### main.username / password

数据库认证凭据。

```json
"username": "akiba",
"password": "akiba"
```

**注意**：当前版本使用默认凭据 `akiba/akiba`。

### main.usingInstance

数据库实例名称，支持多实例管理。

```json
"usingInstance": "akiba"
```

### main.globalConsoleLogLevel / globalFileLogLevel

全局日志级别。

| 可选值 | 说明 |
|-------|------|
| `OFF` | 关闭日志 |
| `TRACE` | 跟踪（最详细） |
| `DEBUG` | 调试 |
| `INFO` | 信息 |
| `WARN` | 警告 |
| `ERROR` | 错误 |

### general

通用配置。

#### general.binariesRoot

二进制文件根目录。导入的文件会复制到此目录并重命名为 `<id>.bin`。

```json
"binariesRoot": "/data/binaries"
```

#### general.processor

缺省处理器架构。设为 `n/a` 时，Akiba 会自动尝试多种常用架构。

```json
"processor": "n/a"
```

#### general.autoAnalysisTimeout

Ghidra 自动分析超时时间（秒）。

```json
"autoAnalysisTimeout": 600
```

#### general.threads

最大并发线程数，即同时分析的二进制文件数量。

```json
"threads": 1
```

### withGhidraProject

Ghidra 项目配置。

#### withGhidraProject.projectRoot

项目文件根目录。

```json
"projectRoot": "./ghidra_projects"
```

#### withGhidraProject.name

项目名称。

```json
"name": "analyzed_base"
```

#### withGhidraProject.mode

项目创建模式：

| 值 | 说明 | 必需配置 |
|---|------|---------|
| `new` | 创建新项目 | - |
| `fork` | 复制已有项目 | `forkTo` |
| `base` | 基于已有项目继续 | `continueLog` |

```json
"mode": "new"
```

#### withGhidraProject.forkTo

当 `mode` 为 `fork` 时，指定新项目名称。

```json
"forkTo": "new_project_name"
```

#### withGhidraProject.continueLog

当 `mode` 为 `base` 时，指定任务日志名。

```json
"continueLog": "continue_log_name"
```

#### withGhidraProject.overwriteLog

是否覆盖已有日志。设为 `false` 时，若日志已存在则拒绝启动。

```json
"overwriteLog": true
```

#### withGhidraProject.saveProject

任务完成后是否保存 Ghidra 项目。设为 `false` 会删除项目文件。

```json
"saveProject": true
```

#### withGhidraProject.noCreateProgram

是否为二进制文件创建 Ghidra Program。设为 `true` 可跳过 Program 创建（如仅需文件熵值计算）。

```json
"noCreateProgram": false
```

### sqlSource

数据库连接配置。

#### sqlSource.serverIP / serverPort

Akiba 数据库守护进程地址。

```json
"serverIP": "127.0.0.1",
"serverPort": "31777"
```

#### sqlSource.useSnapshot

数据库快照选择，当前保留。

```json
"useSnapshot": "current"
```

#### sqlSource.constraint

SQL 约束条件，用于筛选要分析的二进制文件。

```json
"constraint": "WHERE u.ID < 100"
```

实际执行时与 `SELECT u.ID FROM using_binaries u` 拼接。

#### sqlSource.disableUpdate

是否禁用数据库更新。

```json
"disableUpdate": false
```

### dbImports

导入其他模块的输出数据。

```json
"dbImports": ["test_results"]
```

数据访问格式：`数据名.列名`，如 `test_results.function_number`

### tasks

任务配置数组，每个任务对应一个模块。

#### tasks[].mainClassName

模块主类完整路径。类必须继承 `AkibaModule`，文件以 `amod` 开头。

```json
"mainClassName": "org.iotsplab.akiba.module.MyModule"
```

#### tasks[].configKey

模块配置文件路径。

```json
"configKey": "@@/MyModule"
```

#### tasks[].consoleLogLevel / fileLogLevel

任务级日志级别，覆盖全局设置。

```json
"consoleLogLevel": "debug",
"fileLogLevel": "debug"
```

#### tasks[].timeout

任务超时时间（秒），超时后任务被取消。

```json
"timeout": 600
```

## 导入配置文件

`import-example.json` 用于批量导入二进制文件：

```json
{
  "entries": [
    {
      "path": "firmware/nxp_device.bin",
      "arch": "ARM:LE:32:v8",
      "custom_field": "value"
    }
  ]
}
```

| 字段 | 必填 | 说明 |
|-----|------|------|
| `path` | 是 | 相对于 `binariesRoot` 的路径 |
| `arch` | 否 | 指定处理器架构 |
| 其他字段 | 否 | 保存到 `global_data` |

## 日志配置

`log4j2.xml` 控制日志格式：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Configuration status="WARN">
    <Properties>
        <Property name="consolePattern">
             %msg%n
        </Property>
    </Properties>
    <Appenders>
        <Console name="Console" target="SYSTEM_OUT">
            <PatternLayout pattern="%d %highlight{%-5level}{ERROR=Bright RED, WARN=Bright Yellow, INFO=Bright Green, DEBUG=Bright Cyan, TRACE=Bright White} %style{[%t]}{bright,magenta} %style{%c{1.}.%M(%L)}{cyan}: %msg%n"/>
        </Console>
    </Appenders>
    <Loggers>
        <Root level="info">
            <AppenderRef ref="Console"/>
        </Root>
    </Loggers>
</Configuration>
```

## 启动命令

```bash
# 使用默认配置
./gradlew run

# 指定配置文件
./gradlew run --args="-c config.json@main"
```

## 配置路径简写

主配置文件与模块配置可写在同一文件：

```json
{
  "main": { /* 主配置 */ },
  "MyModule": { /* 模块配置 */ }
}
```

引用时使用 `@@/MyModule` 简写。
