# WebRTC QoS 研发路线图（小a 版）

> 定位：29 岁，海康门禁部门（门口机/室内机），不想做安防，想切入**通用流媒体 / QoS 研发**。
> 约束：公司 QoS 简单（主要靠 RTCP NACK）、不投入人做、只能手机测试 → **无生产环境、无团队、无实战**。
> 目标：**不面初级工程师**，定位高级/资深（3-5 年+），用"自建可自证的项目"建立竞争力。

---

## 〇、核心结论（先看这个）

1. **门禁不是卖点，是"由头"**。面试官要的是**通用 WebRTC 实时音视频 + QoS** 能力，不是"你会做门禁对讲"。门禁只是你"为什么开始学"的背景故事，一句话带过。
2. **别等公司投入**。公司 QoS 简单、不投入、没真实弱网环境 → 你的策略必须是**自建环境 + 自证能力**，不依赖公司项目练手。
3. **定位高级工程师**：29 岁不能面初级。要展示的是**体系理解**（QoS 不只是 NACK，是拥塞控制/重传/抖动缓冲多维度）、**能写策略**（注入自定义 NetworkController）、**能搭环境做测量**（弱网模拟 + RTCStats 分析）。
4. **三条铁律**：不碰算法层（GCC/NetEq 别重写）、不碰完整产品（太大）、不做纯调参（太浅）。聚焦"**策略层/编排层**"。

---

## 一、今天（2026-09-08）的分析总结

### 1.1 QoS 扩展点（WebRTC 里能做什么）

QoS 不是单一模块，是**一组机制**，分三个层次：

| 层次 | 内容 | 位置 |
|---|---|---|
| **算法层**（别碰） | GCC 拥塞控制、NetEq、NACK/FEC、jitter buffer 算法 | `modules/` |
| **决策层**（可做） | 何时降码率、降哪层、要不要切 P2P、码率分配 | `call/` `video/` `audio/` |
| **编排层**（注入） | 用官方插槽替换/扩展 | Java/原生接口 |

**官方插槽（不改源码，直接注入）**：
- **`NetworkControllerFactoryFactory`**：Java `PeerConnectionFactory.Builder.setNetworkControllerFactoryFactory()`（sdk/android/api/org/webrtc/NetworkControllerFactoryFactory.java）→ 替换整个拥塞控制算法。**这是 QoS 最大的可做空间。**
- **`PeerConnectionFactoryDependencies.network_controller_factory`**：原生 C++ 侧（api/peer_connection_interface.h:1457）。
- **field_trials**：几十个开关，不改代码调参。**注意名称必须精确**（field_trials 是字符串匹配、无命名空间校验，写错的名字**静默不生效**）。M144 实测存在的：`WebRTC-SendNackDelayMs`（NACK 延迟，nack_requester.cc:46）、`WebRTC-JitterEstimatorConfig`（jitter_estimator.h:40）、`WebRTC-Bwe-LossBasedBweV2`、`WebRTC-Bwe-ProbingConfiguration`、`WebRTC-Bwe-ScreamV2`、`WebRTC-Pacer-*`（DrainQueue/KeyframeFlushing/PadInSilence 等）。⚠️ **不存在 `WebRTC-NACK-*` / `WebRTC-Jitter-*` 这类前缀**，别凭直觉拼。Android 注入通道：`PeerConnectionFactory.Builder.setFieldTrials()`（sdk/android/api/org/webrtc/PeerConnectionFactory.java:194）。

**QoS 的完整维度（面试要讲清楚，NACK 只是其一）**：
1. **拥塞控制（GCC）**：带宽估计，`OnTransportPacketsFeedback`/`OnProcessInterval` → `TargetTransferRate` → 调编码器码率。**核心**。
2. **丢包恢复（NACK/FEC/RTX）**：`NackRequester` 检测丢包 → 重传；FEC 冗余自恢复。**公司现在只做了这个**。
3. **抖动缓冲（NetEq/FrameBuffer）**：吸收网络抖动，视频 `VideoStreamBufferController`，音频 `NetEq`（含丢包隐藏 PLC）。
4. **pacing**：`TaskQueuePacedSender` 平滑发送，配合拥塞控制。

**一句话：公司"主要靠 NACK"说明只做了 QoS 的一个维度（丢包恢复）。你要展示的是完整的 4 维度体系——这正是你比公司现状"深"的地方。**

### 1.2 P2P 优先：架构性冲突，不是好设计（对 LiveKit/SFU）

- LiveKit 是 **SFU（服务端选择性转发）** 架构，核心价值就是媒体走服务端（统一 QoS、录制、审核、多端同步、E2EE 密钥管理）。
- **P2P 优先 = 绕过服务端 = 放弃 SFU 的能力和收费点**。要改：ICE 候选交换信令、第二条 PeerConnection、TURN 成本、多端同步、E2EE 密钥交换。
- **结论**：对 SFU 业务，P2P 优先通常不是好设计。除非纯 1v1 产品。业界做法是"**1v1 P2P + 多人 SFU**"混合，且 P2P 做成可选回退而非优先。
- **对门禁的启示**：门禁对讲很多是 1v1（门口机↔室内机），P2P 有场景。但这是**架构级改动，复杂度高**，作为进阶目标，不一开始碰。

### 1.3 门禁匹配度：不适合当卖点

- 门禁对讲是 WebRTC 的**小众垂直场景**，面试官要通用能力，不是垂直场景。
- **策略**：门禁是"为什么开始"，通用流媒体能力是"我有什么"。面试讲后者。

---

## 二、QoS 研发路线（3 个月，自建环境，不依赖公司）

### 阶段一（第 1 个月）：跑通通话 + 吃透 RTCStats

**目标**：能跑通一个 WebRTC 通话 Demo，看懂每个 QoS 指标。

**做什么**：
1. 用 WebRTC 原生（`examples/`）或 LiveKit 搭一个**最小可跑的通话 Demo**（Android 手机 ↔ 电脑）。
2. 用 `PeerConnection.getStats(RTCStatsCollectorCallback)`（sdk/android/api/org/webrtc/PeerConnection.java:1193）采集 QoS 指标。
3. 吃透 `RTCStatsReport`（getStatsMap()）里每个字段的含义。

**RTCStats 关键字段清单**（`RTCInboundRtpStreamStats` / `RTCOutboundRtpStreamStats`，实测 M144 stats/rtcstats_objects.cc 有 AttributeInit 定义的才算数）：
| 字段 | 含义 | 维度 |
|---|---|---|
| `packetsLost` | 累计丢包数 | 丢包 |
| `jitter` | 抖动（ms） | 抖动 |
| `roundTripTime` | RTT（ms） | 延迟 |
| `framesPerSecond` | 帧率 | 质量 |
| `bytesSent` / `bytesReceived` | 累计字节 | 质量（**码率要自己差分算**：两次采样差/时间差。⚠️ 没有 `bitrate` 字段，W3C 规范里码率是派生量） |
| `targetBitrate` | 当前目标码率（outbound-rtp） | 拥塞控制 |
| `totalPacketSendDelay` | 发送排队延迟 | pacing |
| `nackCount` / `pliCount` / `firCount` | NACK/PLI/FIR 次数 | 丢包恢复（PLI 比 FIR 常用，别漏） |
| `jitterBufferDelay` / `jitterBufferTargetDelay` | 抖动缓冲实测/目标延迟 | 抖动缓冲（**弱网分析核心指标**） |
| `freezeCount` / `pauseCount` | 视频卡顿/暂停次数 | 体验质量 |

