---
name: akiba-zh
description: Akiba 二进制分析框架使用与开发指南 - 基于 Ghidra 和 Kotlin 的批量流水线式分析框架，适用于大规模固件和二进制文件分析
author: Akiba Team
version: 1.0.0
---

## 技能概述

Akiba 是一个基于 Ghidra 的支持批量流水线任务的二进制分析框架，使用 Kotlin 开发，设计用于大规模批量化二进制分析场景。

**核心价值**：
- 多线程流水线并行处理，提升分析效率
- 模块化设计，支持自定义分析流程
- 数据库存储分析结果，支持数据查询和导出
- 断点续传机制，保障长时间任务稳定性

**适用人群**：二进制安全研究人员、固件分析师、逆向工程师

**不包含**：Ghidra 基础操作教学、Kotlin/Java 编程入门、二进制分析理论知识

## 使用场景

- 场景1：需要批量分析大量固件或二进制样本（如 IoT 设备固件、恶意软件家族分析）
- 场景2：需要开发自定义分析模块并集成到 Akiba 流水线中
- 场景3：需要持久化保存分析结果到数据库，支持后续查询和比对
- 场景4：需要运行耗时较长的分析任务（如静态分析、符号执行），需要断点续传保障
- 场景5：需要为不同二进制文件配置差异化的分析流水线

## 核心内容

### 1. 定位 Akiba 安装

**重要**：在使用 Akiba 之前，必须先读取配置文件。

```bash
# 读取配置文件
cat skills/akiba_zh/akiba_config.json
```

配置文件说明：

| 字段 | 说明 |
|-----|------|
| `akiba.home` | Akiba 主仓库路径 |
| `akiba.repoUrl` | Akiba 仓库地址（不存在时使用） |
| `modExample.repoUrl` | 模块开发示例仓库地址 |
| `framework.runCommand` | 运行 Akiba Framework 的完整命令 |
| `daemon.host` / `daemon.port` | 数据库守护进程地址 |

**验证服务**：

```bash
# 检查 daemon 是否运行
curl -s "http://127.0.0.1:31777/test"
```

### 2. 环境准备

#### 系统依赖

| 依赖项 | 版本要求 | 说明 |
|-------|---------|------|
| Java | 21+ | 必须使用 JDK 21，低版本会导致运行时错误 |
| Kotlin | 2.1.20+ | 框架开发语言 |
| Ghidra | 11.3.2 | 二进制分析引擎（其他版本 API 不兼容） |
| PostgreSQL | 最新稳定版 | 数据存储，由数据库守护进程管理 |

#### 初始化步骤

```bash
# 1. 设置 Java 环境
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64

# 2. 初始化 Git 子模块
git submodule update --init --recursive

# 3. Docker 部署（推荐）
docker compose up --build
```

### 3. 核心概念

#### 流水线架构

Akiba 为每个二进制文件启动独立的任务流水线：

```
Akiba 启动 → 初始化 → 全局预处理任务
                            ↓
        线程1: 流水线A（模块1 → 模块2 → 模块3）
        线程2: 流水线B（模块1 → 模块2 → 模块3）
        线程3: 流水线C（模块1 → 模块2 → 模块3）
```

- 最大并行数量由 `config.json` 的 `general.threads` 配置
- 不同文件的模块数据互相隔离
- 相同文件的处理模块串行运行

#### 协程上下文

Akiba 为每个任务创建 2 个协程上下文：

| 上下文类型 | 访问权限 | 用途 |
|-----------|---------|------|
| 全局作用域 | 所有任务可访问 | 全局预处理、全局 API |
| 流水线作用域 | 该流水线内任务可访问 | 二进制专属数据、任务 API |

#### 数据处理

| 数据类型 | 存储位置 | 访问方式 |
|---------|---------|---------|
| 全局数据 | `results` 表的 `global_data` 列（JSON） | 模块间共享 |
| 临时数据 | 流水线内存 HashMap | `getTaskData()`/`setTaskData()` |
| 任务专用数据 | 自定义数据表列 | `updateData()` |

### 4. 配置文件详解

详细配置说明参见 `docs/CONFIGURATION.md`，核心配置结构：

```json
{
  "main": {
    "username": "akiba",
    "password": "akiba",
    "usingInstance": "akiba",
    "general": {
      "binariesRoot": "/data/binaries",
      "threads": 1,
      "autoAnalysisTimeout": 600
    },
    "withGhidraProject": {
      "projectRoot": "./ghidra_projects",
      "name": "project_name",
      "mode": "new"
    },
    "sqlSource": {
      "serverIP": "127.0.0.1",
      "serverPort": "31777"
    },
    "tasks": [
      {
        "mainClassName": "org.iotsplab.akiba.module.MyModule",
        "configKey": "@@/MyModule",
        "timeout": 600
      }
    ]
  }
}
```

