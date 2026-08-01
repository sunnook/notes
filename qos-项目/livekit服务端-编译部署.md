# 一、先明确仓库定位
## 1. `https://github.com/livekit/livekit` = LiveKit SFU 服务端源码仓库
### 关键区分（极易踩坑）
1. **服务端主体：Go 语言实现 SFU 转发逻辑**
   路径 `./cmd/server`，编译产物 `livekit-server`，就是你要跑的媒体服务；
2. **内置 WebRTC 分两套**
   - 默认官方构建：用 **Pion WebRTC（Go 实现）**，纯 Go，没有 C++ libwebrtc；
   - 如果你要做你规划的「魔改 libwebrtc C++、JitterBuffer/VCM/NACK 深度优化」：
     必须切换构建模式，启用 **C++ libwebrtc 绑定**，仓库内 `third_party/webrtc` 才会生效，用 depot_tools/gn/ninja 编译底层C++；
3. **客户端不在这个仓库**：所有 Android/iOS/Web/C++ 客户端 SDK 都是独立仓库，下面单独说明。

## 2. 两种编译模式（对应你的24周项目）
### 模式A：默认 Pion WebRTC（纯Go，快速跑通服务，**不能改C++ libwebrtc**）
适合快速部署、业务调试，不适合你弱网底层魔改计划。
#### 编译&运行步骤（Ubuntu）
```bash
# 1. 安装依赖
sudo apt update && sudo apt install git go mage
# Go 版本要求 1.21+

# 2. 拉取服务端源码
git clone https://github.com/livekit/livekit.git
cd livekit

# 3. 一键初始化依赖（自动拉取子模块、protobuf、工具链）
./bootstrap.sh

# 4. 编译生成二进制（输出到 bin/livekit-server）
mage build

# 5. 开发模式直接运行（内置dev密钥、无需redis、自动放行调试）
./bin/livekit-server --dev
```
启动后默认地址 `ws://服务器IP:7880`
- API Key：`devkey`
- Secret：`secret`

#### 生产配置运行（对应你之前 `/livekit/config`）
```bash
# 生成配置模板
docker run --rm -v /livekit:/output livekit/generate
# 编辑 /livekit/config/livekit.yaml 填入密钥、redis、端口
./bin/livekit-server --config /livekit/config/livekit.yaml
```

### 模式B：启用 C++ libwebrtc（**你的项目唯一选择，可修改底层modules**）
目标：编译内置 `third_party/webrtc` C++ 库，魔改 JitterBuffer、VCMTiming、NACK、TWCC。
#### 完整编译流程
1. 前置依赖（编译WebRTC必备）
```bash
sudo apt install git python3 build-essential libssl-dev cmake ninja-build
# 拉取 depot_tools
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
echo "export PATH=$PWD/depot_tools:$PATH" >> ~/.bashrc
source ~/.bashrc
```
2. 进入livekit仓库，拉取并同步webrtc子模块
```bash
cd livekit
git submodule update --init third_party/webrtc
cd third_party/webrtc
# 同步webrtc全依赖
gclient sync
# 安装系统编译依赖
./build/install-build-deps.sh
```
3. gn生成构建文件，编译libwebrtc静态库
```bash
cd src
# Release编译，x64 Linux
gn gen out/release --args='target_os="linux" target_cpu="x64" is_debug=false rtc_include_tests=false'
ninja -C out/release
# 此时可修改 modules/video_coding / modules/rtp_rtcp 源码，重新ninja编译
```
4. 回到livekit根目录，编译带C++ webrtc绑定的livekit-server
```bash
cd ../../
# 启用libwebrtc C++后端编译
mage build:libwebrtc
# 产物同样 bin/livekit-server，底层是你魔改后的C++ WebRTC
./bin/livekit-server --dev
```

## 3. Docker vs 裸机运行 补充结论（呼应你上一问）
- 同一份 `bin/livekit-server` 二进制，**音视频算法逻辑完全一致**；
- 开发魔改/弱网量化测试：必须裸机运行，容器网络namespace、权限、调试gdb堆栈、自研UDP代理都会引入额外干扰变量；
- 仅成品打包演示：再基于本地编译产物写Dockerfile构建自定义镜像，不要用官方镜像开发。

---

# 二、客户端：独立仓库，分平台编译（适配你阶段四Android NDK交叉编译）
所有客户端和服务端 `livekit/livekit` 仓库完全分离，按需选择：
## 1. C++ SDK（最贴合你的WebRTC底层研究，可编译Linux/Android）
仓库：`https://github.com/livekit/client-sdk-cpp`
内置完整libwebrtc，可同步魔改JitterBuffer，支持：
- Linux x64 桌面客户端
- Android NDK 交叉编译（你阶段四目标）
### 编译Linux客户端示例
```bash
git clone https://github.com/livekit/client-sdk-cpp
cd client-sdk-cpp
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
# 运行demo客户端连接本地livekit-server
./examples/basic_call
```
### Android NDK交叉编译
修改cmake参数指定NDK路径、target_os=android，产出AAR/so库，可嵌入Android App。

## 2. Android Kotlin SDK（业务层Android客户端）
仓库：`https://github.com/livekit/client-sdk-android`
底层封装预编译libwebrtc so，**不适合修改WebRTC底层源码**，仅做上层业务开发。

## 3. Web前端（快速测试，无需编译）
直接用官方在线demo：https://example.livekit.io
填入你的服务器ws地址、token即可连接，用来快速验证服务端音视频通路。

## 4. 其他客户端（仅业务开发，无底层修改价值）
- iOS/Swift：`client-sdk-swift`
- Flutter：`client-sdk-flutter`
- Unity：`client-sdk-unity`

---

# 三、适配你24周项目的标准开发流程（主线）
1. **阶段1-2 底层魔改**
   - 拉 `livekit/livekit`，启用C++ libwebrtc编译模式；
   - 修改 `third_party/webrtc/modules` 下JitterBuffer、NACK、TWCC代码；
   - ninja重编webrtc静态库 → mage build:libwebrtc 生成livekit-server；
   - 裸机运行二进制调试。
2. **阶段3 弱网仿真实验**
   - 宿主机自研UDP Proxy控制丢包/延迟，不要Docker；
   - 对比「原生webrtc编译的server」vs「魔改版server」指标。
3. **阶段4 工程化落地**
   - 方案1：client-sdk-cpp NDK交叉编译Android客户端；
   - 方案2：基于本地编译的livekit-server写Dockerfile打包自定义镜像用于部署演示；
   - 整理量化指标写入简历。

# 四、关键避坑
1. 不要混用两套webrtc：不要单独拉一份webrtc再和livekit拼接，统一使用仓库内 `third_party/webrtc`；
2. 默认mage build用Pion Go WebRTC，无法修改C++底层，做弱网优化必须用 `mage build:libwebrtc`；
3. 官方Docker镜像内置预编译二进制，无源码、无编译链，完全不能用于源码修改开发；
4. 客户端单独仓库，和服务端源码不互通，底层魔改统一在livekit仓库的third_party内操作。‘；、