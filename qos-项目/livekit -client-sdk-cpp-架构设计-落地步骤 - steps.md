
---

### 、 超细化执行手册（Actionable Steps）

下面我将你的计划细化到**具体的操作动作、核心源码文件、工具命令和避坑指南**。

#### 阶段1：基建与基线（细化到操作级）

* **Step 1.1 编译环境 (Day 1-4)**
  * **动作**：使用 Ubuntu 20.04/22.04（强烈建议不要用 Mac 编译 Android 版，坑多）。准备至少 150GB SSD。
  * **命令**：配置 `gclient` 代理，使用清华/阿里镜像。
  * **避坑**：`gclient sync` 失败时，不要删库重来，用 `gclient sync -D --force` 修复。
  * **GN 参数**：
    ```gn
    target_os="android"
    target_cpu="arm64"
    is_debug=false
    rtc_include_tests=false
    rtc_build_examples=false
    rtc_enable_protobuf=false # 减小体积
    use_custom_libcxx=false   # 安卓端建议用系统 libc++ 避免冲突
    ```
* **Step 1.2 原生 Demo 跑通 (Day 5-10)**
  * **动作**：不要自己写 JNI，直接参考 LiveKit 官方的 `client-sdk-android` 中的 JNI 层，把它剥离出来。
  * **核心类**：复用 WebRTC 原生的 `Camera2Capturer` 和 `SurfaceViewRenderer`，确保第一版数据流转全在 C++ 层。
* **Step 1.3 弱网环境搭建 (Day 11-12)**
  * **动作**：在 Linux 服务器（作为 SFU 或中转节点）部署 `tc`。
  * **核心脚本示例**：
    ```bash
    # 10% 随机丢包，延迟 50ms，抖动 20ms
    tc qdisc add dev eth0 root netem loss 10% delay 50ms 20ms distribution normal
    # 周期性丢包 (每 2s 丢 500ms，需配合 iptables 或复杂 tc 规则，建议用 Clumsy/Network Link Conditioner 辅助)
    ```
* **Step 1.4 基线数据采集 (Day 13-14)**
  * **工具**：使用 WebRTC 自带的 `webrtc::RtpTransportControllerSend` 和 `CallStats` 打印日志，或者通过 JNI 把 `StatsReport` 传给 Kotlin 层记录。

#### 阶段2：核心 QoS 魔改（细化到源码级）

* **Step 2.1 JitterBuffer 优化 (Week 3)**
  * **定位源码**：`modules/video_coding/timing/timing.cc` (或 `frame_buffer3.cc`)，`modules/video_coding/jitter_buffer.cc`。
  * **具体修改**：
    * 在 `Timing::MaxWaitingTime()` 或渲染时间计算处，加入你的**方差计算逻辑**。
    * 定义一个 `jitter_variance_` 变量，使用 EWMA (指数加权移动平均) 更新。
    * 当 `jitter_variance_` 超过阈值时，修改 `render_time_ms_` 的平滑系数。
  * **验证**：使用 Perfetto 抓取 `WebRTC.Video.Decoded.FramesDropped` 和 `WebRTC.Video.Render.Time`。
* **Step 2.2 NACK/FEC 协同 (Week 4)**
  * **定位源码**：`modules/rtp_rtcp/source/rtp_sender_video.cc` (发送端)，`modules/video_coding/` 下的 FEC 相关类。
  * **具体修改**：
    * 拦截 TWCC 反馈：在 `TransportFeedbackAdapter` 或 `SendSideCongestionController` 中获取 RTT 和丢包率。
    * 修改 FEC 比例：找到 `UlpfecGenerator` 或 `FlexfecSender`，将固定的 `protection_factor` 改为你的动态计算值。
    * NACK 降级：在 `NackSender` (或类似类) 的 `SendNack()` 中，加入 RTT 判断，若 RTT > 200ms，直接 return 或拉长定时器。
* **Step 2.3 PLI 节流 (Week 5)**
  * **定位源码**：`video/video_stream_encoder.cc`。
  * **具体修改**：WebRTC 其实自带了 `KeyFrameRequestThrottler`。你需要魔改它的参数，或者在 `VideoStreamEncoder::OnBitrateUpdated` 中，根据当前 `target_bitrate` 动态调整请求关键帧的冷却时间 (Cooldown time)。

