# Akiba - A Ghidra-based Batch Pipeline Task Supported Binary Analysis Framework

[中文文档](README_zh.md)

🤔 What is Akiba?

Akiba is a Ghidra-based batch pipeline task supported binary analysis framework that provides high flexibility for binary file analysis. It is developed based on Ghidra and Kotlin language, making it very suitable for scenarios that require large-scale batch analysis.

😋 What are the advantages?

- Supports multi-threaded pipeline analysis, suitable for running on compute servers
- Currently uses PostgreSQL for data storage, supports using Akiba Database Daemon for remote database management
- Fully customizable and detachable modules, with support for simple workflow control

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

## Submodules

- Akiba Framework: Akiba runtime framework
- Akiba Database Daemon: Akiba database daemon process
- Akiba Modules: Akiba modules (currently closed source)