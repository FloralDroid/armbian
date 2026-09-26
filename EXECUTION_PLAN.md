# Armbian Mobile Device Platform 执行计划书

## 1. 当前状态

- 工作目录：`/mnt/aosp-hdd/armbian/armbian-arm-host`
- Git 分支：`main`
- 当前仓库：已初始化，尚无上游代码和设备实现
- 第一台参考设备：Xiaomi Mi 8，`xiaomi-dipper`，Qualcomm SDM845，`arm64`
- 第一阶段产品内核线：`6.12.y` LTS；发布构建跟随该分支最新可验证稳定版本
- reference 复现点：Mobian `linux-6.12-sdm845` `6.12.91-1`（仅用于重现历史基线）
- 每次构建必须锁定精确的 `6.12.N`、下游源提交和完整 patch queue；“最新”不等于不固定版本
- `selinuxns`：作为独立、按 kernel line 版本化的公共补丁层

本计划以最新操作要求为准使用 `main` 作为主分支；原项目说明中的
`mobile-devices` 分支名称不再作为当前分支要求。

## 2. 目标与边界

### 第一阶段目标

在当前 Armbian Build Framework 上完成一个可重复构建的 `xiaomi-dipper`
移动设备支持，并生成：

- Android `boot.img`（kernel + DTB + initramfs）
- ext4 rootfs 镜像
- `manifest.json`、构建信息和校验和

设备应能保留厂商 Qualcomm boot chain，启动 Linux、systemd、UFS 上的 rootfs，
并通过 USB NCM/ECM 管理网络提供 SSH。显示、触摸、GPU、音频、调制解调器、
充电、电池、热管理等已工作的硬件能力不能因 headless 默认设置而被删除。

### 明确不做

第一阶段不替换 XBL/ABL，不修改 Android GPT，不自动化 EDL，不升级 kernel
大版本，不做 OTA、完整 Android container runtime、GUI 或硬件改造，也不为
不同 UFS 容量生成不同 rootfs 镜像。

## 3. 执行阶段与门槛

### 阶段 0：仓库引导（已完成）

**动作**

1. 创建项目目录和 Git 仓库。
2. 设置主分支为 `main`。
3. 写入本计划和仓库边界说明。

**验收**

```bash
cd /mnt/aosp-hdd/armbian/armbian-arm-host
git branch --show-current  # main
git status
```

### 阶段 1：上游审计

**动作**

1. 获取并固定审计版本：`armbian/build` 和 `taygoth/dipper-mainline-port`。
2. 阅读 reference 项目的 README、安装说明、已知问题、kernel、userspace、
   CI/build、boot image 和 firmware extraction 逻辑。
3. 检查 Armbian 当前的 `config/boards/`、`config/sources/families/`、
   `extensions/`、rootfs、artifact 和 image builder 入口。
4. 搜索现有 Qualcomm、SDM845、SM8250、SC8280XP、QCS、QRB 支持，确认能复用
   的 family 和扩展点。
5. 获取 Mobian `linux-6.12-sdm845` 的可复现源包/提交，确认其与 reference
   patch 的精确关系；当前审计到的滚动版本为 `6.12.109-1`。
6. 固定 `selinuxns` kernel、libselinux、systemd 分支和提交，生成 6.12 回移植
   可行性报告。
7. 记录构建主线、依赖、分支、提交和外部下载源，形成审计记录。

**输出**

- `docs/upstream-audit.md`
- 上游提交/标签清单
- 当前 Armbian board/family/extension 入口图
- patch、boot、firmware、rootfs 的初步映射表
- `selinuxns` 对 6.12.y 的 patch/API 兼容性报告

**门槛**：在审计完成前不写设备集成代码；不能从印象推断 boot header、DTB
位置、firmware 路径或 Armbian 私有接口。

### 阶段 2：架构冻结

**动作**

1. 写出并评审四层职责：
   - `common mobile`：rootfs、systemd、first boot、USB gadget、通用 artifact
   - `Qualcomm`：共享 firmware/boot helper 等 Qualcomm 能力
   - `SDM845`：kernel source、通用 patch、kernel config、Adreno/Venus 能力
   - `xiaomi-dipper`：DTB/DTS、设备 patch、boot 参数、firmware mapping、设备 hook
2. 以当前 Armbian 结构为准选择 board、family、extension、overlay 和工具位置；
   不建立平行 build system。
3. 确定数据驱动设备描述格式，优先使用现有 shell/Armbian 配置能力，只有确认
   必要时才引入 parser。
4. 确定 boot artifact、rootfs artifact、firmware manifest 和 flash mapping 的
   接口；设备差异必须进入配置/数据/hooks，而不是散落的 `BOARD` 条件分支。
5. 对 reference patch 逐个分类：`upstream`、`qcom-common`、`sdm845-common`、
   `dipper-specific`、`temporary-workaround`。

**输出**

- `docs/architecture.md`
- `docs/kernel-patches.md`
- 设备元数据样例与 artifact schema

