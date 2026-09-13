# WebRTC 工程模块分析计划

## 目标
分析 webRTC 原生 C++ 库的模块结构、模块间关系、数据流与控制流，形成一份详要而专业的分析文档。

## 读者画像
- 具备 C/C++ 经验，熟悉高级 C++ 用法但需要补充
- 希望理解整个 webRTC 库的架构分层和协作方式

## 章节大纲

### 第 1 章：工程概览
- 1.1 工程定位与架构分层总览
- 1.2 文件夹与模块的对应关系表
- 1.3 核心概念速查（PeerConnection / Call / Channel / Stream / Module）

### 第 2 章：底层基础设施 —— rtc_base
- 2.1 线程与消息系统（Thread / Message / SignalThread）
- 2.2 网络抽象层（Socket / SocketFactory / VirtualSocketServer）
- 2.3 同步原语与内存管理（CriticalSection / ref_counted / scoped_refptr / sigslot）
- 2.4 时间、日志、SSL 适配
- 2.5 C++ 知识点：sigslot 信号槽、placement new、策略模式

### 第 3 章：API 层 —— api/
- 3.1 PeerConnectionInterface（WebRTC 标准 API 入口）
- 3.2 MediaStream / MediaStreamTrack
- 3.3 RTP/RTCP 参数接口
- 3.4 Proxy 模式（跨线程对象访问）
- 3.5 C++ 知识点：抽象接口设计、智能指针、工厂模式

### 第 4 章：信令与媒体控制层 —— pc/
- 4.1 PeerConnection 实现（SDP 协商、ICE 状态机）
- 4.2 JsepTransportController（传输层管理）
- 4.3 RtpTransceiver / RtpSender / RtpReceiver
- 4.4 DataChannel（SCTP over DTLS）
- 4.5 MediaSession（媒体会话管理）
- 4.6 控制流分析：从 API 调用到内部对象的完整链路

### 第 5 章：Call 层 —— call/
- 5.1 Call 类：音视频流的统一调度中心
- 5.2 AudioSendStream / AudioReceiveStream
- 5.3 VideoSendStream / VideoReceiveStream
- 5.4 RTP/RTCP Demuxer
- 5.5 数据流：Call 如何连接 pc 层与 modules 层

### 第 6 章：核心处理模块 —— modules/
- 6.1 audio_coding（音频编解码调度：G722/Opus/iSAC）
- 6.2 audio_device（音频设备抽象：ADM）
- 6.3 audio_processing（APE：AEC/NS/AGC/VAD）
- 6.4 video_coding（视频编解码调度：VP8/VP9/H264）
- 6.5 video_processing（VPP：帧缓冲、旋转、裁剪）
- 6.6 congestion_controller（拥塞控制：GCC、Remote Bitrate Estimator）
- 6.7 pacing（数据包整形与发送节奏控制）
- 6.8 rtp_rtcp（RTP/RTCP 封包与解包）
- 6.9 video_capture（视频采集抽象）
- 6.10 desktop_capture（桌面捕获）
- 6.11 C++ 知识点：Module 接口设计、策略模式、Observer 模式

### 第 7 章：编解码实现 —— video/video_codecs / common_audio / common_video
- 7.1 VP8/VP9/H.264 编码器适配
- 7.2 音频信号处理（resampler、fir_filter、signal_processing）
- 7.3 视频工具（I420 缓冲、libyuv 集成）
- 7.4 C++ 知识点：SIMD 优化、模板元编程、多态与性能

### 第 8 章：P2P 与网络层 —— p2p/
- 8.1 STUN 协议实现
- 8.2 ICE Candidate 收集与候选类型
- 8.3 NAT 穿透原理在代码中的体现

### 第 9 章：媒体引擎桥接层 —— media/engine/
- 9.1 WebRTCMediaEngine（统一音视频引擎）
- 9.2 WebRTCVoiceEngine（VoE 到现代 API 的桥接）
- 9.3 WebRTCVideoEngine（VoViE 到现代 API 的桥接）
- 9.4 编码器仿真代理（SimulcastEncoderAdapter）
- 9.5 这是连接旧版 VoE/VoViE API 与现代 API 的关键层

### 第 10 章：SDK 与平台适配 —— sdk/
- 10.1 Android JNI 桥接
- 10.2 Objective-C 桥接

### 第 11 章：完整业务流程分析
- 11.1 呼叫建立全流程（Offer/Answer + ICE + DTLS 握手）
- 11.2 音频发送数据流：麦克风 -> ADM -> APE -> audio_coding -> RTP -> 网络
- 11.3 音频接收数据流：网络 -> RTP解包 -> audio_coding -> APE -> ADM -> 扬声器
- 11.4 视频发送数据流：摄像头 -> VPP -> video_coding -> RTP -> 网络
- 11.5 视频接收数据流：网络 -> RTP解包 -> video_coding -> VPP -> 渲染
- 11.6 DataChannel 数据流
- 11.7 拥塞控制闭环
- 11.8 控制流总结图（分层调用关系）

### 第 12 章：C++ 高级技巧在 WebRTC 中的应用
- 12.1 零拷贝设计与 Copy-on-Write Buffer
- 12.2 跨线程编程模式（ProcessThread、TaskQueue、Proxy）
- 12.3 模板与类型擦除在编解码适配中的应用
- 12.4 性能关键路径的优化技巧（SIMD、缓存友好、内存池）
- 12.5 线程安全注解（thread_annotations.h）

## 写作顺序
按章节 1 -> 2 -> 3 -> ... -> 12 顺序逐章写入最终文档。
