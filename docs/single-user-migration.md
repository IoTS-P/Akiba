# 单用户化改造（single-user mode）

目标：去掉多用户体系，只保留一个全局密码；实例不再各建 PostgreSQL 集群，
统一落到默认 5432；daemon 鉴权保留（单一凭据）；表锁不变。

## 已完成

| 提交 | 内容 |
|---|---|
| `akiba_framework` 5682986 | 删除 `AdminRoutes.kt` 及注册 |
| `akiba_frontend` 556ec6f | 删除 `AdminUsers.vue`、路由、导航、`adminApi` |
| `akiba_framework` 3a8f5e1 | 单一密码：`UserDao` 只留一行凭据，`AuthRoutes` 收 `password`，新增 `POST /auth/password`，`LoginProtection` 只留 3 秒失败延迟 |
| `akiba_frontend` 731cfd6 | 登录页只留密码框；设置页新增修改密码卡片 |
| `akiba_framework` 05a5679 | `syncDaemonPassword`：改密同时写入 daemon，两个存储保持一致 |
| `akiba_db_daemon` ddbd870 | 实例扁平化：`CREATE DATABASE inst_<name>`，删除 per-instance 集群、端口分配与 `pg_ctl` 生命周期 |

同批修掉的问题：`/files/import` 曾把硬编码的 `akiba/akiba` 写进子进程 config，
导致前端导入静默失败；现在 worker 使用 `DaemonIdentities.current()` 的派生凭据。

## 运行时验收（干净卷 `akiba_flat`）

- `POST /auth/setup` 只带 `password` → 200，返回 `{token, username:"admin"}`
- 错误密码 → 401，耗时 3.06 s（失败延迟生效）
- 改密 → 200；新密码登录 200，旧密码 401
- 建实例 `flat` → 默认集群出现 `inst_flat`
- 导入 20 个文件 → `inst_flat.binaries` 20 行，`arch` 全为 NULL

## 后续三步（已完成）

| 提交 | 内容 |
|---|---|
| `akiba_framework` 4e8b184 | `identify-arch` CLI 子命令 |
| `akiba_db_daemon` 0c8d2cb | 备份改为 `pg_dump` / `pg_restore` 逻辑备份 |
| `akiba_framework` f1debf8、`akiba_frontend` 7546863 | 去掉目录里的用户层 |

验证：
- `identify-arch --all` 对 20 个导入文件全部识别成功，DB 20/20 有 arch
- 备份 `inst_flat` 得到 9.3 KB dump + manifest；删除 5 行后按别名 `first` 恢复，20 行连带 arch 全部回来
- 新导入落到 `~/.akiba/binaries/<instance>/original/`（无用户名层）

## 待办

### 1. 模块编译流程（用户已确认要修）

`akiba_modules` 的 `moduleJar-ALL` / `test` 会因为某个模块的编译错误整体失败
（当前是 `P2IMGateway.kt:71` 的 `definedStrings`）。模块间存在依赖，但不应该
"一个模块编译失败拖垮其他模块"。修法方向：模块任务彼此隔离、依赖按拓扑排序、
失败只影响依赖它的模块。

### 2. `akiba_users` 库仍然存在

`server/db/ServerDatabase` 用它存放单行凭据与 JWT 会话，entrypoint 也仍会创建它。
它不再是"用户管理"，只是认证存储；如需更彻底，可改名为 `akiba_meta` 并并入实例集群的初始化。

## 背景数据（实测）

- 导入瘦身后：20 个 ELF 文件 3.15 s（≈30 ms/文件）；改造前 2 个文件 17.5 s
  （≈8.7 s/文件），旧路径在导入时做 Ghidra 全量分析。
- 每个实例曾是独立 PostgreSQL 集群（`/akiba/instances/<name>`，端口 31800 起），
  这是"实例数据在 5432 里查不到"的原因。

## 架构识别模块（AkibaArch）

| 提交 | 内容 |
|---|---|
| `akiba_modules` 454e1fe | `AkibaArch` 模块 + `HeaderDetector`（ELF `e_machine` / PE `Machine` / Mach-O `cputype`）+ 单元测试 |
| `akiba_framework` 7d1d069 | `identify_architecture` 工具；无架构时 `ensureProgramForBinary` 明确报错 |

语言 ID 取自 `ProgramManager.GUESSED_PRIMARY_LEVEL_ARCHES`，保证导入侧一定能打开；
头字段无法映射时**不猜**，保留 null 并报失败。

已验证（容器内、真实 classpath）：

```
elf64_x86.bin      -> x86:LE:64:default | ELF | bits=64
elf32_mips_be.bin  -> MIPS:BE:32:R6     | ELF | bits=32
pe64.bin           -> x86:LE:64:default | PE  | bits=64
macho_arm64.bin    -> AARCH64:LE:64:v8A | Mach-O | bits=64
junk.bin           -> null
binaries#3 写入     -> arch/format 落库（探针测试后已删除）
```

**尚未跑通**：模块整体经由框架执行（`identify_architecture` → `callModule`）。
解析与写库两段已分别证明，组合段需要在有 LLM 的会话里或补一个 CLI 子命令后验证。

已知阻塞：`akiba_modules` 的 `moduleJar-ALL` / `test` 因既有编译错误（`P2IMGateway` 的
`definedStrings`，与本次改动无关）无法整体构建；单模块 `moduleJar-AkibaArch` 正常。
