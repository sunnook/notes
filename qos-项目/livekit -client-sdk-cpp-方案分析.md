# 核心结论
不用从零手写全套 Kotlin，分两种封装模式，按需选择：
1. **极简方案（推荐调试、快速真机验证）**：少量 JNI 胶水代码 + 极简 Kotlin 壳，几百行代码就能实现视频通话；
2. **完整方案（想复刻官方 Android SDK 体验）**：分层封装 JNI 接口，配套 Kotlin 工具类、摄像头/音频管理，工作量中等。

## 一、先分清三件东西，不混淆
1. `client-sdk-cpp`：纯 C++ 层，负责和 LiveKit SFU 通信、WebRTC 底层（你魔改JitterBuffer/NACK/QoS全部在这里），提供 C++ API；
2. JNI：C++ ↔ Java/Kotlin 的中间桥梁，**只需要写薄薄一层胶水**，把 C++ 的房间、轨道、回调暴露给 Java；
3. Android App（Kotlin）：上层 UI、权限、摄像头、Surface 渲染、页面逻辑，复用安卓原生能力。

## 二、最小工作量封装路线（调试弱网最优，代码极少）
### 1. 不用重写复杂媒体管理
C++ SDK 内部已经封装好：
- 房间连接、发布/订阅音视频轨道
- WebRTC 底层采集、编码、JitterBuffer、TWCC、NACK/FEC
你只需要通过 JNI 透传 4 类接口：
1. 初始化 LiveKit 客户端（传服务地址、token）
2. 加入房间、离开房间
3. 发布本地摄像头/麦克风
4. 远端视频回调（抛画面纹理/数据给安卓 Surface）

### 2. JNI 胶水代码量非常小
示例结构（几页代码搞定）
```cpp
// native-api.cpp JNI胶水
extern "C" JNIEXPORT jlong JNICALL
Java_com_demo_livekit_LiveKitNative_createClient(JNIEnv* env, jobject thiz, jstring url, jstring token) {
    // 调用C++ SDK API 创建LiveKit客户端
    auto client = new livekit::RoomClient(urlStr, tokenStr);
    return (jlong)client;
}

extern "C" JNIEXPORT void JNICALL
Java_com_demo_livekit_LiveKitNative_publishVideo(JNIEnv* env, jobject thiz, jlong clientPtr) {
    // 调用C++发布视频接口
}
```
Kotlin 侧只需要一个 Native 类声明本地方法：
```kotlin
class LiveKitNative {
    external fun createClient(url: String, token: String): Long
    external fun publishVideo(clientPtr: Long)
    external fun subscribeVideo(clientPtr: Long, trackId: String)
    companion object {
        init { System.loadLibrary("livekit_client") }
    }
}
```
这部分 Kotlin 代码几十行，没有复杂逻辑。

### 3. 画面渲染不用自己做WebRTC渲染器
两种偷懒方式：
1. C++ 层输出 I420 裸流，Kotlin 通过 ImageReader + SurfaceView 渲染；
2. 直接复用 WebRTC 自带 `SurfaceTextureHelper`，JNI 把安卓 Surface 传给 C++ WebRTC，底层渲染交给 libwebrtc，不用你写渲染逻辑。

### 4. 权限、摄像头、音频全部Kotlin原生处理
安卓摄像头权限、前后置切换、麦克风静音、后台权限、生命周期，用标准 Kotlin Camera2 / MediaRecorder，**完全不用碰C++**。

## 三、对比官方 client-sdk-android 的优劣
### 官方 Android SDK（纯Kotlin，预编译so）
优点：开箱即用，完整封装房间、轨道、事件、设备管理，不用写JNI；
缺点：WebRTC 底层二进制封死，无法魔改QoS，编译慢、调试底层C++极难。

