# WebRTC 工程全貌 + LiveKit 集成深入（第 21 节独立版）

> 日期：2026-09-07
> 工程：`/data1/luhonghao/codes/adrtc/webrtc/webrtc-m144_release`（M144）
> LiveKit：`/data1/luhonghao/codes/aa/client-sdk-android-main`
> 视角：做引擎 / 优化引擎
> 关联：`wr-api-analysis.md`（主文档）、`webrtc-native-source.md`、`livekit-webrtc-integration.md`

---

## 一、工程顶层目录作用全解

WebRTC 顶层目录分三类：**核心引擎**（api/pc/media/call/modules/p2p/net/rtc_base/video/audio）、**平台 SDK**（sdk）、**辅助工具**（examples/test/stats/logging/rtc_tools 等）。

### 1.1 辅助目录逐个解析

| 目录 | 作用 | 是否进生产 SDK |
|---|---|---|
| `examples/` | **示例代码**：`androidapp`（完整 Android 示例）、`peerconnection`（C++ 示例）、`stunserver`/`turnserver`（STUN/TURN 服务器）、`androidvoip`（VoIP 示例）、`objc`（iOS 示例） | ❌ 不编译进 SDK |
| `test/` | **测试基础设施**：gtest 封装、`test_main.cc`（测试入口）、`fake_decoder`/`fake_encoder`（假编解码器）、`direct_transport`（直连传输）、`create_frame_generator_capturer`（帧生成器）、`call_test.h`（端到端测试基类） | ❌ 仅测试 |
| `rtc_tools/` | **开发/分析工具**：`frame_analyzer`（帧分析）、`psnr_ssim_analyzer`（PSNR/SSIM 画质分析）、`rtc_event_log_visualizer`（事件日志可视化）、`network_tester`（网络测试）、`audioproc_f`（音频处理工具） | ❌ 开发工具 |
| `stats/` | **统计对象实现**：`rtc_stats.cc`、`rtcstats_objects.cc`——实现 `api/stats` 的统计接口 | ✅ 会进 SDK（LiveKit 的 RTCStats 用） |
| `logging/` | **事件日志**：`rtc_event_log`（RTC 事件日志，调试/分析用） | ✅ 部分进 |
| `experiments/` | **实验开关**：`field_trials.py`——field trial 实验特性配置 | ⚙️ 配置 |
| `docs/` | 文档（native-code、bug-reporting、release-notes） | ❌ |
| `infra/` | 持续集成配置（CI specs） | ❌ |
| `data/` | 音频测试数据（audio_processing、voice_engine 的测试音频） | ❌ 仅测试 |
| `resources/` | 测试资源（音频文件、网络 trace 数据） | ❌ 仅测试 |

### 1.2 一句话总结

- **非生产**：`examples/`（示例）、`test/`（测试基建）、`rtc_tools/`（工具）、`docs/`（文档）、`infra/`（CI）、`data/`+`resources/`（测试数据）
- **进 SDK**：`stats/`（统计）、`logging/`（事件日志）
- **配置**：`experiments/`（field trial 开关）

**做引擎启示**：这些目录是"外围"，核心在 api/pc/media/call/modules。但 `test/` 和 `rtc_tools/` 对做引擎很重要——`test/` 提供测试基建（假编解码器、直连传输），`rtc_tools/` 提供分析工具（PSNR/SSIM 画质分析）。

---

## 二、sdk 里的 jni 和 java 都被 LiveKit 使用吗？

### 2.1 核心结论

**LiveKit 只用 Java 接口层（`sdk/android/api/org/webrtc/`），不用 JNI 层（`sdk/android/src/jni/`）。**

