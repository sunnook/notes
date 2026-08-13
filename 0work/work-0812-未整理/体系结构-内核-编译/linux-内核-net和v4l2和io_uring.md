### 1. net/sched/ 的 QoS 和 WebRTC 的 QoS 有交集吗？

**有交集，但不在同一个层面，它们是互补关系。**

| 维度 | Linux net/sched/ (TC) | WebRTC QoS |
|------|----------------------|------------|
| **层级** | **内核态**，L3/L4 层（IP/TCP/UDP） | **用户态**，应用层（RTP/RTCP） |
| **控制对象** | 整个系统的**网络流量**（所有应用） | 单个 WebRTC 连接的**媒体流** |
| **技术手段** | `tc` 命令，队列规则（qdisc）、分类器（filter）、整形（shaping） | 拥塞控制算法（GCC）、NACK/FEC、码率自适应、jitter buffer |
| **视角** | **网络基础设施**视角（管道管理） | **应用体验**视角（视频卡不卡、音频断不断） |

**具体交集点：**

1.  **当 WebRTC 的 GCC 算法检测到拥塞时**，它会主动降低发送码率。此时如果系统层面有 `net/sched` 的限流策略，两者会"协同作战"：
    - WebRTC："网络好像堵了，我少发点数据"
    - TC："整个网络出口确实拥堵，我在这里排队整形"

2.  **优先级映射**：你可以通过 `net/sched` 的 `prio` qdisc 给 WebRTC 的流量打上高优先级，让路由器/交换机优先转发。

3.  **Deep Packet Inspection (DPI)**：高级的 `tc` 配置可以用 `u32` 过滤器识别 WebRTC 的 RTP 包（基于端口、SSRC 等），然后单独对其进行限速或优先处理。

**总结**：`net/sched` 是修公路的（保证道路通畅），WebRTC QoS 是开车的老司机（根据路况调整车速）。对于音视频开发者，**你应该先精通 WebRTC QoS**，等需要做系统级优化时再了解 `net/sched`。

---

### 2. V4L2 为什么没有像音频一样拉出来个顶级目录？

这是个很好的观察！确实，音频有 `sound/` 这个顶级目录，而视频相关的 V4L2 代码却藏在 `drivers/media/` 里。这主要是**历史原因**和**架构差异**导致的：

#### 历史原因
- **ALSA (Advanced Linux Sound Architecture)** 在 2.6 内核早期就**重构**了旧的 OSS 驱动框架，形成了一个统一的、层次清晰的子系统，自然成为了顶级目录。
- **V4L2** 的发展更"渐进式"，一开始只是些零散的摄像头驱动，后来才抽象出共同的框架，但框架和驱动耦合更紧，没有像 ALSA 那样彻底剥离。

#### 架构差异
```
ALSA 的清晰分层：
sound/
├── core/          ← 核心框架（snd_pcm, snd_ctl）
├── soc/           ← 嵌入式系统通用层（ASoC）
├── pci/           ← PCI 声卡驱动
└── usb/           ← USB 音频驱动

V4L2 的"框架+驱动"混合：
drivers/media/
├── common/        ← 一些公共代码
├── platform/      ← 各种 SoC 平台的摄像头驱动（如 RK）
├── pci/           ← PCI 视频采集卡驱动
├── usb/           ← USB 摄像头驱动
└── i2c/           ← 摄像头传感器驱动（I2C 接口）
```

**关键区别**：ALSA 的 `core/` 实现了完整的音频流水线（PCM设备、Mixer、Timer），驱动只需要实现底层的硬件操作。而 V4L2 的框架相对较薄，很多复杂逻辑（如 ISP 图像处理）仍然留在具体的平台驱动里。

**对你来说**：找 RK 平台的视频驱动时，直接看 `drivers/media/platform/rockchip/` 就行，不必纠结为什么不在顶级目录。

---

### 3. 如何用 io_uring，是在服务端用的多吗？

#### io_uring 基本使用

io_uring 是 Linux 5.1+ 引入的**异步 I/O 新标准**，解决了传统 `libaio` 的诸多限制。基本使用流程：

1. **初始化 ring**：
   ```c
   struct io_uring ring;
   io_uring_queue_init(ENTRIES, &ring, 0);  // 创建 SQ/CQ ring
   ```

2. **准备提交队列 (SQ)**：
   ```c
   struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);  // 获取一个 SQE
   io_uring_prep_read(sqe, fd, buf, size, offset);      // 设置读操作
   sqe->user_data = (uintptr_t)my_callback_tag;         // 设置用户标识
   ```

3. **提交操作**：
   ```c
   io_uring_submit(&ring);  // 批量提交所有 SQE 到内核
   ```

4. **检查完成队列 (CQ)**：
   ```c
   struct io_uring_cqe *cqe;
   io_uring_wait_cqe(&ring, &cqe);     // 等待完成事件
   // 处理 cqe->res（结果）, cqe->user_data（标识）
   io_uring_cqe_seen(&ring, cqe);      // 标记为已处理
   ```

5. **清理**：
   ```c
   io_uring_queue_exit(&ring);
   ```

**高级特性**：
- **固定文件/缓冲区**：避免每次操作都 pin 内存
- **链式操作**：SQE 可以形成依赖链（先读后写）
- **轮询模式**：完全绕过中断，CPU 忙检查 CQ，追求极致延迟

#### io_uring 在服务端用的多吗？

**是的，io_uring 在服务端几乎是革命性的，但音视频领域同样受益巨大。**

| 场景 | 传统方式 | io_uring 优势 |
|------|----------|---------------|
| **Web 服务器** (Nginx) | `epoll` + 多线程 | 单个 io_uring 实例就能处理数万连接，减少线程上下文切换 |
| **数据库** (RocksDB) | 同步 I/O 或 `libaio` | 批量提交 I/O 请求，显著提升 SSD 的 IOPS |
| **音视频服务器** (FFmpeg 转码集群) | 多进程/线程 + `read/write` | 零拷贝 + 异步，大幅提升并发流处理能力 |
| **高帧率视频采集** | `poll` + `read` 或 `mmap` | 避免系统调用瓶颈，减少数据拷贝 |

#### 为什么音视频应该关注 io_uring？

1. **高帧率采集**：1000fps 的摄像头会产生海量的 `read` 系统调用，io_uring 的批量提交能彻底解决这个问题。
2. **零拷贝优化**：配合 `SPLICE` 操作，可以直接在内核态把摄像头数据管道传输到编码器，无需拷贝到用户空间。
3. **低延迟播放**：异步 I/O 让音视频渲染线程不会被阻塞，保证实时性。

**建议**：如果你是初学者，可以先掌握传统的 `epoll`+`nonblocking I/O`。但一定要把 io_uring 列入学习路线，这是未来的方向。可以从 `liburing` 这个用户态库开始尝试（封装了底层系统调用）。











