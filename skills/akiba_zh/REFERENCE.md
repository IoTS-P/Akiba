---
name: akiba-zh-reference
description: Akiba 框架快速参考卡片 - 包含完整的命令、路径和配置模板，方便在任何目录下快速查阅和使用 Akiba
author: Akiba Team
version: 1.0.0
---

## 概述

本文档提供 Akiba 项目的快速参考信息，包括命令、路径和常用配置模板。适合作为日常使用的速查手册。

## 路径速查

### Akiba 项目根目录

在 Docker 中默认不存在，需要从 Github https://github.com/IoTS-P/Akiba.git 克隆并拉取子模块并按照[快速启动 Checklist](#快速启动-checklist)中的[基于源代码仓库](#基于源代码仓库)的方式获取 ghidra.jar 并保存到正确位置。

### 核心子项目

| 子项目 | 路径 |
|-------|------|
| Akiba Framework | `subprojects/akiba_framework/` |
| Akiba DB Daemon | `subprojects/akiba_db_daemon/` |
| Akiba Modules | `subprojects/akiba_modules/` |
| Akiba Mod Examples | `subprojects/akiba_mod_example/` |

### 构建产物

| 产物 | 路径                                                                         |
|-----|----------------------------------------------------------------------------|
| Akiba Framework JAR | `subprojects/akiba_framework/build/libs/akiba_framework-<版本>.jar`          |
| Akiba Framework ZIP | `subprojects/akiba_framework/build/distributions/akiba_framework-<版本>.zip` |
| 启动脚本 (Linux) | Akiba Framework ZIP 中的 `/bin/akiba_framework`                              |
| 启动脚本 (Windows) | Akiba Framework ZIP 中的 `/bin/akiba_framework.bat`                          |

### 配置文件目录

| 用途 | 路径 |
|-----|------|
| Framework 配置 | `subprojects/akiba_framework/src/main/resources/configs/` |
| DB Daemon 配置 | `subprojects/akiba_db_daemon/src/main/resources/` |
| 示例配置 | `dockerfile_needed/config_example.json` |

## 环境要求

| 依赖 | 版本 | 说明                               |
|-----|------|----------------------------------|
| Java | 21+ | 必须设置 `JAVA_HOME`                 |
| Kotlin | 2.1.20+ |                                  |
| Ghidra | 11.3.2 | 需要构建 ghidra.jar（构建方法见`SKILL.md`） |
| PostgreSQL | 最新稳定版 | 由 DB Daemon 管理                   |

## 编译构建

### 编译特定组件

```bash
# 仅编译 Framework
./gradlew :subprojects:akiba_framework:assemble

# 仅编译 DB Daemon
./gradlew :subprojects:akiba_db_daemon:assemble
```

### 打包发布

```bash
./gradlew :subprojects:akiba_framework:distZip
# 输出: subprojects/akiba_framework/build/distributions/Akiba-<版本>.zip
```

### 解压运行包

```bash
cd subprojects/akiba_framework/build/distributions
unzip Akiba-<版本>.zip
cd Akiba-<版本>
```

## 数据库守护程序

### 启动 DB Daemon

**方式一：Docker 启动（推荐）**

```bash
cd /media/colin/white_pass/NEED_BACKUP/Firmwares/Akiba
docker compose up --build
```

**方式二：直接启动**

```bash
cd /media/colin/white_pass/NEED_BACKUP/Firmwares/Akiba/subprojects/akiba_db_daemon
./gradlew :subprojects:akiba_db_daemon:run
# 或指定配置
./gradlew :subprojects:akiba_db_daemon:run --args="-c /path/to/config.json"
```

### DB Daemon 配置

配置文件位置：`subprojects/akiba_db_daemon/src/main/resources/config.json`

```json
{
  "consoleLogLevel": "INFO",
  "fileLogLevel": "DEBUG",
  "dbUserName": "test",
  "dbPassword": "test123",
  "dbName": "akiba"
}
```

### DB Daemon API