```
LiveKit (Kotlin)
  │  import livekit.org.webrtc.*（Java 接口层）
  │  通过接口注入自定义实现
  ▼
Java 接口层（api/org/webrtc/）—— LiveKit 直接使用
  │  PeerConnectionFactory / PeerConnection / VideoTrack / VideoEncoder ...
  ▼
JNI 层（src/jni/）—— LiveKit 不直接碰，WebRTC 内部桥接
  │  JNI 把 Java 调用翻译成 C++
  ▼
C++ 引擎（api/pc/media/call/modules）
```

### 2.2 LiveKit 实际 import 的 webrtc 类（完整清单）

```
livekit.org.webrtc.*  （通配）
livekit.org.webrtc.audio.AudioDeviceModule
livekit.org.webrtc.audio.JavaAudioDeviceModule
livekit.org.webrtc.audio.JavaAudioDeviceModule.SamplesReadyCallback
livekit.org.webrtc.AudioProcessingFactory
livekit.org.webrtc.AudioTrack
livekit.org.webrtc.AudioTrackSink
livekit.org.webrtc.Camera1Capturer / Camera1Enumerator / Camera1Helper
livekit.org.webrtc.Camera2Capturer / Camera2Enumerator
livekit.org.webrtc.CameraEnumerator / CameraVideoCapturer
livekit.org.webrtc.CandidatePairChangeEvent
livekit.org.webrtc.CapturerObserver
livekit.org.webrtc.DataChannel
livekit.org.webrtc.DataPacketCryptor / DataPacketCryptorFactory
livekit.org.webrtc.EglBase / EglRenderer
livekit.org.webrtc.ExternalAudioProcessingFactory
livekit.org.webrtc.FrameCryptor / FrameCryptorFactory / FrameCryptorKeyProvider
livekit.org.webrtc.GlRectDrawer
livekit.org.webrtc.HardwareVideoEncoderFactory
livekit.org.webrtc.IceCandidate
livekit.org.webrtc.Logging
livekit.org.webrtc.MediaConstraints / MediaStream / MediaStreamTrack
livekit.org.webrtc.PeerConnection / PeerConnectionFactory
livekit.org.webrtc.RendererCommon / RTCStats / RTCStatsCollectorCallback / RTCStatsReport
livekit.org.webrtc.RtpCapabilities / RtpParameters / RtpReceiver / RtpSender / RtpTransceiver
livekit.org.webrtc.ScreenCapturerAndroid
livekit.org.webrtc.SdpObserver / SessionDescription
livekit.org.webrtc.SimulcastVideoEncoderFactory
livekit.org.webrtc.SoftwareVideoDecoderFactory / SoftwareVideoEncoderFactory
livekit.org.webrtc.SurfaceEglRenderer / SurfaceTextureHelper / SurfaceViewRenderer
livekit.org.webrtc.ThreadUtils
livekit.org.webrtc.VideoCapturer / VideoCodecInfo / VideoCodecStatus
livekit.org.webrtc.VideoDecoder / VideoDecoderFactory / VideoEncoder / VideoEncoderFactory
livekit.org.webrtc.VideoEncoderFallback / VideoFrame / VideoProcessor
livekit.org.webrtc.VideoSink / VideoSource / VideoTrack
livekit.org.webrtc.WrappedNativeVideoEncoder / WrappedVideoDecoderFactory
```

### 2.3 LiveKit 如何使用这些 Java 接口

LiveKit 通过 `PeerConnectionFactoryManager`（`webrtc/PeerConnectionFactoryManager.kt`）创建工厂，**注入**自定义实现：

```kotlin
// LiveKit 创建 PeerConnectionFactory，传入各种 factory
PeerConnectionFactory.initialize(initOptions)
val factory = PeerConnectionFactory.builder()
    .setVideoEncoderFactory(customEncoderFactory)   // 可注入自定义编码器
    .setVideoDecoderFactory(customDecoderFactory)
    .setAudioDeviceModule(javaAudioDeviceModule)     // 音频设备
    .createPeerConnectionFactory()
```

