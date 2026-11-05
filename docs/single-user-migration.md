# 单用户化改造（single-user mode）

目标：去掉多用户体系，只保留一个全局密码；实例不再各建 PostgreSQL 集群，
统一落到默认 5432；daemon 鉴权保留（单一共享凭据）；表锁不变。

已提交：

- `akiba_framework` 5682986 — 删除 `server/routes/AdminRoutes.kt` 及注册
- `akiba_frontend` 556ec6f — 删除 `AdminUsers.vue`、路由、导航、`adminApi`

## 阶段 1：单一密码 + daemon 单一凭据

1. `server/routes/AuthRoutes.kt`
   - `POST /auth/setup`：忽略请求中的 `username`，固定 `admin`；仅在
     `UserDao.countUsers() == 0` 时可用。
   - `POST /auth/login`：只校验 `password`，请求体不再需要 `username`。
   - 新增 `POST /auth/password`：需登录，收 `currentPassword` / `newPassword`。
   - 去掉账号锁定（`LoginProtection`），保留失败延迟。
2. `server/db/UserDao.kt`：删 `listUsers` / `deleteUser` / `setAdmin` /
   `countAdmins` / `getUserById` / 解锁相关列；保留
   `createUser` / `countUsers` / `verifyPassword` / `checkPassword` / `setPassword`。
3. `server/routes/DaemonIdentity.kt`：由"按用户派生"改为进程内单例，
   登录成功时建立一次，后续复用。
4. 配置去字段：框架 config、daemon config、`FileRoutes.kt` 生成的
   `config.json` 中的 `username` / `password` 全部删除。
   这一步同时修掉"导入子进程用硬编码账号导致静默失败"的问题。
5. 前端：`Login.vue` 只留密码框；`stores/auth.ts` 只传 `password`；
   `Settings.vue` 增加"修改密码"。

验收：干净卷 → 设置密码 → 未登录请求 401 → 登录后建实例 →
导入 20 个文件 → `binaries.arch` 全为 NULL。

## 阶段 2：实例扁平化

- `operations/PGInstances.kt`：删 `initdb` / `pg_ctl` / 端口分配 / 每实例集群，
  改为在默认 5432 上 `CREATE DATABASE` / `DROP DATABASE`。
- `dbutil/UserStore.kt`、`dbutil/UserDatabaseSession.kt`：随阶段 1 一并移除。
- `Configs.kt`：去掉 user 相关字段与 `instanceRoot`；日志目录同步拍平。
- `dockerfile_needed/entrypoint.sh`：不再初始化 `akiba_users` 与角色。

验证：干净卷起容器 → 建实例 → 导入 → 查询，全部走 5432。

## 阶段 3：回到文件导入

- 新增 `akiba_mod_arch`（`ArchIdentifier`），对 `arch IS NULL` 的二进制
  执行识别并写回 `arch/format/compiler_spec`。
- 识别前按文件头预筛候选架构：ELF `e_machine`、PE `Machine`、Mach-O `cputype`。
- 工具侧统一 guard：无架构时给出明确错误，不静默失败。

## 背景数据（实测）

- 导入瘦身后：20 个 ELF 文件 3.15 s（≈30 ms/文件）；改造前 2 个文件 17.5 s
  （≈8.7 s/文件），旧路径在导入时做 Ghidra 全量分析。
- 每个实例曾是独立 PostgreSQL 集群（`/akiba/instances/<name>`，端口 31800 起），
  这是"实例数据在 5432 里查不到"的原因。