**产出**：能跑的通话 + 一份 RTCStats 字段解读笔记。

### 阶段二（第 2 个月）：搭弱网环境 + QoS 对比实验

**目标**：能模拟弱网、量化 QoS 指标、对比不同配置。

**做什么**：
1. **弱网模拟**（不依赖公司，手机+电脑就能做）：
   - Linux：`tc netem`（`tc qdisc add dev eth0 root netem loss 5% delay 50ms jitter 20ms`）。
   - Mac：`Network Link Conditioner`。
   - 手机：开发者选项 → 网络模拟，或连电脑热点 + `tc`。
   - 模拟场景：丢包（1%/5%/10%）、延迟（50/100/200ms）、抖动、带宽限制（500kbps/1Mbps）。
2. **测量**：同一条链路，用阶段一的 RTCStats 采集工具，记录不同弱网下的丢包率/RTT/jitter/码率/帧率。
3. **对比实验**：同一弱网条件下，对比不同配置：
   - field_trials 开关（真实存在的：`WebRTC-Bwe-*`、`WebRTC-Pacer-*`、`WebRTC-SendNackDelayMs`、`WebRTC-JitterEstimatorConfig`）。
   - pacing factor（`WebRTC-Pacer-DrainQueue` 等）。
   - ⚠️ ~~jitter buffer 参数（`max_wait_for_keyframe`/`max_wait_for_frame`）~~ **不可直接配**：这两个值由 `DetermineMaxWaitForFrame()`（video/video_receive_stream2.cc:213-223）从 `rtp.nack.rtp_history_ms` 推导，换算因子写死为 3，而 `rtp_history_ms` 来自 SDP 的 `rtx-time` 参数（pc/codec_vendor.cc:472）——只能**通过 SDP 间接影响**，Java 层无开关。想调它就去改 SDP 里的 rtx-time。