**关键**：LiveKit 通过这些 **Java 接口**注入自己的实现（虚化背景、自定义编解码），JNI 在底层把这些 Java 实现桥接到 C++。**LiveKit 从不直接调 JNI**——它通过 Java 接口触发，JNI 自动工作。

### 2.4 做引擎启示

- 想给 LiveKit 加新能力 → 在 **Java 接口层**（`api/org/webrtc/`）加接口 + JNI 桥接
- 想替换/优化引擎内部 → 通过 **Java 接口注入**（`VideoEncoderFactory`、`VideoProcessor` 等替换插槽）
- JNI 层是"翻译"，LiveKit 不碰，但做引擎要懂（新增 Java API 时）

---

## 三、各模块测试如何做？

### 3.1 测试框架：gtest（Google Test）

WebRTC 用 **gtest**，每个模块有自己的 `*_unittest.cc`。测试宏：
```cpp
TEST(DelayManagerTest, UpdateNormal) {
  TickTimer tick_timer;
  DelayManager dm(DelayManager::Config(...), &tick_timer);
  for (int i = 0; i < 50; ++i) {
    dm.Update(0, false, ...);
    tick_timer.Increment(2);
  }
  EXPECT_EQ(20, dm.TargetDelayMs());   // 断言
}
```

### 3.2 各模块测试文件

**信令模块（pc/）**：
- `pc/sdp_offer_answer_unittest.cc` —— SDP offer/answer 处理
- `pc/peer_connection_unittest.cc` —— PeerConnection 状态机
- `pc/data_channel_controller_unittest.cc` —— 数据通道
- `pc/data_channel_integrationtest.cc` —— 数据通道集成测试
- `pc/congestion_control_integrationtest.cc` —— 拥塞控制集成测试

**音视频模块**：
- `media/engine/webrtc_video_engine_unittest.cc` —— 视频引擎
- `video/video_receive_stream2_unittest.cc` —— 视频接收流
- `audio/audio_send_stream_unittest.cc` —— 音频发送流
- `audio/channel_send_unittest.cc` / `channel_receive_unittest.cc` —— 音频通道

**QoS 模块**：
- `modules/audio_coding/neteq/delay_manager_unittest.cc` —— NetEq 延迟管理
- `modules/audio_coding/neteq/decision_logic_unittest.cc` —— NetEq 决策逻辑
- `modules/congestion_controller/goog_cc/*_unittest.cc` —— 拥塞控制
- `modules/video_coding/nack_requester_unittest.cc` —— NACK

### 3.3 测试基础设施（test/ 目录）

| 设施 | 作用 |
|---|---|
| `test/gtest.h` | gtest 封装 |
| `test/test_main.cc` | 测试入口 |
| `test/fake_decoder.h` / `fake_encoder.h` | **假编解码器**（测试音视频链路，不真编解码） |
| `test/direct_transport.h` | **直连传输**（测试不经过真实网络，直接对接） |
| `test/create_frame_generator_capturer.h` | **帧生成器**（测试视频流，生成假帧） |
| `test/call_test.h` | **端到端测试基类**（测完整 call 链路） |

### 3.4 测试分层

| 层级 | 测什么 | 例子 |
|---|---|---|
| 单元测试 | 单个类 | `delay_manager_unittest.cc` |
| 集成测试 | 模块协作 | `pc/data_channel_integrationtest.cc`、`pc/congestion_control_integrationtest.cc` |
| 端到端 | 完整链路 | `test/call_test.cc`（用假编解码器 + 直连传输） |

### 3.5 做引擎启示

- **单元测试**：测单个算法（NetEq 延迟、拥塞、NACK）——改算法时跑这些
- **假编解码器 + 直连传输**：测完整音视频链路，不依赖真实编解码/网络——**做引擎验证链路是否通**的关键
- **帧生成器**：测视频流，生成假帧喂给引擎
- **PSNR/SSIM**（rtc_tools）：测画质——优化编码器后对比画质

