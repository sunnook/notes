# LiveKit Android SDK 设计分析计划

## 目标
梳理 `livekit-android` SDK 的代码架构，输出 `docs/client-sdk-android-design-analysis.md`。

## 目标读者
有 C/C++ 经验但对 Android/Java/Kotlin 不熟悉的开发者。

## 章节大纲

### 第 1 章：项目概览与专业背景
- 1.1 项目简介
- 1.2 Gradle 多模块架构
- 1.3 专业背景补充（Android/Java/Kotlin 概念速查）

### 第 2 章：入口与生命周期
- 2.1 LiveKit.create() 入口
- 2.2 Dagger 依赖注入
- 2.3 Room 对象生命周期
- 2.4 connect() 与 release() 流程

### 第 3 章：整体架构分层
- 3.1 应用层 → SDK 层 → WebRTC 层
- 3.2 控制面 vs 数据面
- 3.3 分层控制流图

### 第 4 章：核心模块详细分析
- 4.1 Room — 房间管理与事件中枢
- 4.2 RTCEngine — 连接引擎
- 4.3 SignalClient — WebSocket 信令
- 4.4 LocalParticipant / RemoteParticipant — 参与者管理
- 4.5 Track 体系

### 第 5 章：数据流
- 5.1 上行数据流（发布音视频）
- 5.2 下行数据流（订阅音视频）
- 5.3 信令数据流（WebSocket 协议消息）
- 5.4 DataChannel 数据流
- 5.5 事件数据流（EventBus）
- 5.6 数据流总览图

### 第 6 章：关键子系统
- 6.1 音频子系统（AudioHandler / AudioSwitch / AudioProcessing）
- 6.2 视频子系统（Camera / CameraX / 视频编码与 Simulcast）
- 6.3 重连机制（Soft Resume / Full Reconnect）
- 6.4 端到端加密（E2EE）
- 6.5 RPC 与 DataStream
- 6.6 网络感知与自动重连

### 第 7 章：类图与交互关系
- 7.1 核心类图（文本形式）
- 7.2 关键类交互序列图

### 第 8 章：其他模块
- 8.1 livekit-android-camerax
- 8.2 livekit-android-track-processors（虚拟背景）
- 8.3 sample-app 示例
- 8.4 livekit-lint / detekt-rules