### 5. 模块开发

详细开发规范参见 `docs/MODULE_DEVELOPMENT.md`，核心开发步骤：

1. **创建模块类**：继承 `AkibaModule`，使用 `@WithTableColumn` 定义数据列
2. **实现入口方法**：在 `startProcess()` 中编写分析逻辑
3. **保存结果**：通过 `updateData()` 写入数据库
4. **配置任务**：在 `config.json` 中注册模块

```kotlin
@WithTableColumn("result", "TEXT")
class MyModule(
    id: Int,
    program: Program,
    consoleLogLevel: Level = Level.INFO,
    fileLogLevel: Level = Level.INFO,
    tableName: String? = "my_module_results"
) : AkibaModule(
    id = id,
    program = program,
    consoleLogLevel = consoleLogLevel,
    fileLogLevel = fileLogLevel,
    tableName = tableName
) {
    override suspend fun startProcess() {
        val result = analyzeProgram()
        updateData(mapOf("result" to result))
    }
}
```

### 6. 日志管理

Akiba 按二进制文件和模块分离保存日志：

```
<log root>/
├── Root.log                    # 根日志
├── config.json                 # 任务配置
├── <failed>/                   # 失败任务
│   └── <binary_id>/
│       └── ModuleName.log
├── <runtime_error>/            # 运行时错误
└── <success>/                  # 成功任务
```

断点续传使用 `starter.py` 监控，日志 20 分钟无更新时自动重启：

```bash
python3 starter.py &
```

### 7. 常见问题

#### Q1: 任务超时怎么办？

- 在 `config.json` 中增大对应任务的 `timeout` 值
- 如需无限制超时，添加 `@IgnoreRuntimeTimeout` 注解

#### Q2: 如何调试模块？

设置日志级别为 `debug`：

```json
{
  "consoleLogLevel": "debug",
  "fileLogLevel": "debug"
}
```

#### Q3: 数据库连接失败？

检查数据库守护进程是否运行：

```bash
curl http://localhost:31777/test
```

## 示例

### 示例1：Docker 部署

```bash
git clone https://github.com/IoTS-P/Akiba.git
cd Akiba
git submodule update --init --recursive
docker compose up --build
```

### 示例2：配置并运行分析任务

1. 编辑 `config.json` 配置任务
2. 确保数据库守护进程运行在 `127.0.0.1:31777`
3. 启动分析：

```bash
./gradlew run --args="-c config.json@main"
```

### 示例3：开发自定义模块

参考 `subprojects/akiba_mod_example/usages_zh/AkibaExample.md`

## 注意事项

1. **版本兼容性**：Ghidra 11.3.2 是当前唯一兼容版本，其他版本可能导致 API 不兼容
2. **Java 版本**：必须使用 JDK 21，设置 `JAVA_HOME` 环境变量
3. **子模块**：首次克隆后必须执行 `git submodule update --init --recursive`
4. **数据库认证**：当前默认凭据为 `akiba/akiba`
5. **API 作用域**：流水线 API 只能被该流水线的后续任务调用
6. **协程安全**：避免在协程中使用 Java `ReentrantLock`，改用 `Mutex`

## 拓展说明

### 相关文档

| 文档 | 说明 |
|-----|------|
| `akiba_config.json` | 全局配置 - 定位 Akiba 安装和数据库连接信息 |
| `REFERENCE.md` | 快速参考卡片 - 包含完整命令、路径速查和配置模板 |
| `docs/CONFIGURATION.md` | config.json 配置文件完整说明 |
| `docs/MODULE_DEVELOPMENT.md` | Akiba 模块开发规范 |
| `subprojects/akiba_framework/Usage_guide_zh.md` | 框架使用指南 |
| `subprojects/akiba_framework/README_zh.md` | 框架 README - 包含子命令说明 |
| `subprojects/akiba_db_daemon/Usage_guide_zh.md` | 数据库守护进程 API |

### 外部资源

- [Akiba 官方仓库](https://github.com/IoTS-P/Akiba)
- [Akiba 模块示例仓库](https://github.com/IoTS-P/Akiba-Mod-Example)
- [Akiba 数据库守护进程](https://github.com/IoTS-P/Akiba-DB-Daemon)
- [Ghidra 官方文档](https://ghidra-sre.org/)