---

## 四、LiveKit 的特殊处理怎么做？

### 4.1 录屏（Screenshare）

```
LiveKit LocalScreencastVideoTrack（room/track/LocalScreencastVideoTrack.kt）
  → Android MediaProjection（系统录屏 API）获取屏幕
  → ScreenCapturerAndroid（WebRTC Java 类，sdk/android/api/org/webrtc/ScreenCapturerAndroid.java）
  → 作为 VideoSource 喂给 WebRTC 视频上行链路
```

**关键**：LiveKit 用 **Android 系统级 `MediaProjection`** + WebRTC 的 `ScreenCapturerAndroid` 采集屏幕，然后走标准视频上行链路（编码 → RTP → 发送）。

### 4.2 虚化背景（Virtual Background）

```
LiveKit VirtualBackgroundVideoProcessor（livekit-android-track-processors 模块）
  → Google ML Kit SelfieSegmenter（人像分割，识别前景人像）
      com.google.mlkit.vision.segmentation.selfie.SelfieSegmenter
  → 分割出人像 mask
  → OpenGL 渲染：人像保留，背景替换/虚化
  → 作为 VideoProcessor 注入视频链路
```

**关键**：LiveKit 用 **Google ML Kit**（`SelfieSegmenter`）做人像分割，然后用 **OpenGL** 把背景虚化/替换。它通过 WebRTC 的 **`VideoProcessor` 接口**（`api/org/webrtc/VideoProcessor.java`）**注入**到视频链路——这就是"做引擎"时自定义视频处理的入口。

### 4.3 其他特殊处理

| 特殊处理 | 实现方式 | 注入点 |
|---|---|---|
| 自定义编解码 | `CustomVideoEncoderFactory` | `VideoEncoderFactory` 接口 |
| 音频处理 | `ExternalAudioProcessingFactory` | `AudioProcessingFactory` 接口 |
| E2EE 加密 | `FrameCryptor` | WebRTC 帧加密接口 |
| 不丢帧处理 | `NoDropVideoProcessor` | `VideoProcessor` 接口 |
| 滤镜/缩放 | `ChainVideoProcessor`、`ScaleCropVideoProcessor` | `VideoProcessor` 接口 |

### 4.4 做引擎启示

**LiveKit 的特殊处理都是通过 WebRTC 的 Java 接口层注入的**——录屏用 `ScreenCapturerAndroid`，虚化背景用 `VideoProcessor` + ML Kit，自定义编解码用 `VideoEncoderFactory`。这些都是 WebRTC 预留的**"替换插槽"**（呼应 api/ 暴露配置/观测/替换插槽的设计）。

**这正好说明**：WebRTC 引擎的扩展点（替换插槽）就是这些 Java 接口。做引擎时，想支持新能力，就是**新增/扩展这些替换插槽**。

---

## 五、总结

1. **顶层目录**：核心是 api/pc/media/call/modules；`examples/`/`test/`/`rtc_tools/`/`docs/`/`infra/`/`data/`/`resources/` 是非生产辅助；`stats/`/`logging/` 进 SDK；`experiments/` 是配置
2. **LiveKit 只用 Java 接口层**（`api/org/webrtc/`），不碰 JNI 层；通过接口注入自定义实现
3. **测试**：gtest + 每模块 `*_unittest.cc`；`test/` 提供假编解码器/直连传输/帧生成器做集成和端到端测试
4. **特殊处理**：录屏用 `ScreenCapturerAndroid`，虚化背景用 `VideoProcessor` + ML Kit，都通过 WebRTC 的 Java 接口"替换插槽"注入

**一句话**：WebRTC 引擎的**扩展点（替换插槽）就是 Java 接口层**，LiveKit 的所有特殊处理都通过这些插槽注入；做引擎的核心是理解这些插槽 + 用 `test/` 和 `rtc_tools/` 验证和优化。