下面仅有部分常用接口，更多接口请查看 [daemon 使用文档](https://IoTS-P/Akiba-DB-Daemon/Usage_guide_zh.md)。

| 接口 | 方法 | 说明 |
|-----|------|------|
| `http://127.0.0.1:31777/test` | GET | 健康检查 |
| `http://127.0.0.1:31777/instance/login` | POST | 用户登录 |
| `http://127.0.0.1:31777/instance/connect` | POST | 连接数据库实例 |
| `http://127.0.0.1:31777/module/start` | POST | 标记任务开始 |
| `http://127.0.0.1:31777/module/update` | POST | 更新任务数据 |
| `http://127.0.0.1:31777/module/finish` | POST | 标记任务完成 |

### DB Daemon 实例管理

```bash
# 创建实例
./bin/akiba_framework instance-create -n <实例名> -u <用户名> -H 127.0.0.1 -p 31777

# 启动实例
./bin/akiba_framework instance-start -i <实例名> -u <用户名> -H 127.0.0.1 -p 31777

# 关闭实例
./bin/akiba_framework instance-shutdown -i <实例名> -u <用户名> -H 127.0.0.1 -p 31777

# 删除实例
./bin/akiba_framework instance-delete -i <实例名> -u <用户名> -H 127.0.0.1 -p 31777

# 备份实例
./bin/akiba_framework instance-backup -i <实例名> -t full -u <用户名> -H 127.0.0.1 -p 31777

# 恢复实例
./bin/akiba_framework instance-restore -n <新实例名> -l <备份标签> -u <用户名> -H 127.0.0.1 -p 31777
```

## 分析任务运行

### 启动分析（正常模式）

```bash
# /home/akiba/akiba_framework 是 Akiba Docker 中 Akiba Framework 的固定路径
cd /home/akiba/akiba_framework
./bin/akiba_framework -c config.json@/main
```

### 导入文件模式

```bash
cd /home/akiba/akiba_framework
./bin/akiba_framework -i /path/to/import-example.json -c config.json@/main # 仍然需要指定 config.json 以确定数据库地址等配置
```

### 断点续传模式

```bash
cd /home/akiba/akiba_framework

# 继续最新任务
./bin/akiba_framework -r latest

# 继续指定时间戳的任务
./bin/akiba_framework -r 20250201140000

# 仅重试失败任务
./bin/akiba_framework -r latest -f

# 仅重试报错任务
./bin/akiba_framework -r latest -e
```

## 配置模板

### 完整任务配置 (config.json)

```json
{
  "metadata": {
    "description": "分析任务描述"
  },
  "main": {
    "username": "akiba",
    "password": "akiba",
    "usingInstance": "akiba",
    "globalConsoleLogLevel": "INFO",
    "globalFileLogLevel": "DEBUG",
    "general": {
      "binariesRoot": "/data/binaries",
      "importRoot": "/data/binaries",
      "processor": "n/a",
      "autoAnalysisTimeout": 600,
      "threads": 4
    },
    "withGhidraProject": {
      "projectRoot": "./ghidra_projects",
      "name": "my_project",
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
    "dbImports": [],
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
    "param1": "value1"
  }
}
```

### 导入配置 (import-example.json)

```json
{
  "entries": [
    {
      "path": "firmware/device.bin",
      "arch": "ARM:LE:32:v8",
      "customField": "customValue"
    }
  ]
}
```

### 任务配置说明

| 配置项 | 必填 | 说明 |
|-------|------|------|
| `main.username` | 是 | 数据库用户名，默认 `akiba` |
| `main.password` | 是 | 数据库密码，默认 `akiba` |
| `main.usingInstance` | 是 | 数据库实例名 |
| `general.binariesRoot` | 是 | 二进制文件根目录 |
| `general.threads` | 否 | 并发数，默认 1 |
| `general.autoAnalysisTimeout` | 否 | Ghidra 分析超时（秒） |
| `sqlSource.serverIP` | 否 | DB Daemon 地址，默认 `127.0.0.1` |
| `sqlSource.serverPort` | 否 | DB Daemon 端口，默认 `31777` |
| `tasks[].mainClassName` | 是 | 模块主类全路径 |
| `tasks[].configKey` | 是 | 模块配置路径 |
| `tasks[].timeout` | 否 | 任务超时（秒） |

## 模块开发

### 模块目录结构

```
my-module/
├── build.gradle.kts
└── src/main/kotlin/
    └── com/akiba/module/
        └── MyModule.kt
```

### 基础模块类

```kotlin
package com.akiba.module

import ghidra.program.model.listing.Program
import org.apache.logging.log4j.Level
import org.iotsplab.akiba.module.AkibaModule
import org.iotsplab.akiba.utils.WithTableColumn

@WithTableColumn("result", "TEXT")
class MyModule(
    configPath: String? = null,
    id: Int,
    program: Program,
    consoleLogLevel: Level = Level.INFO,
    fileLogLevel: Level = Level.INFO,
    tableName: String? = "my_module_results"
) : AkibaModule(
    configPath = configPath,
    id = id,
    program = program,
    consoleLogLevel = consoleLogLevel,
    fileLogLevel = fileLogLevel,
    tableName = tableName
) {
    override suspend fun startProcess() {
        // 分析逻辑
        updateData(mapOf("result" to "analysis complete"))
    }
}
```

### 常用 API

| API | 说明 |
|-----|------|
| `getMetadata()` | 获取二进制文件元数据 |
| `getTaskData(key)` | 获取临时数据 |
| `setTaskData(key, value)` | 设置临时数据 |
| `updateData(map)` | 保存结果到数据库 |
| `updateErr(msg)` | 保存错误信息 |
| `callTaskAPI(function, *args)` | 调用其他模块 API |

## 日志文件

### 日志目录结构

```
log/<project_name>/
├── Root.log                    # 根日志
├── config.json                 # 任务配置副本
├── properties.json             # 二进制文件属性
├── <failed>/                   # 失败任务
│   └── <binary_id>/
│       └── ModuleName.log
├── <runtime_error>/            # 运行时错误
└── <success>/                  # 成功任务
```

### 日志级别

| 级别 | 说明 |
|-----|------|
| `OFF` | 关闭 |
| `TRACE` | 最详细 |
| `DEBUG` | 调试 |
| `INFO` | 信息 |
| `WARN` | 警告 |
| `ERROR` | 错误 |

## 断点续传

### 使用 starter.py

```bash
python3 subprojects/akiba_framework/src/main/scripts/starter.py &
```

### 手动续传

```bash
cd /home/akiba/akiba_framework

# 查看可用的断点
ls log/

# 续传指定任务
./bin/akiba_framework -r 20250201140000
```

## 快速启动 checklist

### 基于源代码仓库

```
□ 1. 克隆仓库
  cd ~
  git clone https://github.com/IoTS-P/Akiba.git
  cd Akiba
  git submodule update --init --recursive

□ 2. 生成 ghidra.jar
  wget https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_11.3.2_build/ghidra_11.3.2_PUBLIC_20250415.zip -O /tmp/ghidra.zip
  unzip /tmp/ghidra.zip -d /tmp
  cd /tmp/ghidra_11.3.2_PUBLIC/support
  chmod +x ./buildGhidraJar
  ./buildGhidraJar
  cp ghidra.jar ~/Akiba/lib/ghidra.jar

□ 3. 设置 Java 环境
  cd ~/Akiba
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64

□ 4. 编译
  ./gradlew assemble

□ 5. 启动 DB Daemon
  docker compose up -d
  # 或
  ./gradlew :subprojects:akiba_db_daemon:run

□ 6. 创建数据库实例
  ./gradlew run --args="instance-create -n akiba -u akiba"

□ 7. 导入二进制文件
  ./gradlew run --args="-i import-example.json -c config.json@/main"

□ 8. 运行分析
  ./gradlew run --args="-c config.json@/main"
```

### 基于 Docker（推荐）

```
□ 1. 克隆仓库
  cd ~
  git clone https://github.com/IoTS-P/Akiba.git
  cd Akiba
  
□ 2. 构建 Docker 镜像并开启容器（需要软件包 docker-compose-v2）
  docker compose up --build -d
  
□ 3. 进入 Docker 容器
  docker exec -it akiba_all_in_one bash
  
□ 4. （可选）运行功能测试脚本
  ~/binaries/test_run.sh
  
□ 5. 导入二进制文件
  cd ~/akiba_framework 
  ./bin/akiba_framework -i import-example.json -c config.json@/main
  
□ 6. 运行分析
  cd ~/akiba_framework 
  ./bin/akiba_framework -c config.json@/main
```

## Akiba Docker 关键目录解释

| 目录                                  | 说明                                   |
|-------------------------------------|--------------------------------------|
| `/home/akiba/akiba_framework`       | Akiba 框架发布包根目录                       |
| `/home/akiba/akiba_db_daemon`       | Akiba 数据库守护进程所在目录                    |
| `/home/akiba/binaries`              | 示例模块、示例二进制文件、功能测试脚本所在目录              |
| `/home/akiba/binaries/test_run.sh`  | 集成功能测试脚本，直接运行即可进行测试                  |
| `/home/akiba/.akiba/daemon.log`     | 数据库守护进程（在容器中PID为1）日志                 |
| `/home/akiba/.akiba/instances.json` | Akiba 管理的所有数据库实例信息（仅在数据库守护进程正常退出后更新） |
| `/akiba/backups`                    | Akiba 管理的数据库实例的所有备份所在目录              |
| `/akiba/instances`                  | Akiba 管理的所有数据库实例所在目录                 |

## 常见问题

| 问题             | 解决方案                                      |
|----------------|-------------------------------------------|
| DB Daemon 连接失败 | 检查 `127.0.0.1:31777` 是否可访问                |
| 任务超时           | 增加 `timeout` 值或添加 `@IgnoreRuntimeTimeout` |
| 数据库认证失败        | 确认 `username/password` 为 `akiba/akiba`    |
| 模块找不到          | 确认 JAR 文件在 `modules/` 目录且以 `amod` 开头      |
| Ghidra 版本不兼容   | 使用 Ghidra 11.3.2 版本                       |
| Akiba 框架运行时崩溃  | 使用断点续传参数恢复还未完成的任务                         |
