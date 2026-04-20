# Akiba 模块开发指南

本指南基于 `subprojects/akiba_mod_example/usages_zh/AkibaExample.md` 编写，涵盖模块开发的核心流程、常用 API 和最佳实践。

## 概述

Akiba 模块是框架的可拆卸组件，使用 Kotlin 开发，支持 Maven 库导入、模块间依赖、数据持久化和多线程批量处理。

**适用场景**：
- 开发自定义二进制分析功能
- 封装可复用的分析流程
- 与其他模块共享数据

## 注意事项

若配置文件 akiba_config.json 中 `akiba.home` 为 `null`，则需要首先拉取  Akiba 仓库并将 ghidra.jar 移动到正确位置（参见 SKILL.md 中的相关说明）。对于模块开发而言，只需要拉取子模块 `subprojects/akiba\_framework` 和 `subprojects/akiba\_mod\_example` 即可，并可在 `subprojects/akiba\_mod\_example` 的基础上开发新模块。

模块开发完成后，在 Akiba 主源代码仓库根目录中运行 `./gradlew akiba_mod_example:<你的模块主类名>` 验证模块能否成功构建，构建成功的模块将保存于 `subprojects/akiba_mod_example/build/libs` 中。

## 模块主类

### 继承 AkibaModule

模块主类必须继承 `org.iotsplab.akiba.module.AkibaModule`：

```kotlin
abstract class AkibaModule (
    private val configPath: String? = null,
    private val defaultConfig: Any? = null,
    val id: Int = -1,
    protected val program: Program? = null,
    consoleLogLevel: Level = Level.INFO,
    fileLogLevel: Level = Level.INFO,
    tableName: String? = null,
)
```

**参数说明**：

| 参数 | 类型 | 说明 |
|-----|------|------|
| `configPath` | String? | 配置文件路径，格式：`<文件名>@<JSON路径>` |
| `id` | Int | 二进制文件唯一 ID |
| `program` | Program? | Ghidra Program 上下文 |
| `consoleLogLevel` | Level | 控制台日志级别，默认 INFO |
| `fileLogLevel` | Level | 文件日志级别，默认 INFO |
| `tableName` | String? | 数据表名 |

### 注解类

| 注解 | 作用 |
|-----|------|
| `@WithConfigClass` | 指定配置类 |
| `@WithTableColumn` | 定义数据表列 |
| `@WithView` | 创建数据视图 |
| `@IgnoreRuntimeTimeout` | 忽略任务超时限制 |
| `@FailOnCancelled` | 超时后判定为失败 |
| `@DoNotCreateTable` | 不创建数据表 |
| `@PureDependency` | 纯依赖模块（不运行但可被调用） |

## 入口方法

模块逻辑在 `startProcess()` suspend 函数中实现：

```kotlin
override suspend fun startProcess() {
    try {
        val metadata = getMetadata()
        logger.info("Processing file: ${metadata.originalPath}")
        
        val result = analyze()
        updateData(mapOf("result" to result))
    } catch (e: Exception) {
        logger.error("Analysis failed: ${e.message}")
        updateErr("Analysis failed: ${e.message}")
    }
}
```

## 常用 API

### 数据操作

```kotlin
// 临时数据（流水线内存）
suspend fun getTaskData(key: String?): Any?
suspend fun setTaskData(key: String, value: Any?)

// 持久化数据
protected fun updateData(data: Map<String, Any?>)
protected fun updateErr(msg: String)
protected fun clearErr()

// 元数据
suspend fun getMetadata(): BinaryMetadata
```

### BinaryMetadata

```kotlin
data class BinaryMetadata(
    val id: Int,                      // 文件 ID
    val originalPath: String,         // 原始路径
    val processedPath: String?,       // 处理后路径
    val arch: String?,                 // 处理器架构
    val format: String?,               // 文件格式（ELF、PE 等）
    val compilerSpec: String?,          // 编译器规范
    val checksum: String,              // MD5 校验和
    val processedChecksum: String?     // 处理后校验和
)
```

### 文件操作

```kotlin
// 从模块 JAR 中提取文件
protected fun extractFileInJar(inPath: String, outPath: Path)
```