### C++ SDK + 极简JNI Kotlin壳（你的项目首选）
优点：
1. WebRTC 源码完全可控，JitterBuffer、NACK、TWCC 直接改C++，Linux客户端快速调试，不用反复编译安卓AAR；
2. 一套魔改后的webrtc同时用于Linux调试客户端、安卓真机；
3. JNI胶水极薄，不需要复刻官方完整API，只保留你做弱网实验必需的接口；
缺点：需要写少量JNI互通代码，完全没有复杂业务封装。

## 四、如果你不想写任何JNI、Kotlin，有没有替代方案？
有，但只适合临时看画面，**不能做量化弱网测试**：
用 Linux x86 编译 `client-sdk-cpp` 的 `basic_call` demo，电脑开模拟器投屏模拟手机，但是无法复现安卓真实网络、摄像头编码、移动网络抖动场景，实验数据无效，不适合你的24周QoS项目。

## 五、给你最简落地步骤（最小封装成本）
1. NDK交叉编译 `client-sdk-cpp`，产出 `liblivekit_client.so`（内置你魔改的libwebrtc）；
2. 在 C++ SDK 新增少量 JNI 胶水，暴露**实验必需的最小接口**（连接房间、推流、拉流、获取延迟/丢包统计回调）；
3. 新建空Android项目，Kotlin只做三件事：
   - 动态加载so、调用native方法；
   - 摄像头权限采集、Surface画面渲染；
   - 输入服务端地址、token，一键加入房间；
4. 远端弱网指标（端到端延迟、抖动、丢包率）在C++层计算，通过JNI回调传给Kotlin页面展示，用于记录实验数据。

## 补充关键：不需要复刻官方全套SDK
你做项目的核心目标是**验证自研JitterBuffer、NACK/FEC联合决策、TWCC优化**，不是开发商用完整APP。
因此JNI只需要暴露和QoS相关的核心接口，聊天、录制、屏幕共享等无关功能全部砍掉，大幅减少Kotlin和JNI代码量。
 
  












# 结合你Android音视频NDK+C++求职场景梳理--三点完整解答
## 一、弱网模拟：Linux / Windows 都能做，各有适用场景
### 1）Windows 可控弱网方案
1. **WAN Emulation（Windows自带）**
    系统内置网络模拟器，可精确控制：丢包、延迟、抖动、带宽限制，适合快速桌面端测试；但只能管控本机网卡全局流量，无法单独过滤App进程流量。
2. 第三方工具：Clumsy（轻量开源）、Network Delay Simulator
    Clumsy最常用，图形化操作，可自定义上下行丢包、延迟、断流，适合快速验证Android真机USB投屏/模拟器流量。
缺点：Windows抓底层包不如Linux灵活，高并发、精细化链路QoS模拟能力弱。

### 2）Linux（服务器/本地虚拟机）工业级弱网（推荐做专业压测）
核心工具 `tc`（traffic control）+ `netem`，行业流媒体标准弱网方案，完全可控：
- 精准配置：单向/双向延迟、随机抖动、固定丢包率、带宽限流、重复包、乱序；
- 可精准隔离端口/IP，只限制流媒体（UDP 5004/8080等）流量，不影响其他服务；
- 适合你场景：阿里云2G服务器搭建SRS/SFU弱网环境，做WebRTC全链路弱网压测，配合Perfetto采集性能数据用于面试佐证。

### 补充Android真机专属弱网补充
除电脑端模拟，手机侧也有：Android开发者选项「网络模拟」，但精度低，仅做简单调试，正式压测优先Linux tc。

## 二、MediaSoup、libwebrtc 是否还要分析？结论：必须深挖，不能放弃
你求职目标是**Android中高级音视频研发、流媒体QoS优化**，这两个是核心加分栈，不能舍弃，分场景说明：
### 1）libwebrtc：必学，刚需
1. Android RTC核心底层，LiveKit底层封装的就是libwebrtc；
2. 你有嵌入式C++背景，优势点就在**魔改libwebrtc底层**：GCC拥塞控制、JitterBuffer、NEON音频优化、回声消除AEC3；
3. 面试高频考点：
   - WebRTC原生QoS机制（带宽估计、分层编码、NACK/PLI/FIR）；
   - NDK对接libwebrtc与MediaCodec硬解的线程冲突、异步适配；
   - 弱网下WebRTC自带拥塞算法缺陷、自定义优化方案。
