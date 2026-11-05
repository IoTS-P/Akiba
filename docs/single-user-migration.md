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

## 待办

### 1. 备份需要重写（功能暂时关闭）

`pgbackrest` 的 stanza 以"每实例一个数据目录"为前提，实例变成数据库后不再成立。
现在 `BackupManager.backup()` / `restoreBackup()` 会明确报错而不是写错范围。
重写方向：按实例数据库做逻辑备份（`pg_dump` / `pg_restore`），备份树
（`backupDbName` / `backupTreeDbName`）保持。

### 2. 配置与目录的残留

- `server/db/ServerDatabase` 仍单独持有 `akiba_users` 库（JWT 会话所在），
  它已经和实例同一个 5432 集群，只需确认部署时不再单独创建。
- `RouteHelpers.currentUserGhidraProjectsRoot()` 这类按用户名分支的路径，
  以及 `Settings.vue` 里 `~/.akiba/<area>/<username>` 的展示，都还带一层用户名；
  单用户下可以拍平成 `~/.akiba/<area>`。
- `dockerfile_needed/entrypoint.sh` 仍在创建 `akiba_users` 库与角色，可随上一并清理。

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
