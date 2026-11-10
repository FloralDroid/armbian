# SDM845 6.18 补丁职责

`series.conf` 是完整应用顺序，不能仅按子目录独立排序或将依赖补丁省略后构建。当前目标基线为 Linux 6.18.62，整理目录不会替代基线核验。

| 目录 | 职责 |
| --- | --- |
| `patches/` | SDM845 / 小米 8 板级设备、驱动及兼容修复 |
| `selinuxns/` | SELinux 子命名空间、策略/标签/SID 隔离及其基础修复 |
| `uts/` | 宿主管理的 UTS 实例身份、资源、proc/sysfs、事件、任务/UID/时间视图与映射实例权限兼容 |
| `scheduler/` | 调度与 rlimit 权限兼容、cgroup CPU 调度控制；实例绑定检查仍依赖此前的 UTS 基础设施 |
| `container-root/`（当前没有补丁） | 仅保留给容器内 App 授权、提权链本身必须的内核改动，不能用作普通隔离或 Android 启动兼容的兜底分类 |

按代码实际职责归类，而不是按最早的测试任务命名。依赖顺序仍由 `series.conf` 明确列出，目录归类不表示这些补丁没有依赖或应单独构建。

原 `container-root/0001-container-root-Isolate-task-UID-and-time-views.patch` 移至 `uts/0014-uts-Isolate-task-UID-and-time-views.patch`：实际提供绑定实例的 task、UID 资源与时间等视图，不负责 App 授权。原邮件 Subject 保留以维持历史内容和来源。

原 `container-root/0002-rlimit-Allow-instance-local-RT-priority-limits.patch` 曾移至 `uts/0015-uts-Allow-instance-local-RT-priority-limits.patch`，现按调度模块归入 `scheduler/0001-rlimit-Allow-instance-local-RT-priority-limits.patch`：实际是绑定实例管理员的自身 RTPRIO 限额兼容，正常 Sensor/Camera HAL 同样需要。绑定核验依赖前面的 UTS 补丁，不能因此将调度兼容继续归入 UTS 视图。它没有开放 FIFO/RR，也没有实现 cgroup v2 RT 带宽配额。

2026-11-09 目录整理仅改变路径和 series 说明，补丁字节、作者/签名和应用先后顺序保持。前次记录位于仓库 `dev/patch-responsibility-20261109/`；调度模块最新归类核验位于 `dev/rt-budget-6.18.62/organization-replay.json`。新增 RT 预算实现须另以实际代码和运行证据核验，目录存在不表示 RT 配额已经可用。过去构建日志中的旧路径按历史证据保留。

`scheduler/0002` 实现用户于 2026-11-10 批准的 RT 修订三。宿主先设置有限 `cpu.max`，再在空、无后代且未发布的实例根设置 `cpu.rt.mode=quota`；后代继承同一边界，不能解除模式或删除实例根限额。RT 保留原生 FIFO/RR、优先级、RR 时间片和 SMP 放置，RT/普通线程与 PI 合计消耗同一实例及祖先 CPU 配额；不把 RT 纳入 `cpu.weight`、不修改普通主要 tick/均衡算法，不增加独立 RT 毫秒池。宿主原生 RT 安全预算保留，实例不获得直接 SCHED_DEADLINE 准入。需要 FAIR_GROUP_SCHED、RT_GROUP_SCHED 与 CFS_BANDWIDTH；SCHED_CORE、SCHED_PROXY_EXEC 或 SCHED_CLASS_EXT 配置仍显式拒绝该模式。旧实验值 `group` 拒绝写入，防止新旧 daemon/内核误认语义。

实现与 Docker 构建记录位于 `dev/rt-budget-6.18.62/`。修订二的共同权重候选、旧测试及未通过的 SMP 实验保留为历史证据；当前验收以 `quota-*` 记录为准，须区分 QEMU、ARM 实机、Android 和性能验证。补丁进入 series 不表示尚未记录的验证已通过。

`uts/0015` 补齐绑定映射实例的 alarm timerfd：实例内 CAP_WAKE_ALARM 经绑定核验后使用本地 hrtimer，保留 clock 8/9 的逻辑标识与 time namespace 归属，不进入宿主物理 RTC 唤醒队列。物理休眠由宿主决定；此补丁不表示私有墙钟与独立校时已经完成。源码、审批范围及验证记录在 `dev/instance-alarm-6.18.62/`，是否已上板以该目录实际结果为准。

本轮粒度整理仅处理工作区尚未提交的补丁：将原 `uts/0010-proc-Honor-user-namespace-IDs-for-private-UTS-sysctls.patch` 与 `uts/0013-sysfs-Use-instance-root-ownership-for-private-views.patch` 合并为 `uts/0010-uts-Honor-instance-root-permissions-for-private-views.patch`，统一说明私有 proc/sysfs 视图的实例 root 权限映射。原作者与签名保留，其余补丁内容和相对顺序保持。完整序列由 113 份减为 112 份；从精确基线重放前后的最终源码树相同，记录位于 `dev/patch-consolidation-20261110/`。