**门槛**：关键架构选择先评审再实现；任何新增公共接口、抽象层或 fallback 都要
说明必要性、风险和替代方案。

### 阶段 3：最小可启动链路

按最小闭环实现，顺序固定为：

1. 增加 `xiaomi-dipper` board 配置（初期使用当前框架认可的 WIP 状态）。
2. 接入 `6.12.y` LTS 的 SDM845 kernel source、config、DTB 和分层 patch；先
   复现 `6.12.91-1`，再将同一 patch queue 维护到发布时明确锁定的最新
   `6.12.y` 提交。每个安全更新都要重新构建和执行静态检查；第一阶段不切换到
   6.18 或 7.x。
3. 接入基于原厂 `boot.img` 和 reference 项目确认的 Android boot 参数，生成
   boot artifact；不猜 header version、page size、load address 或压缩方式。
4. 生成 Debian Trixie minimal/server rootfs，默认 `BUILD_DESKTOP=no`，包名以
   当前发行版和 Armbian 实际可用包为准。
5. 生成固定合理大小的 ext4 rootfs 镜像；first boot 只扩展 filesystem，不改 GPT。
6. 添加 manifest、build-info 和 SHA256SUMS，记录 Armbian/kernel/patch/board
   revision。

**阶段验收**

```text
BOARD=xiaomi-dipper 可进入构建流程
kernel、DTB、initramfs、boot.img、rootfs.img 均生成
artifact 命名不含项目品牌，且按设备可扩展
manifest 能追溯完整版本输入
```

### 阶段 4：通用运行时能力

**动作**

1. 以通用 first-boot infrastructure 实现 machine-id、SSH host keys、firmware
   extraction、filesystem resize、USB 管理网络和 network-online 顺序。
2. 通过 `configfs`、systemd 和 `systemd-networkd` 实现 USB NCM，确认 ECM fallback
   的必要性和设备能力边界。
3. firmware 使用共享 extractor engine + 设备 manifest；首先复用 droid-juicer
   路径，但隔离 `dipper` 专属映射。
4. 保留 SELinux、seccomp、LSM 和容器基础 kernel 配置，不为方便关闭安全能力。
5. 将 `selinuxns` 作为独立 6.12 patch queue 集成，启用
   `CONFIG_SECURITY_SELINUX_NS=y`；同时审计修改版 `libselinux`、systemd-nspawn
   和容器 systemd 的版本兼容性，未完成 userspace 验证前不宣称功能完成。
6. 设备 hook 只注入设备差异，不将所有逻辑集中到 `firstboot-dipper.sh`。

**阶段验收**

```text
无屏幕、触摸、摄像头仍可 boot -> systemd -> USB/network -> SSH
firmware 不进入公开仓库，persist/calibration/unique identifiers 不被复制
common 服务不硬编码 Qualcomm UDC 名称
```

### 阶段 5：静态和构建验证

**动作**

1. 在干净构建目录执行完整 build；记录主机、工具链、依赖和耗时。
2. 检查 boot image header/内容、kernel、DTB、initramfs、rootfs、modules、manifest
   和 checksum。
3. 对 shell、配置和扩展执行语法检查；搜索核心框架中散落的 dipper-specific
   条件分支。
4. 检查 `CONFIG_SECURITY_SELINUX_NS`、namespace/cgroup/LSM 配置和 userspace
   依赖是否进入最终 artifact。
5. 构造重复构建对比，区分预期变化（时间戳、构建元数据）和非预期差异。

**构建命令基线**

```bash
./compile.sh \
  BOARD=xiaomi-dipper \
  BRANCH=current \
  RELEASE=trixie \
  BUILD_MINIMAL=yes \
  BUILD_DESKTOP=no
```

实际参数以阶段 1 审计到的当前 Armbian CLI 为准；若 CLI 不支持上述形式，记录
等价的可复制命令，不自行重写 build framework。

### 阶段 6：实体设备验证

这一阶段必须在真实 Xiaomi Mi 8 上执行，未连接设备前只能标记
`HARDWARE TEST REQUIRED`，不能把静态成功描述成启动成功。

**刷写前保护**

- 明确 fastboot serial；多设备连接时禁止自动选择第一个。
- 只允许写入 device metadata 指定的 `boot` 和 `userdata`。
- 不默认 erase `persist`、`modemst`、`xbl`、`abl`，不改 GPT。
- flash 工具必须使用 `set -euo pipefail`，并在执行前展示目标和 artifact。

**验证顺序**

1. fastboot 识别 product/serial，刷写 boot 和 userdata。
2. ABL 加载 boot.img，Linux、rootfs、systemd 正常启动。
3. UFS、挂载点和 filesystem resize。
4. USB NCM/ECM、networkd 和 SSH。
5. firmware 加载以及 Wi-Fi、Bluetooth、USB、音频、充电/电池、modem 等状态。
6. `/dev/dri`、Adreno 630、Freedreno；确认不是 `llvmpipe`/`softpipe`。
7. `/dev/video*`、Venus 和 H264/H265 能力，记录未完成的 userspace pipeline。
8. thermal zones、cpufreq 和 throttling；不得通过关闭保护换取性能。
9. namespaces、cgroup v2、OverlayFS、seccomp、bridge/veth/nftables、BinderFS。
10. 若 userspace 适配已完成，验证 `selinuxns` 的 unshare、子 namespace policy
    load、enforcing 切换和 systemd-nspawn 容器；否则明确标记未完成项。

