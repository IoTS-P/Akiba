# Akiba - 一个基于 Ghidra 的支持批量流水线任务的二进制分析框架

🤔 什么是 Akiba？

Akiba 是一个基于 Ghidra 的支持批量流水线任务的二进制分析框架，可为二进制文件分析提供高度灵活性。它基于 Ghidra 和 Kotlin 语言开发，非常适合需要进行大规模批量化分析的场景。

😋 有哪些优势？

- 支持多线程流水线分析，适合运行在计算服务器上
- 目前使用 PostgreSQL 保存数据，使用 Akiba 数据库守护进程完成数据库远程数据管理
- 完全自定义可拆卸的模块，并支持简单的流程控制
- 支持海量 Maven 第三方库导入，较 Ghidra Script 更加灵活更加强大

🤗 需要开发自己的功能模块？

Akiba 提供了一个示例模块仓库 [Akiba-Mod-Example](https://github.com/IoTS-P/Akiba-Mod-Example)，其中包含示例模块及开发说明文档。欢迎 Fork！

😓 有 bug？

Akiba 目前还处于早期开发阶段，可能还存在一些 bug 和性能问题，请不要吝啬在 issue 中反馈，或者提交 pull request 来帮助修复。非常感谢！

## 环境依赖

Java 版本：21 及以上

```shell
sudo apt install openjdk-21-jdk
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
git submodule update --init --recursive
```

Kotlin 版本：2.1.20 及以上

Ghidra.jar 版本: 11.3.2 (因 Ghidra API 不断更新，其他版本可能会存在兼容性问题)

## Docker 容器部署

```shell
# sudo apt install docker-compose-v2
docker compose up --build
```

## 子模块

- Akiba Framework：Akiba 运行时框架
- Akiba Database Daemon：Akiba 数据库守护进程
- Akiba Mod - Utils：Akiba 实用模块（对 Ghidra 进行二次封装）
- Akiba Mod - Example: Akiba 示例模块
- Akiba Modules：Akiba 模块（目前闭源）