#### 阶段3：零拷贝与架构优化（细化到 Android 底层）

* **Step 3.1 采集端零拷贝 (Week 6)**
  * **核心动作**：废弃 Java 层的 `Camera2` 回调，使用 C++ 层的 `AndroidCamera2Session`。
  * **源码定位**：`sdk/android/src/java/org/webrtc/Camera2Session.java` 和 C++ 层的 `android_camera2_session.cc`。
  * **改造**：确保 Camera2 输出的 `Image` 直接转换为 `AHardwareBuffer`，然后包装成 WebRTC 的 `TextureBuffer` (通过 `SurfaceTextureHelper`)。**绝对不要调用 `Image.getPlanes()` 去拷贝 YUV 数据**。
* **Step 3.2 编解码零拷贝 (Week 7)**
  * **核心动作**：改造 `HardwareVideoEncoder` 和 `HardwareVideoDecoder`。
  * **避坑**：MediaCodec 的 `configure` 必须开启 `COLOR_FormatSurface`。输入端使用 `createInputSurface()`，输出端使用 `createOutputSurface()`。
  * **改造**：将 WebRTC 的 `VideoFrame` 直接渲染到 MediaCodec 的 Input Surface 上，避免 CPU 介入。
* **Step 3.3 渲染端直通 (Week 8)**
  * **核心动作**：使用 `SurfaceViewRenderer`。解码器输出的 `SurfaceTexture` 直接通过 EGL 渲染到 `SurfaceView` 的 `Surface` 上。全程在 Native 层通过 OpenGL/Vulkan 完成。

#### 阶段4：音频与开源闭环（细化到业务级）

* **Step 4.1 音频 3A 优化 (Week 9)**
  * **源码定位**：`modules/audio_processing/audio_processing_impl.cc`。
  * **具体修改**：针对门禁场景，调整 `AudioProcessing::Config`。
    * 开启 `noise_suppression` (NS) 并设为 `kHigh`。
    * 调整 `echo_canceller` (AEC3) 的 `enforce_high_pass_filtering` 和 `delay_estimate` 参数，门禁设备通常扬声器和麦克风距离很近，物理延迟极小，需优化 AEC 的滤波器长度。
* **Step 4.2 文档与图表 (Week 10)**
  * **图表工具**：使用 Python 的 `matplotlib` 或 `seaborn`，读取 WebRTC 导出的 JSON/CSV 统计数据，画出专业的折线图。
  * **README 补充**：把之前留白的 `[TODO]` 全部替换为真实的源码路径和算法公式（用 LaTeX 语法编写）。

---

### 三、 给你的 3 个“保命”建议

1. **建立 Git 分支隔离策略**：
   * `main`：纯净的 LiveKit + 原生 WebRTC。
   * `feat/jitter-opt`：只包含 JitterBuffer 修改。
   * `feat/nack-fec`：只包含 NACK/FEC 修改。
   * **千万不要把所有修改混在一个分支里**，一旦某个优化导致崩溃，你根本找不到原因，且无法做单一变量的 A/B 测试。

2. **准备“降级预案”**：
   * 如果阶段3的 `AHardwareBuffer` 零拷贝在某些手机上黑屏/花屏（极其常见），**立刻回退到半零拷贝方案**（如使用 `YuvConverter` 在 GPU 层做转换），不要在底层死磕，保证项目整体进度。

3. **面试话术预演**：
   * 当面试官问：“你做的这些优化，WebRTC 官方为什么不做？”
   * **标准回答**：“WebRTC 是通用框架，追求的是在各类网络下的**普适性和安全性**（保守策略）。而我针对的是**IoT 门禁/对讲场景**，这类场景网络特征明显（如局域网高带宽但外网出口易拥塞、设备算力低），我的优化是**牺牲了部分通用性，换取了特定场景下的极致体验**，属于业务定制优化。”

这份计划已经具备了冲击大厂高级/资深岗位的雏形。按这个细化步骤去执行，遇到具体的 C++ 编译报错或源码逻辑看不懂时，随时来找我拆解！祝你顺利！