> 你之前规划的「魔改libwebrtc源码、弱网压测」是差异化竞争力，不能跳过。

### 2）MediaSoup：可深度对比学习，作为选型储备
1. 和SRS同为主流SFU服务端，面试常会问「SRS vs MediaSoup选型差异」；
2. MediaSoup基于C++，强面向WebRTC，底层传输、线程模型、带宽调度设计更重型；
3. 学习收益：
   - 理解SFU端转发、多用户混流、端到端QoS联动；
   - 对比SRS轻量化架构，能说出不同业务场景选型（安防对讲/实时直播/会议）；
4. 取舍建议：不用完整部署商用，但吃透架构差异、传输层逻辑，面试能横向对比即可，不用投入大量生产级部署时间。

简单总结：libwebrtc 深度吃透（核心），MediaSoup 做横向对比分析（加分项），两者都不能完全不考虑。

## 三、协议与底层是否还要深入？结论：必须重点涉及，是中高级岗分水岭
### 1）为什么不能只停留在MediaCodec应用层
你原文描述的MediaCodec操作（同步/异步、码率模式、关键帧间隔）**只是Android应用层基础操作**，只能应付初级音视频岗；中高级、芯片厂商（博通等）面试一定会深挖底层协议与底层硬件编解码逻辑。

### 2）需要深挖的底层/协议模块（贴合你的技术栈）
#### （1）传输协议层（WebRTC核心）
- UDP、SRTP加密、RTCP控制报文、RTP封包解包；
- BWE带宽估计算法（WebRTC GCC底层源码）、RTT/丢包计算逻辑；
- NACK、FEC、ARQ弱网修复底层实现。

#### （2）硬件编解码底层（MediaCodec底层边界）
MediaCodec只是Android上层封装，底层依赖厂商硬件编解码器（高通/联发科芯片），仅调API解决不了复杂线上问题：
1. 硬编底层限制：硬件缓冲区队列、输入输出buffer同步锁、硬件VPU时序阻塞；
2. 硬编特有故障：硬件编码帧丢帧、码率漂移、I帧编码耗时突增、低码率下画质劣化；
3. 底层优化手段：NDK直接操作native buffer、自定义buffer队列、异步线程解耦、配合libwebrtc做帧缓存控制。

#### （3）音视频基础底层协议
H.264/H.265 SPS/PPS、NALU分包、时间戳PTS/DTS同步逻辑；音频OPUS底层码率、帧长、丢包补偿算法。

#### （4）嵌入式底层加分（你的独有优势）
蓝牙底层、NEON汇编、内存管理、多线程锁、零拷贝优化，能和WebRTC/Android Media链路结合，拉开和纯Android应用开发者差距。

### 3）分层价值区分
1. **应用层MediaCodec配置**（你原文内容）：基础保底能力，所有人都会；
2. **协议+底层传输+硬件编解码底层**：核心竞争力，面试区分中高级研发；
3. 求职芯片厂、流媒体底层岗位时，底层、协议是必问重点，只懂上层API会直接降级。

## 补充补充你那段MediaCodec原文的延伸解读
你提到MediaCodec操作仅在应用层、只会抛异常不会损坏设备，这个结论正确，但有底层边界坑需要补充：
1. 上层API操作确实不会造成手机硬件损坏、系统崩溃；
2. 但底层底层操作会出现严重隐性问题（仅上层API无法解决）：
   - 异步模式下native Buffer未及时释放 → 内存泄漏、长时间运行App OOM；
   - 硬编码队列阻塞未做底层帧丢弃逻辑 → 延迟持续走高、音画不同步；
   - 码率控制仅靠MediaFormat配置，不结合RTCP带宽反馈 → 弱网下码率剧烈波动、卡顿。
这也反过来证明：只做应用层MediaCodec配置不够，必须搭配传输协议、底层帧调度逻辑才能完成完整QoS方案。