## 数据表结构

### 默认列

每个模块数据表包含 5 列保留列：

| 列名 | 类型 | 说明 |
|-----|------|------|
| `id` | integer | 二进制文件 ID |
| `start_timestamp` | timestamptz | 任务开始时间 |
| `finish_timestamp` | timestamptz | 任务结束时间 |
| `execute_time` | interval | 执行耗时 |
| `err_msg` | text | 错误信息 |

### 自定义列

使用 `@WithTableColumn` 定义：

```kotlin
@WithTableColumn("function_count", "integer")
@WithTableColumn("strings", "JSONB")
class MyModule(...) : AkibaModule(...) {
    // 数据表将包含：id, start_timestamp, finish_timestamp, execute_time, err_msg, function_count, strings
}
```

**支持的数据类型**：

| 类型 | 说明 |
|-----|------|
| `integer`, `bigint` | 整数 |
| `double precision` | 浮点数 |
| `text` | 文本 |
| `timestamptz` | 时间戳 |
| `interval` | 时间间隔 |
| `boolean` | 布尔值 |
| `jsonb` | JSON 对象 |
| `bytea` | 二进制数据 |

## 模块 API

### 暴露 API

使用 `@TaskInterface` 注解暴露方法：

```kotlin
class ProviderModule(...) : AkibaModule(...) {
    @TaskInterface
    fun getAnalysisResult(): String = "result_data"
}
```

### 调用 API

使用 `callTaskAPI()` 调用：

```kotlin
class ConsumerModule(...) : AkibaModule(...) {
    suspend fun process() {
        val result = callTaskAPI(ProviderModule::getAnalysisResult)
        logger.info("Received: $result")
    }
}
```

**注意**：流水线作用域内，同一 ID 的模块实例共享 API 调用。

## 开发流程

### 1. 创建模块类

```kotlin
package org.iotsplab.akiba.module

import ghidra.program.model.listing.Program
import org.apache.logging.log4j.Level
import org.iotsplab.akiba.module.AkibaModule
import org.iotsplab.akiba.utils.WithTableColumn

@WithTableColumn("analysis_result", "TEXT")
class MyAnalyzer(
    configPath: String? = null,
    id: Int,
    program: Program,
    consoleLogLevel: Level = Level.INFO,
    fileLogLevel: Level = Level.INFO,
    tableName: String? = "my_analyzer_results"
) : AkibaModule(
    configPath = configPath,
    id = id,
    program = program,
    consoleLogLevel = consoleLogLevel,
    fileLogLevel = fileLogLevel,
    tableName = tableName
) {
    override suspend fun startProcess() {
        val programContext = program!!
        
        // 1. 获取元数据
        val metadata = getMetadata()
        
        // 2. 执行分析
        val result = performAnalysis(programContext)
        
        // 3. 保存结果
        updateData(mapOf("analysis_result" to result))
    }
    
    private fun performAnalysis(program: Program): String {
        // 实现分析逻辑
        return "analysis complete"
    }
}
```

### 2. 配置任务

在 `config.json` 中添加：

```json
{
  "main": {
    "tasks": [
      {
        "mainClassName": "org.iotsplab.akiba.module.MyAnalyzer",
        "configKey": "@@/MyAnalyzer",
        "consoleLogLevel": "debug",
        "fileLogLevel": "debug",
        "timeout": 600
      }
    ]
  },
  "MyAnalyzer": {}
}
```

### 3. 打包部署

模块文件以 `amod` 开头命名，保存到项目 `modules` 目录。

## 二进制文件剪切

Akiba 自动处理固件中的大段空字节（`\x00`），将文件切片保存到 `load_properties` 字段：

```json
{"oldOffset": 1000000, "newOffset": 0, "length": 1024}
```

**注意**：对于 ELF、PE 等标准格式文件，Akiba 不会执行剪切操作。

## 参考资料

- [Akiba 官方仓库](https://github.com/IoTS-P/Akiba)
- [Akiba 模块示例仓库](https://github.com/IoTS-P/Akiba-Mod-Example)
- [Akiba 数据库守护进程](https://github.com/IoTS-P/Akiba-DB-Daemon)
