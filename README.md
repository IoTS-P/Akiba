# Akiba - A Ghidra-based Batch Pipeline Task Supported Binary Analysis Framework

[中文文档](README_zh.md)

🤔 What is Akiba?

Akiba is a Ghidra-based batch pipeline task supported binary analysis framework that provides high flexibility for binary file analysis. It is developed based on Ghidra and Kotlin language, making it very suitable for scenarios that require large-scale batch analysis.

😋 What are the advantages?

- Supports multi-threaded pipeline analysis, suitable for running on compute servers
- Currently uses PostgreSQL for data storage, uses Akiba Database Daemon for remote database management
- Fully customizable and detachable modules, with support for simple workflow control
- Supports massive Maven third-party library imports, more flexible and powerful than Ghidra Script

🤗 Want to develop your own functional modules?

Akiba provides an example module repository [Akiba-Mod-Example](https://github.com/IoTS-P/Akiba-Mod-Example), which contains example modules and development documentation. Welcome to Fork!

😓 Any bugs?

Akiba is still in early development stage, there may be some bugs and performance issues. Please don't hesitate to report them in issues, or submit pull requests to help fix them. Thank you very much!

## Environment Requirements

Java Version: 21 and above

```shell
sudo apt install openjdk-21-jdk
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
git submodule update --init --recursive
```

Kotlin Version: 2.1.20 and above

Ghidra.jar Version: 11.3.2 (Due to continuous updates of Ghidra API, other versions may have compatibility issues)

## Docker deployment

```shell
# sudo apt install docker-compose-v2
DOCKER_BUILDKIT=1 docker compose up --build
```

## Submodules

- Akiba Framework: Akiba runtime framework
- Akiba Database Daemon: Akiba database daemon process
- Akiba Mod - Utils: Akiba utility module (re-encapsulation of Ghidra)
- Akiba Mod - Example: Akiba example module
- Akiba Modules: Akiba modules (currently closed source)