# AutoNovel Restic 备份机制

- Primary Compose 每次启动只执行一次标准 `restic backup`
- Primary 的 `files-wenku` 和 `files-extra` bind 在 Compose 中固定为只读
- Primary 通过 crontab 每小时调用 `just primary`。
- Replica 通过 `rest-server` 接收备份；`restic-mount` 手动启用后提供只读 FUSE，`restic-admin` 供检查、恢复和清理接口，`just cleanup` 执行清理。

## Backup Server

部署顺序是先 Backup、后 Primary；命令均在本配置目录执行：

| 执行位置 | 配置文件 | 命令 | 行为 |
|---|---|---|---|
| Backup | `.env` | `just backup` | 初始化/复用仓库，启动 HTTP 接收端 |
| Primary | `.env` | `just primary [dry-run]` | 执行一次备份，或仅预览，随后退出 |
| Backup | `.env` | `just mount` | 准备 shared mount 并启用挂载 |
| Backup | `.env` | `just cleanup` | 停止服务、只保留最新快照并清理，结束后手动重启 |

持续每小时备份需要安装下文的 Primary cron；`just primary` 为 single shot。

### justfile

宿主机安装 `just` 和 Bash，并确保当前用户能操作 Docker。`just` 的安装方式见[官方安装说明](https://just.systems/man/en/packages.html)。

编辑下文的 `.env` 后，在本目录执行：

```bash
# On Backup Server
just backup           # 自动准备本地仓库并启动接收端
just mount            # 准备 shared mount 并启用 FUSE 挂载
just cleanup dry-run  # 预览历史删除计划，不执行 forget 删除或 prune
just cleanup          # 保留最新备份、回收空间并检查
```

### 所有配置放在 env

| 配置项 | Primary | Backup |
|---|---|---|
| `RESTIC_REPOSITORY` | 目标仓库的完整 HTTP/HTTPS URL | 本地仓库地址由路径和用户名自动组合 |
| `RESTIC_REST_USERNAME` | REST 登录用户名 | 同一个用户名，也作为仓库子目录名 |
| `RESTIC_REST_PASSWORD` | REST 登录密码 | 同一个登录密码 |
| `RESTIC_PASSWORD` | 仓库加密密码 | 同一个加密密码，供初始化/mount/admin 使用 |
| 快照主机名 | `RESTIC_HOSTNAME` | `RESTIC_PRIMARY_HOSTNAME`，必须与 Primary 一致 |
| 快照标签 | `RESTIC_TAG` | 同一个 `RESTIC_TAG`，供 mount/cleanup 筛选 |

登录密码与加密密码是两个独立配置项。

密码使用单行值，建议像示例一样用单引号包裹，避免其中的 `$` 被 Compose 当成变量展开。把示例密码替换为自己的密码

Compose 会自动创建 `.env` 指定的仓库根目录和缓存目录，无需单独执行 mkdir。首次启动由 Backup 在本地初始化仓库

示例项目名为 `auto-novel-backup`，路径如下：

| 位置 | 宿主机默认路径 | 用途 |
|---|---|---|
| REST 服务根目录 | `/data/restic/data` | rest-server 容器中的 `/data` |
| 实际仓库 | `/data/restic/data/auto-novel` | `RESTIC_REST_USERNAME=auto-novel` 对应的子目录 |
| FUSE 挂载点 | `/data/restic/mount` | 启用后在 `snapshots/latest/` 下浏览文件 |
| 缓存 | `./data/cache` | restic 缓存，尽量位于 SSD |

### HTTP 监听与 Cloudflare 接入

rest-server 始终提供 HTTP，容器内部监听 8000；`REST_SERVER_PORT` 控制 Backup 发布端口，`REST_SERVER_LISTEN_ADDRESS` 控制 Backup 发布地址。

| 用途 | `REST_SERVER_LISTEN_ADDRESS` | 连接方式 |
|---|---|---|
| 宿主机上的反向代理 / cloudflared | `127.0.0.1`（默认） | 代理回源 `http://127.0.0.1:8000` |
| 仅 Tailscale 直连 | 本机 Tailscale IP，例如 `100.64.0.10` | Primary 使用 `rest:http://100.64.0.10:8000/auto-novel/` |
| 所有 IPv4 网卡，包括 Tailscale 和公网 | `0.0.0.0` | 使用该服务器实际 IP；`0.0.0.0` 不能作为客户端目标地址 |

### Backup 日志：每个容器最多 10 MiB

Backup 的初始化、接收端、挂载和 admin 服务统一使用 Docker `local` 日志驱动。`rest-server` 保持 `--log -`，stdout/stderr 由 Docker 管理；

每个容器按 5 MiB 轮转，最多保留 2 个文件（含当前文件，压缩前合计约 10 MiB），旧日志自动压缩，超过数量限制后删除最旧文件。

首次启动旧版本时，可能先出现 `Fatal: repository does not exist`，随后出现 `created restic repository ...`，这表示空仓库探测后已成功创建，并非初始化失败。
后续出现 `Existing repository is ready.` 表示复用已有仓库。

### 自动准备仓库并启动接收端

```bash
just backup
```

默认运行一次 `restic-init`，成功后启动 `rest-server`，不自动启用 mount。

初始化任务的逻辑是：本地仓库可打开则复用；只有 restic 明确返回仓库不存在（退出码 10）且目标目录为空/不存在时才初始化。首次探测的预期报错不会作为 Fatal 输出，而会提示 `Repository does not exist; initializing it now.`；其他真实错误仍正常输出。密码错误、其他访问错误或非空目录缺少仓库配置都会报错，不继续启动依赖它的服务。

`restic-mount` 同样等待 `restic-init` 成功后再启动，因此可以在首次备份前运行 `just up`；空仓库的挂载视图里暂时没有 `snapshots/latest/`，第一份快照到达后才有内容。`just mount` 和 `just up` 会自动完成下文的 shared mount 准备。

rest-server 每次启动从 env 中的 REST 用户名/密码生成 bcrypt 认证文件，放在容器临时目录中。无需 `create_user` 或额外认证文件；当前配置管理一个 REST 用户。仓库加密密码只传给初始化任务和 mount/admin，rest-server 接收端不需要解密备份。

接收端固定启用：

```text
--append-only --private-repos
```

因此 Primary 可以读取和追加备份，但不能通过网络删除或覆盖已有仓库对象。

## Primary Server

### env

```bash
cp .env.primary.example .env
```

编辑 `.env`，填写目标地址及与该 Backup Server 一致的两种密码。例如 Cloudflare 入口：

```dotenv
RESTIC_REPOSITORY=rest:https://backup.example.com/auto-novel/
RESTIC_REST_USERNAME=auto-novel
RESTIC_REST_PASSWORD='your-rest-login-password'
RESTIC_PASSWORD='your-repository-encryption-password'
```

Tailscale 直连时，仅把地址改为 `rest:http://<backup-tailscale-ip>:8000/auto-novel/`，并确认 Backup Server 已绑定 Tailscale IP 或所有地址。

`WENKU_PATH`、`EXTRA_PATH`、缓存路径和资源参数也在同一份 env 中设置。缓存目录由 Compose 自动创建；两个生产源目录必须已存在，并始终只读挂载。

### 启动备份

> 先保证 Backup 已经执行过 `just backup`

在 Primary 执行：

```bash
just primary          # 实际上传并创建 snapshot
just primary dry-run  # 读取并预览，不上传、不创建 snapshot
```

默认 mode 为 `apply`，因此 `just primary` 与 `just primary apply` 等价。只接受 `apply` 和 `dry-run`，其他值会直接报错。两种模式都读取同一份 `.env`，都不会检查或初始化仓库；dry-run 仍会遍历和读取源文件，但源目录始终以只读方式挂载。

也可以直接启动 Primary Compose，未传入 `RESTIC_DRY_RUN` 时默认执行实际备份：

```bash
docker compose -f docker-compose.primary.yml \
  up --exit-code-from restic-primary
```

它是一次性任务，备份完成后退出；每小时运行由下文的 cron 负责。

Compose 使用 `/source` 作为工作目录并传入相对路径，避免父目录元数据变化制造无意义 snapshot。`--no-scan` 用于关闭仅用于进度预估的额外扫描

### 每小时执行

cron 先切换到部署目录，再运行 Compose

Debian 如果尚未安装 cron，先安装并启动：

```bash
sudo apt-get install -y cron util-linux logrotate
sudo service cron start
```

安装提供的 cron 配置：

```bash
sudo install -d -o root -g root -m 700 /var/log/auto-novel-restic
sudo install -o root -g root -m 644 \
  cron/auto-novel-restic.example /etc/cron.d/auto-novel-restic
sudo service cron reload
```

示例默认在每小时第 17 分钟运行 `replica-01`。安装前必须把 cron 文件中的 `/root/deploy/backup/restic` 改成本目录的实际绝对路径。

每条任务都使用同一个 `/run/lock/auto-novel-restic.lock`。即使多个 Replica 的时间重叠，也不会同时扫描 Primary；等待锁超过 3300 秒的任务会失败并记录非零退出码，下一小时会启动新任务。3300 秒只限制等待锁的时长，不限制备份本身；首轮备份应先手动完成，再安装 cron。

添加第二个目标时，在 Primary 上准备独立部署目录，例如：

```bash
mkdir -p ../restic-replica-02
cp docker-compose.primary.yml justfile ../restic-replica-02/
cp .env.primary.example ../restic-replica-02/.env
chmod 600 ../restic-replica-02/.env
```

编辑第二个目录的 `.env`，填写第二个目标的地址和密码；默认相对缓存路径 `./data/cache` 也会落在第二个目录下。第二台 Backup 同样用自己的 `.env` 启动 `just backup`；Primary 在第二个目录执行 `just primary` 上传。启用 cron 示例的第二行，并把 `cd` 路径改为第二个目录的绝对路径。

每个目录的 `.env` 只配置一个仓库 URL，两个目标分别执行备份。以后同步 Compose/justfile 版本时保留各目录的 `.env`；日常更换地址、密码、源目录、缓存和资源参数，只编辑该目录的 `.env`。

检查 cron 和手工触发：

```bash
sudo service cron status
sudo tail -n 50 /var/log/auto-novel-restic/replica-01.log

just primary
echo "exit=$?"
```

日志中的 `END exit=0` 表示本轮成功，包含“文件未变化，因此跳过创建快照”的情况；`END exit=3` 表示部分文件未读到，快照不完整；其他非零退出码同样需要处理。日志按天轮转，保留 7 份，logrotate 每次运行时也会检查 10 MB 大小阈值。

```bash
sudo grep 'END exit=' /var/log/auto-novel-restic/replica-01.log | tail -n 10
```

检查的是最近一次成功执行时间，不是最新快照时间。若连续两轮未成功，查看同一日志中的网络、权限或空间错误；若只有 `START` 而长期没有 `END`，检查正在运行的容器和目标磁盘。手工备份请避免与 cron 重叠。本配置不依赖本机邮件系统，也不自动发送外部告警。

## FUSE Mount

`restic-mount` 使用 `profiles: ["mount"]`，普通 `up -d` 默认启动它

### FUSE mount propagation

要让容器内 FUSE 出现在宿主机，mount point 必须是 shared mount。直接执行：

```bash
just mount
```

该命令从 `.env` 读取 `RESTIC_MOUNT_PATH`，要求它是绝对路径，然后依次完成：
- 停止旧 `restic-mount` 容器
- 卸载传播到宿主机的旧或失联 restic FUSE
- 创建目录、在需要时建立 scoped self-bind、设置 `rshared`、验证传播状态
- 重新启动 `restic-mount`。

重复执行会刷新容器和 FUSE 视图，但不会叠加 self-bind。过程中会由 `sudo` 请求宿主机权限。

如果容器停止后访问路径出现 `Transport endpoint is not connected`，这是传播到宿主机的 FUSE 已失联。直接再次执行 `just mount` 即可；

宿主机重启会丢失临时 self-bind；重启后再次执行 `just mount` 即可。

若希望 Docker 在宿主机启动后无需手工命令就恢复 FUSE，可以按 `.env` 中的实际路径在 `/etc/fstab` 加入：

```fstab
/data/restic/mount /data/restic/mount none bind,rshared 0 0
```

> fstab 持久化是可选项；使用 `just mount` 时无需编辑 fstab。

## Admin 与维护

`restic-admin` 默认不启动，只在 Replica 本机临时运行。默认保留所有历史，空间紧张时可清理到每个备份路径组仅剩最新一份

### 定期检查

建议每周低峰期检查一次，检查后手动启动服务：

```bash
docker compose -f docker-compose.backup.yml --profile mount down
docker compose -f docker-compose.backup.yml \
  --profile tools run --rm -T restic-admin check
# 检查结束后，根据输出处理错误，再手动启动：
just up
```

普通 `check` 检查仓库结构，不会读取全部文件数据。弱 HDD 可轮换用 `check --read-data-subset=1/4`、`2/4`、`3/4`、`4/4` 替换上面的 `check`，分四次验证数据内容。

### 一键清理：仅保留最新备份

```bash
just cleanup          # 停止服务并执行清理
just up               # 清理结束后手动启动接收端和挂载
```

流程只有三步：

1. `docker compose --profile mount down` 停止并移除初始化、接收端和挂载容器，bind mount 中的仓库数据保留。
2. 用一个 `run --rm restic-admin` 临时容器依次执行 `check` → `forget --keep-last 1` → `prune` → `check`；任一步失败即退出，保留非零退出码。
3. 打印手动启动提示，不自动恢复 server 或 mount。

可选的预览命令：

```bash
just cleanup dry-run
```

预览同样会 down 服务，但仅执行前置 `check` 和 `forget --dry-run`，不删除历史、不执行 prune。结束后也需要手动启动服务。重启时在同一部署目录执行命令，继续使用该目录的 `.env`。

清理前确认没有备份/恢复正在执行，且 Primary 最近一轮备份成功。