**输出**

- `docs/hardware-validation.md`
- 原始命令输出、dmesg、版本和失败记录
- 明确的 `BUILD VERIFIED`、`STATIC VERIFIED`、`HARDWARE VERIFIED` 状态

### 阶段 7：可扩展性验收

回答并验证：增加 OnePlus 6 / `enchilada` 时，至少只需新增或修改：

- board/device config
- DTB/device patch
- firmware mapping
- boot parameters
- 必要的设备 hook 和测试数据

应通过代码搜索和最小配置检查证明：common、Qualcomm、SDM845 逻辑不依赖
`dipper`，不需要复制整套实现或增加几十处 `if`。

## 4. 目标目录与责任边界

最终目录必须服从实际 Armbian upstream 结构，以下只是责任映射，不是强制复制的
平行目录：

```text
userpatches/config/boards/xiaomi-dipper.wip              # board identity and device overrides
userpatches/config/sources/families/sdm845.conf          # reusable SDM845 defaults
userpatches/config/kernel/linux-sdm845-current.config    # pinned kernel configuration
userpatches/kernel/archive/sdm845-6.12/                  # project patch queue
extensions/                            # build/image hooks following Armbian APIs
devices/xiaomi-dipper/                 # device metadata, boot, firmware mappings
tools/                                 # thin build/flash wrappers
docs/                                  # audit, architecture, patch and validation records
```

禁止将 proprietary firmware、机器校准数据、唯一标识符和大体积 generated cache
放进 Git；具体忽略规则在阶段 1 根据实际输出目录补充。

## 5. 优先级与阻塞定义

- **P0 blocker**：无法构建、boot chain 破坏、rootfs/firmware 数据损坏、误写危险分区、
  热保护失效或无法追溯 artifact。
- **P1 important**：USB/SSH、UFS resize、GPU/容器基础能力或分层架构不满足第一阶段
  验收，但不涉及不可逆刷写风险。
- **P2 later**：Venus userspace 完整管线、第二台设备、6.12 以外的 kernel line、
  SM8250、批量 provisioning、OTA、完整 container runtime 和额外 SELinux/UTS 扩展。

任何构建、硬件或依赖不可用都必须在报告中明确标记；不能静默跳过。

## 6. 最终交付报告

完成第一阶段后按以下顺序提交报告：

1. **Architecture**：common / Qualcomm / SDM845 / dipper 职责。
2. **Files Changed**：每个文件及其目的。
3. **Build**：完整可复制命令和环境。
4. **Artifacts**：boot、rootfs、manifest、build-info、SHA256SUMS。
5. **Flash**：带明确 serial 和分区保护的 fastboot 命令。
6. **Validation**：分别列出 `BUILD VERIFIED`、`STATIC VERIFIED`、
   `HARDWARE TEST REQUIRED/VERIFIED`。
7. **Framework Extensibility**：新增第二台 SDM845 设备的最小变更清单。
8. **Remaining Issues**：按 P0/P1/P2 分类。
9. **Next Steps**：仅在第一阶段成功后推进第二台设备、kernel upgrade、SM8250、
   container runtime、SELinux enhancements、UTS enhancements、batch provisioning、OTA。

## 7. LTS 迁移策略

迁移到下一个 LTS 时不复制整套设备实现，而是新建候选 kernel line，保留旧线作为
回滚线，按以下顺序重放并验证：

```text
new LTS base
  -> selinuxns versioned queue
  -> Qualcomm common
  -> SDM845 common
  -> device-specific
```

每个 patch 必须重新分类为：已进入 upstream、可直接移植、需要 API 调整、需要功能
重写或已废弃。新 LTS 完成所有 board 的构建和 dipper 硬件验证后，才切换默认线；
旧 LTS 至少保留一个回归周期。

### 6.12.y 安全更新策略

`6.12.y` 是产品线约束，不是单一永久版本。正常更新以 kernel.org 的最新稳定
`6.12.N` 为候选，并同步评估 Mobian SDM845 下游版本是否已包含该修订；高风险
CVE 可脱离常规节奏优先处理。更新完成后必须重新验证 `selinuxns`、Qualcomm/SDM845
和设备补丁层，因为稳定分支更新可能改变上下文或接口。未完成构建和回归验证前，
不能把新版本标记为发布版本；旧的已验证 `6.12.N` 保留为回滚输入。

## 8. 下一步执行入口

仓库初始化和上游材料获取已完成。下一项是完成 `docs/upstream-audit.md` 中的
kernel source、patch compatibility 和 Armbian extension 对照，再提交架构方案，
经确认后进入实现阶段。