**对比实验的正确做法——用 test/ 基建，不是真机+tc netem**（2026-09-08 核实，详见 2.5 节）：
真摄像头+真手机+tc netem 的数据噪声大到得不出结论（摄像头帧率漂移、手机温控降频、WiFi 波动全是变量）。WebRTC 的 `test/` 有现成的科学实验框架：
- **网络仿真**：`BuiltInNetworkBehaviorConfig`（api/test/simulated_network.h:83-104），一个结构体定义全部弱网参数（queue_delay_ms/delay_standard_deviation_ms/link_capacity/loss_percent/avg_burst_loss_length），进程内仿真、随机种子可复现，比 tc netem（真内核队列、随机不可复现）强。
- **确定性帧源**：`test/create_frame_generator_capturer`（固定帧率、固定内容，可重放）。
- **三层实验法**（由快到慢）：①算法级单测（modules/congestion_controller/goog_cc/*_unittest.cc 模式，喂假 feedback，断言 target_rate 轨迹——测你自己写的 NetworkController 用这层）②端到端（test/call_test.h 的 CallTest 基类，两个 Call + SimulatedNetwork 双管道）③真机（才用 tc netem，只做手感验证）。
- **真实例子**：video/end_to_end_tests/bandwidth_tests.cc:61 `ReceiveStreamSendsRemb`——继承 `test::EndToEndTest`，`ModifyVideoConfigs()` 改 RTP 扩展，`OnReceiveRtcp()` 拦截 RTCP 解析 REMB 并断言。把断言换成 OnTargetTransferRate、loss_percent 设 5%，就是"丢包 5% 时 GCC 多久降码率"的自动化验证。

**产出**：一份"弱网下 WebRTC QoS 表现分析报告"（含真实数据图表）+ 一套可复用的测量方法。

### 阶段二点五：test/ 基建详解——科学实验怎么做（2026-09-08 补充）

**为什么真机+tc netem 不科学**：摄像头帧率漂移、手机温控降频、WiFi 信号波动、后台进程抢占——全是不可控变量。对比实验要"控制变量"，变量控制不了数据就没有结论。WebRTC 官方 `test/` 目录就是为此而生的一套科学实验框架。

**三层实验体系**（由快到慢、由算法到系统）：

**层一：算法级单测**（最快、最可复现，测自己的 NetworkController 用这层）
- 位置：`modules/congestion_controller/goog_cc/*_unittest.cc`
- 原理：不建 Call、不建流，直接手工构造 packet arrival / TransportPacketsFeedback 序列喂给控制器，断言输出 target_rate 轨迹。
- 例子：`delay_based_bwe_unittest.cc` 的 `TEST_F(DelayBasedBweTest, ProbeDetection)`——构造一组探测包到达序列，断言 DelayBasedBwe 正确估计出探测码率。
- **用法**：你写完 `MyNetworkController`，照这个模式写 `MyNetworkControllerTest`：喂"丢包 5% 的 feedback 流"，断言 N 个周期内 target_rate 降到预期区间。几分钟跑完，CI 可重复。

**层二：端到端骨架**（CallTest 基类，测完整链路行为）
- 位置：`test/call_test.h`（基类）+ `video/end_to_end_tests/`（用例集）
- 原理：`CreateSenderCall/CreateReceiverCall` 建两个 Call 实例，中间接 `SimulatedNetwork` 双管道（send_simulated_network_ / receive_simulated_network_，call_test.h:226/235），帧源用 `create_frame_generator_capturer`（确定性、可重放）。
- 弱网配置：`BuiltInNetworkBehaviorConfig`（api/test/simulated_network.h:83-104），一个结构体：
  ```cpp
  BuiltInNetworkBehaviorConfig cfg;
  cfg.queue_delay_ms = 100;              // 延迟
  cfg.delay_standard_deviation_ms = 20;  // 抖动
  cfg.link_capacity = DataRate::KilobitsPerSec(500);  // 限速
  cfg.loss_percent = 5.;                 // 丢包率
  cfg.avg_burst_loss_length = 3;         // 突发丢包
  ```
- **真实例子**（video/end_to_end_tests/bandwidth_tests.cc:61 `ReceiveStreamSendsRemb`）：
  ```
  TEST_F(BandwidthEndToEndTest, ReceiveStreamSendsRemb):
    继承 test::EndToEndTest
    ├ ModifyVideoConfigs()   ← 定制 RTP 扩展/编码配置（这里是 abs-send-time）
    ├ OnReceiveRtcp()        ← 拦截每个 RTCP 包，解析 REMB 就断言 SSRC/码率合法
    └ PerformTest()          ← Wait() 到点或超时失败
  ```
  把断言换成 OnTargetTransferRate、loss_percent 设 5% → 自动验证"丢包 5% 时 GCC 多久降码率"。这就是"弱网 QoS 对比实验"的官方模板。
- 同目录还有现成的 `fec_tests.cc`（FEC 恢复能力）、`call_operation_tests.cc`、`corruption_detection_tests.cc`——你的阶段二实验报告可以直接基于这套用例改。

**层三：真机 + tc netem**（只做手感/最终验证）
- `tc netem` 是真内核网络栈，随机性强、不可精确复现。适合最终"人眼/手感"验证，不适合做数据。
- **推荐拓扑：手机 USB 共享 Ubuntu 网络**（2026-09-08 确认可行）——手机用 Ubuntu 的网，Ubuntu 是网关，控制点成立。反方向（Ubuntu 连手机热点）不行，Ubuntu 只是客户端控不了流量。USB 还比 WiFi 热点少一个射频波动变量，适合对照实验。

  ```
  手机 ──usb0──> Ubuntu ──eth0──> 互联网
  互联网 ──eth0──> Ubuntu ──usb0──> 手机
  ```
  **关键坑：上行/下行分开配**。netem 默认只作用在发送方向：
  - 下行（服务器→手机）：直接在 `usb0` 发送方向挂 netem ✅
  - 上行（手机→服务器）：流量从 usb0 进、eth0 出。netem 挂不了 ingress，在 `eth0` 上用 u32 filter 只对手机 NAT 前源 IP（如 192.168.42.129）挂 netem：

  ```bash
  # 下行：丢包5% + 延迟50ms±20ms（影响手机收到的包）
  tc qdisc add dev usb0 root handle 1: netem delay 50ms 20ms loss 5%

  # 上行：只对手机的流量（eth0 过滤源 IP）
  tc qdisc add dev eth0 root handle 1: prio
  tc qdisc add dev eth0 parent 1:3 handle 30: netem delay 50ms loss 5%
  tc filter add dev eth0 parent 1:0 protocol ip u32 match ip src 192.168.42.129 flowid 1:3

  # 带宽限制用 tbf（别用 netem rate，精度差）
  tc qdisc add dev usb0 root tbf rate 500kbit burst 32kbit latency 400ms
  ```
  **操作要点**：
  1. 手机飞行模式 + 只开 USB 共享（飞行模式下 USB 共享仍可用）——杜绝手机 WiFi/蜂窝背景流量噪声。
  2. 先测基线（不加 netem 跑一遍）——确认 USB 共享本身（ADB/存储挤占、Ubuntu 上行带宽）不是瓶颈，否则 5% 丢包叠加在未知基线上。
  3. 突发丢包模型更真实：`tc netem loss 0.5% 25%`（gilbert-elliot 近似），比独立丢包 `loss 5%` 接近真实网络。两种都测。
  4. **白送的抓包能力（本拓扑最大附加价值）**：`tcpdump -i usb0 -w webrtc.pcap` 直接抓手机全部 RTP/RTCP，与手机端 RTCStats 互证（stats 说 nackCount=47，pcap 里数 NACK 包验证）——**终端指标与网络层实据互证**，这个能力面试直接讲。

**三层怎么选**：
| 要验证什么 | 用哪层 |
|---|---|
| 自己写的 NetworkController 行为 | 层一（单测喂 feedback） |
| GCC/NetEq/NACK 在完整链路上的表现 | 层二（CallTest + SimulatedNetwork） |
| 真实设备上的体验 | 层三（tc netem） |

**面试价值**：能讲出"我用 SimulatedNetwork + frame_generator 做确定性可复现的对比实验，而不是真机上碰运气"——这本身就是高级工程师和调参侠的分水岭。

### 阶段三（第 3 个月）：注入自定义 NetworkController（升华）

**目标**：能写 QoS 策略，展示"研发"深度，不是调参。

**做什么**：
1. 用 `NetworkControllerFactoryFactory` 注入一个**自定义 NetworkController**（Java 侧创建原生工厂）。
2. 在 `OnTransportPacketsFeedback`/`OnProcessInterval` 里加**自己的带宽估计逻辑**（哪怕是一个简化的丢包-based 控制器）。
3. 对比默认 GCC 和你的控制器的 QoS 表现（用阶段二的弱网环境）。

**Java 侧代码骨架**（NetworkControllerFactoryFactory.java）：
```java
public class MyNetworkControllerFactoryFactory implements NetworkControllerFactoryFactory {
  @Override
  public long createNativeNetworkControllerFactory() {
    // 返回 webrtc::NetworkControllerFactory 的原生指针（JNI 创建）
    return nativeCreateMyNetworkControllerFactory();
  }
  private static native long nativeCreateMyNetworkControllerFactory();
}

// 使用：
PeerConnectionFactory.Builder builder = PeerConnectionFactory.builder();
builder.setNetworkControllerFactoryFactory(new MyNetworkControllerFactoryFactory());
```

**原生侧**（C++，`NetworkControllerInterface`，api/transport/network_control.h:63）：
```cpp
class MyNetworkController : public NetworkControllerInterface {
 public:
  // ⚠️ 接口 12 个方法全部带 ABSL_MUST_USE_RESULT，返回 NetworkControlUpdate
  // ⚠️ 参数类型是 ProcessInterval（不是 IntervalConfig——别和 NetworkControllerConfig 混淆）
  NetworkControlUpdate OnTransportPacketsFeedback(
      TransportPacketsFeedback report) override {
    // 自己的带宽估计逻辑：根据丢包率/吞吐调整 target_rate
    // 例：丢包 > 5% 时降码率，否则维持
  }
  NetworkControlUpdate OnProcessInterval(ProcessInterval msg) override {
    // 周期更新 TargetTransferRate（默认 25ms，kUpdateIntervalMs，
    //   api/transport/goog_cc_factory.cc:52）
  }
};
```

**⚠️ 2026-09-08 修正：这条路（LiveKit 上做 stage3）走不通，正确路径是自编译**：
- LiveKit 依赖的是 **LiveKit 自编译的 `livekit.org.webrtc` 前缀包**（android-prefixed:144.7559.09，正是本地 webrtc-m144_release 编出来的）。LiveKit 的 `PeerConnectionFactoryManager` 没有暴露 NetworkControllerFactoryFactory 注入点，走 LiveKit 就做不了 stage3。
- **正确路径**：改自己编的 AAR——C++ 侧写 `MyNetworkControllerFactory`（实现 `NetworkControllerFactoryInterface`，network_control.h）+ Java 侧工厂桥（`createNativeNetworkControllerFactory` 返回原生指针）+ JNI 注册。**JNI 桥接 + so 编译是核心工作量**，上面 Java 骨架里的 `nativeCreateMyNetworkControllerFactory()` 一行就是最难的部分，别低估。
- **你的独家优势**：本地有完整 webrtc-m144 源码 + GN/Ninja 环境，`android-prefixed:144.7559.09` 就是这套源码编的——链路现成，别人（没源码环境的竞争者）做不到。面试时这一点要讲出来。

**产出**：自定义拥塞策略 Demo + 设计文档（对比默认 GCC 的改善数据）。

### 3 个月总览

| 阶段 | 做什么 | 产出 | 面试价值 |
|---|---|---|---|
| 第 1 月 | 跑通通话 + 吃透 RTCStats | 能跑的通话 + 字段解读 | "我能跑通实时音视频" |
| 第 2 月 | 弱网模拟 + QoS 对比 | 弱网 QoS 分析报告（真实数据） | "我会测、会分析 QoS" |
| 第 3 月 | 注入自定义 NetworkController | 自定义拥塞策略 Demo + 文档 | "我能做 QoS 策略研发" |

---

## 三、安卓 / 后端等其它需要掌握的能力栈（针对 29 岁高级工程师）

> 29 岁不能面初级。**初级看"会不会用"，高级看"体系、权衡、故障、性能、架构"**。下面是按"高级工程师"标准的能力栈，分主次。

### 3.1 安卓（客户端，你的主场）

**必须扎实（面试必问）**：
- **自定义 View / 渲染管线**：`SurfaceViewRenderer`/`TextureViewRenderer` 怎么渲染视频帧、EGL 纹理、`onDrawFrame` 回调。做引擎必懂。
- **线程模型**：主线程/worker/网络线程 + **Handler/Looper** 机制（WebRTC 三线程模型的安卓对应物）。**这是高级工程师的核心题**。
- **内存/性能**：`LeakCanary`/`Profiler` 定位内存泄漏、卡顿（jank）、ANR。WebRTC 视频是内存大户，要能分析。
- **JNI 层**：`@CalledByNative`、`NativeLibrary`、JNI 引用管理（local/global reference）。你文档里已掌握，面试是加分项。

**加分（体现深度）**：
- **MediaCodec 硬件编解码**：`HardwareVideoEncoder`/`MediaCodecVideoDecoderFactory` 的 buffer 流转（input/output buffer、颜色格式转换）。
- **Camera2 API**：`Camera2Capturer` 的采集管线、`ImageReader`、帧率控制。
- **Kotlin 协程/Flow**：现代安卓开发，LiveKit 用协程，面试会问。

### 3.2 后端（SFU / 服务端，QoS 决策的另一半）

**为什么重要**：QoS 的"决策"很多在服务端（SFU 带宽分配、码率控制、录制）。只懂客户端是"半个流媒体工程师"。

**必须掌握**：
- **SFU 架构**：`LiveKit Server`（Go）/ `mediasoup`（Node.js）/ `Janus`（C++）的转发模型。**能讲清楚 SFU 和 MCU 的区别**（转发 vs 混流）。
- **信令**：WebSocket + protobuf/JSON，offer/answer 交换，ICE 候选。你文档里的 `SignalClient` 链路。
- **网络基础**：TCP/UDP 区别、NAT/STUN/TURN、ICE 状态机、DTLS-SRTP。**这是流媒体后端的地基**。

**加分（体现架构）**：
- **Go 或 Node.js**：能看懂/写简单的 SFU 服务端逻辑（LiveKit Server 是 Go）。
- **分布式**：多 SFU 节点、房间路由、媒体转发拓扑。
- **监控/可观测**：`Prometheus`/`Grafana` 采集 QoS 指标（丢包/RTT/码率），服务端 + 客户端指标汇总。**这是"QoS 研发"的落地形态**。

### 3.3 通用能力（高级工程师的"软实力"）

- **性能分析**：会用 `perf`/`top`/`Profiler` 定位 CPU/内存/IO 瓶颈。视频编解码是 CPU 大户。
- **网络抓包**：`Wireshark`/`tcpdump` 抓 RTP/RTCP 包，分析丢包、重传、FEC。**这是 QoS 研发的必备技能**。
- **Linux 基础**：`tc netem`、`ip`、`ss`、`iftop`。弱网模拟和网络诊断都要用。
- **英语文档**：WebRTC spec（w3c webrtc-stats）、RFC（RFC3550 RTP、RFC4588 RTX、RFC5109 FEC）。能读 spec 是高级工程师的标配。

### 3.4 优先级排序（29 岁高级工程师，时间有限）

| 优先级 | 方向 | 理由 |
|---|---|---|
| 🥇 | **安卓线程模型 + 渲染管线 + 内存性能** | 客户端主场，面试必问，你已有基础 |
| 🥈 | **网络基础（NAT/TURN/ICE/DTLS-SRTP）** | 流媒体地基，QoS 研发绕不开 |
| 🥉 | **SFU 架构 + 信令** | 后端决策层，体现"完整流媒体"视野 |
| 4 | **QoS 指标监控（Prometheus/Grafana）** | QoS 研发的落地形态 |
| 5 | **Go/Node.js + 分布式** | 加分项，锦上添花 |

---

## 四、面试策略（29 岁高级工程师）

### 怎么讲门禁（关键）
- **不要**："我在海康做门禁对讲，会 WebRTC。"
- **要**："我在海康接触了实时音视频（门禁对讲是切入场景），但**我专注的是 WebRTC 通用实时音视频 + QoS**。我自己搭了弱网环境，研究了 GCC 拥塞控制、NACK、NetEq 的完整体系，做了一个自定义拥塞控制策略，对比默认 GCC 有 X% 改善。"

### 展示"高级"而非"初级"
| 初级表现 | 高级表现 |
|---|---|
| "我会用 RTCStats 读指标" | "我理解 QoS 是拥塞控制/重传/抖动缓冲多维度，NACK 只是其一" |
| "我调了 field_trials 参数" | "我注入自定义 NetworkController，对比默认 GCC 有 X% 改善" |
| "我做了门禁对讲" | "我掌握了通用实时音视频 + SFU 架构 + 弱网 QoS" |
| "我会安卓" | "我懂线程模型、渲染管线、内存性能，能定位卡顿/泄漏" |

### 简历亮点（3 个月后能写）
1. **"自建弱网环境，量化 WebRTC QoS 在丢包/延迟/抖动下的表现，产出分析报告"** —— 证明测量与分析能力。
2. **"用 NetworkControllerFactoryFactory 注入自定义拥塞控制策略，对比默认 GCC 有 X% 改善"** —— 证明策略研发能力。
3. **"吃透 WebRTC 三线程模型 + 渲染管线 + RTCStats 全字段"** —— 证明体系理解。

### 求职目标分层：主攻引擎岗，业务岗是保底（2026-09-08 补充）

**目标优先级**：
- 🥇 **主目标：音视频引擎岗**（引擎策略/优化/QoS 方向）——冲刺方向，3 个月路线全部为此准备。
- 🥈 **保底：音视频业务/优化岗**（大平台直播/会议/连麦的上层业务，不太涉及 QoS）——退而求其次，但依然在同一能力圈内。
- **不是放弃**：保底岗在职期间继续准备（自编译 AAR、NetworkController Demo、弱网报告），**积累 6-12 个月后以"有引擎岗所需全部证据"的姿态二次冲刺**。
- **保底岗真正能攒到的三样东西**（2026-09-08 修正，别把"大规模线上问题"当必要条件——没规模之前别硬编）：
  1. **真实机型矩阵**：公司设备池远超个人手机，MediaCodec 各厂商差异（颜色格式/关键帧语义/输入缓冲）是实打实的引擎知识。
  2. **真实场景约束**：低端机内存、后台杀进程、生产环境不能乱开 field_trials——这种约束感是没上过生产的人没有的。
  3. **行业在场感**：在职身份 + 音视频圈信息 + 内推网络。
- **"线上问题"的正确替代——自造真实问题**（价值在"现象→假设→工具→证据→结论"的完整排障过程，不在用户规模）：①自建弱网环境把 loss 10%+burst 打开，观察 pliCount/nackCount/jitterBufferDelay 联动；②自编译 AAR 必踩的坑（NDK 版本/符号裁剪/机型 MediaCodec 差异/SRTP 协商失败）；③自己写的 NetworkController 翻车场景（丢包-based 控制器在带宽突变时的震荡）——分析自己的策略为什么不如 GCC 稳，反而是好故事。
- **面试措辞**：别说"我处理过大规模线上问题"（会被追问穿）。要说："我的环境是自建的，但我做的是**确定性可复现的实验**——相同弱网参数跑十次结果一致，比偶发线上问题更能定位因果。真实线上问题是噪声里找信号，我的方法是先建立无噪声的因果基线，再放到真机上验证。"——把"没有大规模"翻转成方法论优势，而且是真的。

**两套叙事，同一套准备**（不用做两份功课，只换侧重点）：

| | 引擎岗叙事（主） | 业务岗叙事（保底） |
|---|---|---|
| 卖什么 | 自编译源码 + 注入 NetworkController + 科学实验法 | 全链路地图 + 排障方法论 + 能改引擎的兜底能力 |
| 开场 | "我做了自定义拥塞策略，对比 GCC 有 X% 改善" | "我能从 Java 接口追到 jitter buffer 行号" |
| QoS 深度的角色 | 主菜 | 溢价（"疑难杂症时我比团队多一条路"） |
| 面试官听到的信号 | 这人能做策略研发 | 这人的问题定位半径比团队现有的人大一层 |

**业务岗价值四抓手**（保底时怎么讲）：
1. **链路地图当作品**：画出 VideoSource → VideoStreamEncoder → RtpVideoSender → PacedSender → SRTP → RtpDemuxer → PacketBuffer 组帧 → FrameBuffer → 解码 → 渲染，标注每环节所在线程。
2. **定位故事代替知识清单**：备 2-3 个"现象→假设→工具(stats/pcap/日志)→证据→结论"案例——如"偶发花屏→抓包+pliCount 确认参考帧丢失""jitterBufferDelay 持续增长→时钟 drift 非网络"。
3. **QoS 知识转业务语言**："我知道码率是拥塞控制自动调的，上层只配边界；能分清'调参能解决的'和'要改架构的'"——回答"会不会太理论"的隐忧。
4. **证明能交付上层业务**：LiveKit 事件总线/状态机/重连/E2EE 应用层完整经验 + 安卓主场（线程/渲染/JNI）。

**关键认知**：业务岗人才池里"会调 SDK 的"一大把、"能钻进引擎源码的"极少——你的引擎准备在业务岗面试是**降维打击**，保底 offer 大概率比纯业务背景的竞争者更容易拿。所以保底不是妥协，是策略：**先进场（大平台音视频业务），在职继续攒引擎证据，二次冲刺引擎岗**。

### 四-B、自研轻量后端 + 个人项目的定位（2026-09-09 补充）

小a手里还有一个自研轻量项目：C++ reactor 后端（房间管理 + WHIP/WHEP + WebSocket 信令）+ 浏览器 JS 客户端（借浏览器原生 WebRTC），libwebrtc 走 P2P。

**架构疑点先厘清（面试必被问）**：WHIP/WHEP 是 HTTP 基协议、面向"对接媒体服务器"的推/拉流接口，不是浏览器对浏览器的 P2P 信令。若核心信令是 WS 自定义协议，WHIP/WHEP 只在"设备推服务器、浏览器从服务器拉"时有意义——这暗示项目实际形态是 **SFU 雏形（single-relay）**而非纯 P2P。先画清楚架构图（WS 交换 offer/answer/candidate？后端是否当 peer 一进一出？），否则被问"为什么同时有 WHIP/WHEP 和 WS 信令"答不上会掉一半可信度。

**水平定位**：优秀的学习型项目，入门级的产品雏形。覆盖面好（信令/房间/媒体控制/HTTP 接口/网络模型 = 简化一个量级的 LiveKit），但深度差三样——①无 QoS 观测（stats 采集/上报/面板）②无规模（并发房间？reactor 线程怎么配？）③无可靠性工程（断线重连、ICE restart、renegotiation）。这三样是"学习项目"和"生产项目"的分界线。

**扩充原则——往深扩一件，不往全扩**，按性价比排序：
1. 🥇 **加 QoS 观测闭环**（最推荐，一周级）：RTCStats 采集 → WS 上报后端 → 存储 → 曲线。把项目从"能通话"变成"能测量"，与本文档阶段一/二的实验合并——**一个项目两条叙事线**（后端工程能力 + QoS 实验平台）
2. 🥈 **断线重连 + ICE restart（与观测闭环同期做掉，不排期二阶段）**：两者共享同一套弱网实验环境（实验里拉网线/断网就能测重连），两三天工作量。理由很具体：面试官几乎必问"你的项目弱网/断网怎么办"，现在的回答是"没做"，加上它们回答变成"做了，实测过"
3. 🥉 自建 coturn：**降级为"报告需要时再说"**——弱网实验是 netem 注入，不需要真 NAT 穿透；coturn 只在演示"打通率"话题时有价值，那不是主叙事
4. ❌ 不做：堆并发、多级架构、分布式——那是后端基建岗的活，对引擎/QoS 目标无加分
5. ❌ 不做：SIP/多协议网关、录制/Egress、权限模型（LiveKit 有完整实现，复刻简化版没有增量价值）、WHIP/WHEP 协议完备性（认证/ICEServers 协商/204 语义全套——RFC 忠实度是协议岗的卖点，不是我们的）

**加功能的判断标准（以后每次想给这个项目加东西，先问一个问题）**：
> **"这个东西能不能写进弱网 QoS 报告，或者成为面试里一个取舍故事？"**
> - 能 → 做（观测、重连、对照组数据都能）
> - 不能 → 不做（协议完备性、架构堆量、功能广度都不能）

做完观测闭环 + 重连/ICE restart 后**功能冻结**，只留两个后续动作：第 4-6 月的文档化（对照分析），以及为报告补数据时的小改动。**"能讲出取舍的边界，比代码里多十个模块专业得多"——这是高级工程师和初级工程师在同一个项目上的分水岭。**

**与 LiveKit 的关系——别结合代码，当对照组**：
- 协议层结合不划算（LiveKit Server 是 Go 完整 SFU + 私有 protobuf-over-WS，C++ 信令接不进去，"兼容 LiveKit 协议"= 重写它的客户端，无意义）
- 并存可以（Web 端走自研、移动端走 LiveKit SDK；或设备 WHIP ingress 推给 LiveKit）
- **对照组价值最大**：自研项目每一层去 LiveKit 找对应物（房间管理 ↔ Room/Participant，WS 信令 ↔ SignalClient/protobuf），对照分析"产品化到底加了什么"（订阅模型/DynamicBroadcast/region 路由/Egress/Webhook/权限模型）——写进文档，含金量比集成 demo 高

**两个项目各司其职**（别重复加 QoS）：

| | 自研轻量后端 + JS 客户端 | LiveKit + 自编译 webrtc AAR |
|---|---|---|
| 叙事角色 | 全链路理解 + **测量平台** | 引擎深度 + **改造能力** |
| QoS 动作 | 观测闭环：stats 采集→上报→存储→曲线，成为弱网实验平台 | 注入 NetworkController 对比 GCC |
| 面试主打 | "我能从信令到媒体全链路排障" | "我能改引擎并量化改进" |

合起来一个故事："我从零搭了信令和测量（后端项目），钻进引擎改了算法（AAR），用同一套测量方法证明改进"——闭环。

### 四-B-2、协议岗评估：不适合当主攻，但材料天然覆盖（2026-09-09 补充）

"协议岗"在 2026 年市场里实际是什么，逐类看：

| 岗位类型 | 实际干什么 | 市场量 | 对小a 的匹配度 |
|---|---|---|---|
| **标准协议栈岗**（SIP/JSEP/RTCP/QUIC/RTP） | 视讯会议/SBC/网关设备的协议实现与互通 | 少，集中在华为/中兴/亿联等视讯或电信设备商 | ⚠️ 电信系公司的技术栈偏 SIP/SDP 老协议簇，和 WebRTC 现代栈有重叠但不重合；缺 SIP 功底，且进去容易陷在电信协议里，反而离 WebRTC 引擎更远 |
| **互通/网关岗** | WebRTC↔SIP、WHIP/WHEP ingress、SIP trunk（LiveKit/mediasoup 生态都有这活） | 少而专，通常 1-2 人/公司 | ⚠️ 要 SIP 功底，没有 |
| **协议安全岗**（DTLS/SRTP/密钥协商） | 加密传输、合规 | 极少，一般并入引擎岗 | 同引擎岗要求 |
| **应用层协议设计岗**（信令协议/protobuf 接口演进） | SDK 侧 API/协议演进 | **不是独立岗位**，是 SDK 工程师工作的一部分 | ✅ 后端项目 + LiveKit 对照已覆盖 |

**结论：市场上不存在足够多的"纯协议岗"供投递**——它要么是电信设备商的 SIP 系（缺 SIP 且技术栈偏老），要么就是引擎/SDK 岗的一个组成部分。所以：**不把职业定位换成协议工程师，但把协议深度当引擎/SDK 岗面试的子卖点**——手里的牌已经够了：M144 源码分析里 JSEP/ICE/DTLS-SRTP/trickle 整条协议链追到行号级（wr-signaling-analysis.md），LiveKit 的 protobuf 信令协议也读了。面试时的讲法："我追过 ICE 状态机、DTLS 密钥导出（ExtractParams:230）、trickle 候选交换的完整实现"——这比"我了解 WebRTC 协议"的泛泛之谈硬一个量级。

**一个例外**：亿联/MaxHub 这类 **WebRTC 视讯设备商**的协议岗是 WebRTC 系的，设备端 + WebRTC + 门禁背景的组合在那里意外对口。但那是设备商路线，与"不回安防/IoT 硬件"的决定有张力——除非把边界划成"不去萤石系安防，但通用 WebRTC 视讯设备商可投"。这个边界小a 自己拿捏，不作默认推荐。

**海康内部"协议岗" vs 互联网"协议岗"——同名不同物（2026-09-09 补充，来自老员工建议的插曲）**：

老员工推荐协议岗（"小红书招协议岗工资很高"）时，大概率指的是海康内部视角的协议——**目的地他说对了，路径他说反了**：

| | 海康内部协议岗 | 互联网高薪协议岗（小红书等） |
|---|---|---|
| 实际内容 | ISAPI（HTTP 基私有设备接口）/ GB28181（基于 SIP 的国标联网）/ ONVIF / 嵌入式定制协议 | RTP/RTCP、WebRTC 传输栈、QUIC/HTTP3、自研传输与弱网优化 |
| 本质 | **接口设计/标准对接**，价值锁死在安防生态 | **现代实时传输协议工程**，市场稀缺 |
| 对小a 路线的意义 | ❌ 往垂直再扎一层，做了 3 年 GB28181/ISAPI 换不来互联网协议岗的入场券（两个应用域） | ✅ 就是 QoS 主线正在堆的那一层 |
| 老员工为什么推荐 | 视角偏差而非忽悠——从海康内部看，标准化组确实体面稳定（评级/行业地位） | 他引用的市场信号是真的：协议深度确实有溢价 |

**过滤框架**（半年里还会遇到各种内部建议，用这个判断）：
1. 看 JD 关键词：出现 `RTP/RTCP/QUIC/WebRTC/传输/拥塞/直播` → 与路线吻合，加进目标清单；出现 `SIP/GB28181/国标/信令网关` → 电信系/安防系，按本节评估处理
2. **不接海康内部转向协议标准化的机会**（如果有）：看着是升维，实际是"设备端音视频"→"安防协议"的换赛道——门禁 2 年的实时音视频底盘比 ISAPI 经验对目标市场值钱
3. 这个插曲当**市场验证**用：连海康老员工都在传"协议岗高薪"= 传输/协议深度确实稀缺溢价，QoS 主线押对了，更笃定，不改方向

### 四-B-3、后端项目怎么讲：不是门口机的项目，三层讲法（2026-09-09 补充）

**先拆心障**：高级工程师的个人项目不需要是工作项目的延伸。面试官对 5 年+ 候选人的项目问题只有三个——解决了什么问题、做到什么深度、能讲出什么取舍。项目"从哪来"在这三个问题的回答质量面前几乎不重要。初级岗才看"公司项目经历"，高级岗看"你自己能发起并完成什么"。所以"它不是门口机项目"这个顾虑，在目标岗位上不成立。

**分层讲法**（从浅到深，按面试官追问深度自动下探）：

**第一层·为什么做（30 秒）——不提门口机，提职业判断**：

> "我做了几年设备端音视频，想把实时音视频的**全链路**吃透——不只是客户端那一半。读源码只能理解它，自己从零搭一遍信令和会话层才能验证理解。所以我搭了一个最小可用的后端：房间管理、WS 信令、WHIP/WHEP ingress，客户端用浏览器原生 WebRTC。"

要点：**项目动机是"体系化理解实时音视频"，不是"我想做个产品"**——这正是引擎岗面试官想听的方向感。也是它不是工作延伸的最自然解释：主动补的体系课。

**第二层·做到什么深度（2 分钟）——用 LiveKit 对照当弹药**：

> "搭的过程中我发现 WHIP/WHEP 和浏览器 P2P 信令是两条不同的路：WHIP 是 HTTP 基协议、面向和服务端对接，P2P 是 WS 交换 SDP/候选。我把两条都做了，所以我能讲清楚什么时候该用哪个、为什么 LiveKit 的 ingress 走 WHIP 而它的客户端信令走私有 protobuf-over-WS。"
> "线程模型是 C++ reactor，我对比了 libwebrtc 自己的三线程+消息循环设计——同一个问题（高并发 IO + 串行化），两边用了不同的答案，为什么。"

这一层的技巧：**每讲一个自己做的模块，都带一句"LiveKit 在这层是怎么做的"**。这就是普通个人项目和高级工程师个人项目的区别——有参照系、有取舍。

**第三层·怎么和门禁闭环（被问"这和你的工作有什么关系"时）——门口机此时才出场，角色是"问题来源"不是"项目归属"**：

> "直接关系不大，这是我主动补的体系课。但它立刻反哺了工作：我们设备端音频的抗抖动层是我写的，之前只是照需求实现；把 libwebrtc NetEq 的 target delay 机制和后端实验里看到的 jitter 特性对照后，我重新审视了我们双水位策略的适用边界——什么网络条件下它会失效。"

一句话总结这个讲法：**"主动补体系 → 做出取舍判断 → 反哺生产代码"**。第三层的"反哺"是小a 独有的——大多数自建项目的人没有生产代码可以反哺，手里有 audio_neteq，这是真实生产经验和个人项目之间的桥，也是别人抄不走的组合。

**配套动作**：简历"个人项目"栏，项目名别叫 demo，叫它的问题域——例如"轻量 WebRTC 会话服务（房间/信令/WHIP-WHEP ingress）"，一行说清范围；两个特性描述 = QoS 观测闭环 + 断线重连/ICE restart（做完 0-2 月的扩充后）。

### 四-C、组内项目挖掘：audio_neteq 是主弹药（2026-09-09 补充）

**先修正问题预设**：29 岁高级工程师的自建项目不是减分项，**包装成组内项目才是减分项**。正确姿势是简历"个人项目"栏老实标自建，面试用"问题→方法→数据→源码验证"结构讲——由头来自门禁（门禁对讲弱网卡顿是问题来源），项目是为解决问题自建的，逻辑就闭环了。诚实的自建 + 有深度的结论 > 含糊的"参与过类似项目"（后者一追问就穿）。

**组内（dsp-4-vi）素材对照表**——这才是能以"作者/参与者"身份讲的组内项目：

| 组内组件 | libwebrtc 对应物 | 面试讲法 |
|---|---|---|
| **audio_neteq**（alg_aud_neteq.c，614 行，**本人写的封装层**：init/deinit/create/destroy/send_data/get_data 六接口 + 通道管理 + 互斥） | `NetEqImpl::InsertPacket/GetAudio`（neteq_impl.cc:184/:432） | "我在设备上做音频抗抖动通道管理，对照 libwebrtc NetEq 的 expand/fade/PLC 看我们的简化取舍"——**主弹药，唯一能以作者身份讲的组内项目，正好落在 QoS 主题上** |
| **audio_pro**（alg_aecsp/agc/anr/eq/resample 等 ~5800 行封装） | `AudioProcessingImpl`（AEC3/NS/AGC1/AGC2 管线） | "设备端 AEC/AGC/NS 工程集成，与 APM 管线顺序一致：采集侧先 AEC 再 NS 再 AGC" |
| audio_quality_det（啸叫/回环/静音/声音检测） | 无对应（WebRTC 不做质检，安防特色） | 弱化一句"做过音频质量检测"，不展开 |
| KWS 插件（plugin_kws.c：注册音采集/DFX/唤醒超时） | 无对应 | 只在"语音入口"叙事里提 |
| TTS 插件（plugin_tts.c：ping-pong 缓冲/4 路混音/会话超时释放） | 无对应 | 同上 |

**KWS + TTS + 对讲 = 完整的"设备端语音 Agent"入口**（喊唤醒→对讲→TTS 播报，模型是研究院的，管道是你们的）——2026 年 AI 实时语音语境里的现成 hook。

**开源 vs 组内分工——两个都要**：
- 组内素材（audio_neteq/audio_pro）→ 简历"工作经历"栏：证明**生产经验**（真实产品里做过音频 QoS 工程）
- 开源自建（LiveKit+自编译 AAR+轻量后端）→ "个人项目"栏：证明**通用能力**（理解体系+能改引擎）
- 缺一不可：只有前者被问"离开海康还能干啥"；只有后者被问"你没做过真实产品"
- ❌ **不要用开源重写组内的东西**（如拿 libwebrtc NetEq 替换设备端 neteq）——对着 614 行自有代码做无用功，6 个月要花在注入 controller 主线上

### 四-D、LiveKit Agents 是什么 + LLM 经历处理（2026-09-09 补充）

**纠正误解：LiveKit Agents 不是安卓上层框架**，是**服务端 Python/Node 框架**，与安卓/libwebrtc 客户端无关：

```
┌─ 浏览器/手机/设备（客户端）── LiveKit SDK（安卓 SDK 在这层，纯 WebRTC）
│        ↓ RTC 媒体流
├─ LiveKit Server（Go，SFU）── 房间管理、媒体转发
│        ↓
└─ Agents 进程（Python）── 以"参与者"身份加入房间：
     收音频帧 → 流式 ASR → LLM → 流式 TTS → 发回房间；管理打断/VAD/对话状态
```

- 客户端不需要装任何 agent 框架，普通 SDK 就能和 Agent 通话；Agents 是"会说话的机器人参与者"，活儿是**编排 ASR/LLM/TTS 三个外部服务**，不碰 WebRTC 内部
- **对 RTC 工程师的意义**：生态缺的不是写 Python 胶水的人，是**懂低延迟管道**的人——首包延迟、打断链路（客户端 VAD→服务端截断 TTS）、弱网下的 agent 体验，全是 RTC 问题

**Agents 到底干什么（追问到功能层）**——它自己**不做任何模型推理**，全是调外部接口的编排层：

```
Agents 进程（pip install livekit-agents，Python）
├─ 以"参与者"身份加入 LiveKit 房间（和普通用户一样走 RTC）
├─ 收用户音频帧（10ms 一帧 PCM）
├─ ─→ 调外部流式 ASR（Deepgram / AssemblyAI / 火山 / OpenAI Realtime…）
├─ ─→ 调 LLM（GPT / Claude / 任意 OpenAI 兼容接口，含 function calling）
├─ ─→ 调外部流式 TTS（ElevenLabs / Cartesia / Azure…）
├─ ─→ 合成语音帧发回房间（仍是标准 RTC 音频流）
└─ 框架管的横切面：VAD（谁在说话）、打断（用户开口→立刻掐掉 TTS）、
   上下文管理、转写显示、电话接入（SIP）、多 Agent 转接
```

用途：AI 客服/语音助手、销售外呼、AI 面试官/口语陪练、会议纪要、直播数字人。**岗位含义**：这些产品全要低延迟管道（首包 < 800ms 才能用），模型是别人的，**延迟是你的**——每家做 voice agent 的公司都需要 RTC 底座优化的人。

**LLM 经历的处理——不追，留一个钩子**：
- 前几年做的对话系统/数据库问答是 pre-LLM 时代技术栈，拿出讲不加分，**不更新不重学**；但**不删**简历（聊到 voice agent 时不至于一无所知），不作为卖点主动讲
- 行业缺的是管道这头（低延迟 RTC），不是模型那头——"我是做管道的"把焦虑转成定位优势
- **钩子**：QoS 报告做完后若有余力，一两周跑通一个 Agents demo（官方 quickstart，Python 几十行），面试时能说出"打断怎么传导到 TTS 戆断、首包延迟卡在哪个环节"就够；把 LLM 学习排进计划会稀释 QoS 主线，6 个月里最贵的是焦点

### 四-D-2、语音概念校准：KWS / ASR / TTS 别说混（2026-09-09 补充）

概念说错比不说更减分，先把组内三个词校准：

- **KWS ≠ 简单版 ASR**。技术路线不同：KWS 是**小模型关键词检出**（几十词内、本地常开、毫秒级、功耗优先——唤醒词"小海小海"）；ASR 是**大词表连续语音转写**。类比：门铃和电话功能沾边，原理两回事。准确讲法："KWS 是常开的轻量语音入口（唤醒词检出），**不做转写**"
- **"ASR 就是 TTS"是反的**：TTS = 文字转语音（设备播报），ASR = 语音转文字。门禁链路**有 TTS（播报），没有真正的 ASR**——KWS 只检出关键词不输出文字
- **组内"语音 Agent 入口"的准确表述**：**唤醒（KWS）→ 对讲（RTC 音频管道）→ 播报（TTS）**，中间"转写/理解"这环组内没做（是研究院模型/云端的活）。这个校准反而让叙事更顺：AI voice agent = ASR→LLM→TTS 三段编排，组内手里有**两头的管道**（KWS 入口 + TTS 出口 + 中间对讲管道），缺的只是接大模型那一跳——正好接"Agents 是编排层"的话题

**ASR 还需要做吗（按角色分）**：
- **RTC/引擎岗目标：不做 ASR**。那是算法/模型岗的活。只需要懂流式 ASR 的**接口特性**——分块延迟（几百 ms 一段）、partial result（边说边出字）、说话人分离——因为这三个特性决定管道怎么切帧怎么传，知道工程含义就够
- **voice agent 方向工程师**：会**集成**流式 ASR/TTS SDK（不是做算法）——喂帧的前处理（重采样/格式/分块）、partial 与最终结果的会话状态管理、打断时序。全是管道侧的活，正好是已有的能力
- **组内视角**：门禁若未来加"语音指令"（"开门"→识别→执行）才需要 ASR——但那是接研究院/云端 API 的集成工作，不是现在该投入的

### 四-C-2、audio_neteq 双水位策略的讲法 + audio_pro↔APM 精确对照（2026-09-09 补充）

**架构事实（看过代码后分层）**：研究院库（`alg_neteq_lib.h`，接口 `NetEq_Send` 帧号+时间戳入队 / `NetEq_GetData` 出队，配置只暴露采样率/位宽/帧长/声道，**策略参数不外露**）+ 本人写的 614 行封装层（alg_aud_neteq.c:488 send_data / :556 get_data，通道管理/互斥/DFX/生命周期）。所以角色定位是"**抗抖动通道的工程封装 + 策略验证方**"——水位参数若可调，策略讲自己的；写死在库里，就讲"集成+调参+实测"。

**双水位策略的 libwebrtc 对应（背熟）**："高水位加速放、低水位 expand 插值" 对应 NetEq 的 **accelerate / expand / preemptive-expand** 三操作 + **target delay 动态调整**——组内的"两个水位"就是 NetEq IAT-based target delay 的工程简化版。

**"简化版不适合门禁吗"——直觉是对的，且是面试金句（能讲出为什么不做 > 我做了简化版）**：

> "门禁对讲是短会话、室内局域网场景，jitter 特性简单，双水位 + PLC 够了。libwebrtc NetEq 的完整 IAT 分布跟踪 + 多操作代价模型是为公网会议设计的，在 RTOS/嵌入式上算力内存都不划算。这是**场景约束下的工程取舍**，不是能力差距。"

**audio_pro ↔ WebRTC APM 精确对照表**（源码佐证，modules/audio_processing/）：

| 组内 audio_pro | WebRTC APM 对应物 | 备注 |
|---|---|---|
| alg_aecsp（**单麦**消回声） | `EchoCanceller3`（AEC3） | WebRTC AEC3 单麦起步、多麦增强 |
| alg_anr（降噪） | `NoiseSuppressor`（NS） | 频域维纳滤波一系 |
| alg_agc（自动增益） | `agc_manager_direct`（AGC1）+ `GainController2`（AGC2） | WebRTC 两级 |
| alg_alc（音量调节） | 无直接同名（近 GainController2 固定增益模式） | ALC≈模拟/数字增益调整 |
| alg_amer（混音） | `AudioMixer`（modules/audio_mixer） | TTS 插件 4 路混音 ↔ WebRTC 混音器 |
| alg_eq（均衡） | **无**——WebRTC 不做 EQ | 安防设备特色（音箱调音） |
| alg_aud_resample（重采样） | `PushResampler`（common_audio） | 两边都有 |
| — | `high_pass_filter`（APM 管线第一级） | 组内没暴露这个概念 |

**管线顺序对照（面试金句）**：WebRTC M144 `ProcessCaptureStreamLocked`（audio_processing_impl.cc:1272 附近）顺序 = `高通滤波 → AEC3 → NS → AGC1 → AGC2 → 回声检测`；组内 audio_pro 集成顺序同样是**采集侧先 AEC 再 NS 再 AGC**。**能讲出"为什么 AEC 在最前"就赢了大多数人**：AEC 依赖远端参考信号与近端信号的相关性做自适应滤波，AGC/NS 先动了信号，AEC 的自适应滤波就收敛不了——这个顺序是 DSP 的教科书结论，两边殊途同归。

### 四-E、投递分层收敛 + 市场现实（2026-09-09 补充）

- **萤石/IoT 硬件岗排除**（小a判断：传统部门→萤石没必要）：IoT 硬件线窄化为"面试谈资"不投递——门口机经验照写简历，但不讲"想去安防"。三条变两条，弹药更集中：
  - 🥇 音视频引擎/QoS 岗（声网/即构/字节/腾讯会议系）——QoS 实验报告 + 源码分析是核心弹药
  - 🥈 音视频客户端岗（直播/会议平台）——全链路地图 + 排障方法论 + 两个项目
- **背景重新框定**：不是"4 年杂活"，是"**2 年嵌入式 C/C++ 固件（蓝牙底层）+ 2 年设备端音视频（含自研音频抗抖动层）**"——两段对"硬件侧 RTC"都是正资产，叙事上不自我否定
- **市场现状（2026 务实版）**：
  - RTC 平台层在整合（声网/即构/TRTC/火山占住平台市场），纯"会建 WebRTC 房间"没有溢价——轻量后端项目证明的是**理解**，不是稀缺性，自己要清醒
  - 需求在两端：**AI 实时语音**（voice agents，这两年唯一明显增量）/ **IoT 音视频硬件**（可视门铃/对讲/宠物相机）——"安防不行"≠"设备端音视频经验不行"
  - 引擎/QoS 岗恒定稀缺：能读懂 libwebrtc、能改引擎、能做弱网实验的人市场上一直少
- **6 个月节奏（与第二章 3 个月路线衔接）**：
  1. **0～2 月**：轻量后端补 QoS 观测闭环（与阶段一/二合并成一件事）——"一个项目两条叙事线"
  2. **2～4 月**：自编译 AAR + 注入 NetworkController + 弱网对比（阶段三照旧）；**后端项目冻结功能**只做可靠性补齐
  3. **4～6 月**：产出两份文档化成果——①LiveKit ↔ 自研后端对照分析 ②弱网 QoS 实验报告（含 audio_neteq 与 NetEq 对照一节）；开始投递
  4. 面试叙事一句话："**门禁问题为引 → 自建全链路测量 → 引擎源码级定位 → 注入改造并量化**"

---

## 五、一句话总结

**小a 的路线 = 主攻音视频引擎岗（自编译 M144 源码 + 弱网科学实验 + 注入自定义 NetworkController），保底音视频业务岗（全链路地图 + 排障方法论 + 引擎源码兜底能力），两套叙事同一套准备。** 门禁是故事的起点（audio_neteq 是组内主弹药），通用流媒体 QoS 能力才是通行证。不碰算法层、不碰完整产品、不做纯调参——聚焦"策略层研发"；LLM 只留 LiveKit Agents demo 钩子，不投入。