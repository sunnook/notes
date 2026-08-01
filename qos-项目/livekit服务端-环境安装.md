# LiveKit 服务端完整部署流程复盘（含命令注释、问题+解决方案）
## 整体流程分段：防火墙放行端口 → 安装Docker（中途踩坑）→ 安装Go环境（多版本冲突核心坑）→ 拉取LiveKit源码编译
## 一、防火墙端口放行（WebRTC媒体端口）
```bash
# 安装防火墙工具firewalld
sudo apt install firewalld
# 放行LiveKit控制端口7880 TCP
sudo firewall-cmd --add-port=7880/tcp --permanent
# 放行7880 UDP媒体
sudo firewall-cmd --add-port=7880/udp --permanent
# 管理/API端口7881 TCP
sudo firewall-cmd --add-port=7881/tcp --permanent
# STUN TURN端口3478 UDP
sudo firewall-cmd --add-port=3478/udp --permanent
# WebRTC媒体大端口范围40000-50000 UDP
sudo firewall-cmd --add-port=40000-50000/udp --permanent
# 重载防火墙规则，永久生效
sudo firewall-cmd --reload
```
无报错，端口全部放行成功，无问题。

## 二、Docker 安装流程（用于后续打包编译后LiveKit镜像）

### 0. 总结版本
1. 安装docker（docker官方装不上，用阿里云源）；
2. 安装Go（正确版本Go1.26）(google不好使，就拉中科大源)；
3. 用Go安装mage wire 依赖注入工具；
4. 拉取livekit服务器源代码，并编译；

#### 第1步，更换阿里云国内Docker源，安装docker
```bash
# 卸载残留失败的Docker组件
sudo apt remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin
# 自动清理无用依赖
sudo apt autoremove -y

# 安装基础证书、下载工具
sudo apt install ca-certificates curl gnupg lsb-release -y
# 导入阿里云Docker GPG签名密钥
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
# 写入国内Docker软件源
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新软件源索引
sudo apt update
# 安装Docker全套，剔除不存在的docker-model-plugin
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin

# 重载系统服务配置，识别docker服务
sudo systemctl daemon-reload
# 启动Docker服务
sudo systemctl start docker
# 设置开机自启动
sudo systemctl enable docker
# 查看Docker运行状态，确认启动正常
sudo systemctl status docker

# 校验Docker版本
docker -v
# 校验docker compose插件
docker compose version
```

#### 第2步，中科大镜像下载go 1.26（当前要求）；用go1.26安装mage、wire依赖注入工具
```bash
# 创建Go工具存放目录，缺失会导致mage安装失败
mkdir -p ~/go/bin
# 删除旧Go1.23（如果有的话）
sudo rm -rf /usr/local/go

# 中科大镜像下载Go1.26
wget https://mirrors.ustc.edu.cn/golang/go1.26.0.linux-amd64.tar.gz
# 解压安装
sudo tar -C /usr/local -xzf go1.26.0.linux-amd64.tar.gz
# 刷新PATH与代理环境变量
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bashrc
echo "export GOPROXY=https://goproxy.cn,direct" >> ~/.bashrc
source ~/.bashrc

# 校验升级后Go版本
go version
# 查看代理配置（仅排查网络超时问题使用，非必需）
# go env GOPROXY
# 查看工具安装路径（仅排查命令找不到问题使用，非必需）
# go env GOBIN

# 清理项目编译缓存
mage clean
# 重新初始化项目依赖
./bootstrap.sh

# 删除旧Go编译的mage、wire等工具二进制（如果有的话）
sudo rm -rf ~/go/bin/*
sudo rm -rf ~/go/pkg

# 使用当前Go1.26重新编译安装mage、wire依赖注入工具
go install github.com/magefile/mage@latest
go install github.com/google/wire/cmd/wire@latest


# 拉取LiveKit源码
mkdir -p ~/codes/livekit
cd ~/codes/livekit
git clone https://github.com/livekit/livekit.git
cd livekit

# 清理+初始化后，用Go1.26编译
mage clean
./bootstrap.sh
mage build
```


### 1. 最初官方脚本安装失败问题
```bash
# 国外源SSL连接被重置、超时
curl -fsSL https://get.docker.com | sh
# 尝试启动docker，提示unit不存在（安装中断失败）
sudo systemctl start docker
```
**问题1**：境外get.docker.com网络拦截，SSL连接重置，安装中途中断，无docker服务文件；
**问题2**：Ubuntu 20.04(focal)官方脚本提示系统生命周期终止，不存在`docker-model-plugin`包导致安装中断。

### 2. 修复方案：换阿里云国内Docker源手动分步安装
```bash
# 卸载残留失败的Docker组件
sudo apt remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin
# 自动清理无用依赖
sudo apt autoremove -y

# 安装基础证书、下载工具
sudo apt install ca-certificates curl gnupg lsb-release -y
# 导入阿里云Docker GPG签名密钥
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
# 写入国内Docker软件源
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新软件源索引
sudo apt update
# 安装Docker全套，剔除不存在的docker-model-plugin
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin

# 重载系统服务配置，识别docker服务
sudo systemctl daemon-reload
# 启动Docker服务
sudo systemctl start docker
# 设置开机自启动
sudo systemctl enable docker
# 查看Docker运行状态，确认启动正常
sudo systemctl status docker

# 校验Docker版本
docker -v
# 校验docker compose插件
docker compose version
```
修复结果：Docker完整安装成功，可后续打包自定义LiveKit镜像。

## 三、Go语言环境安装（LiveKit编译核心依赖，踩坑最多环节）

需要先装Go；

### 阶段1：初次安装Go1.23，执行bootstrap.sh报错
```bash
# 拉取LiveKit源码
mkdir -p ~/codes/livekit
cd ~/codes/livekit
git clone https://github.com/livekit/livekit.git
cd livekit

# 一键初始化项目依赖、构建工具
./bootstrap.sh
```
**报错1**：`go: command not found`，系统未预装Go；
解决：下载安装Go1.23.3
```bash
# 下载Go1.23安装包
wget https://dl.google.com/go/go1.23.3.linux-amd64.tar.gz
# 删除旧Go（如有）
sudo rm -rf /usr/local/go

# 解压到系统目录
sudo tar -C /usr/local/ -xzf go1.23.3.linux-amd64.tar.gz
# 将Go二进制加入环境变量PATH
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc

# 刷新环境变量生效
source ~/.bashrc
# 校验Go版本
go version
```

### 阶段2：Go1.23环境下bootstrap.sh新问题
```bash
# 创建Go工具存放目录，缺失会导致mage安装失败
mkdir -p ~/go/bin

# 配置国内Go模块代理，解决golang.org下载超时
echo "export GOPROXY=https://goproxy.cn,direct" >> ~/.bashrc
# PATH追加Go工具目录
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bashrc
source ~/.bashrc

# 查看代理配置
go env GOPROXY  # 打印当前 Go 模块下载代理地址
go env GOBIN    # 查看 Go 工具安装目录
# 手动安装构建工具mage（脚本内自动安装逻辑有兼容警告）
go install github.com/magefile/mage@latest

# 重新初始化项目
./bootstrap.sh
# 执行编译
mage build
```
**报错2**：`mkdir /home/ecs-user/go/bin: no such file or directory`
原因：Go默认工具目录不存在；解决：`mkdir -p ~/go/bin`

**报错3**：下载go toolchain超时 `dial tcp xxx:443: i/o timeout`
原因：直连谷歌域名被墙；解决：配置`GOPROXY=https://goproxy.cn,direct`国内代理

**报错4**：`wire: package requires newer Go version go1.26 (application built with go1.23)`
原因：LiveKit新版代码最低要求Go1.26，Go1.23版本过低；旧版本wire工具二进制缓存残留，版本校验冲突。

### 阶段3：升级Go到1.26，清理旧缓存彻底修复
```bash
# 删除旧Go1.23
sudo rm -rf /usr/local/go

# 中科大镜像下载Go1.26
wget https://mirrors.ustc.edu.cn/golang/go1.26.0.linux-amd64.tar.gz
# 解压安装
sudo tar -C /usr/local -xzf go1.26.0.linux-amd64.tar.gz
# 刷新PATH与代理环境变量
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bashrc
echo "export GOPROXY=https://goproxy.cn,direct" >> ~/.bashrc
source ~/.bashrc

# 校验升级后Go版本
go version

# 清理项目编译缓存
mage clean
# 重新初始化项目依赖
./bootstrap.sh

# 删除旧Go编译的mage、wire等工具二进制（核心冲突根源）
rm -rf ~/go/bin/*
rm -rf ~/go/pkg
sudo rm -rf ~/go/bin/*
sudo rm -rf ~/go/pkg

# 使用当前Go1.26重新编译安装mage、wire依赖注入工具
go install github.com/magefile/mage@latest
go install github.com/google/wire/cmd/wire@latest

# 清理+初始化后再次编译
mage clean
./bootstrap.sh
mage build
```
**问题根因**：虽然系统升级Go1.26，但`~/go/bin`内的mage、wire是Go1.23编译生成，内部标记低版本，和新版代码校验冲突；
**最终解决手段**：清空全部旧Go工具缓存，用Go1.26重新安装全套构建工具。

## 四、关键名词补充说明
1. `firewalld`：Linux防火墙服务，控制服务器端口出入站；
2. Docker：容器工具，后期用来打包编译完成的livekit-server，仅做成品部署，不用于底层libwebrtc源码开发；
3. Mage：Go工程构建工具，替代Makefile，封装LiveKit编译、代码生成、清理全套脚本；
4. Wire：Go依赖注入代码生成工具，LiveKit业务层必备，版本随Go环境绑定；
5. bootstrap.sh：LiveKit一键初始化脚本，自动拉取mage、protobuf、子模块依赖；
6. GOPROXY：Go模块下载代理，解决境外golang.org资源访问超时。

## 五、整体踩坑汇总表
| 故障现象 | 根因 | 解决方案 |
|--------|------|---------|
| Docker安装中断，找不到docker.service | 境外源网络阻断+旧Ubuntu缺少软件包 | 切换阿里云Docker国内源手动安装 |
| go: command not found | 未安装Go语言 | 下载解压Go二进制并配置PATH |
| mkdir ~/go/bin 不存在 | Go工具目录未创建 | mkdir -p ~/go/bin |
| Go工具链下载i/o timeout | 无法直连谷歌域名 | 配置GOPROXY国内代理 |
| wire提示需要Go1.26、当前编译环境1.23 | Go版本过低+旧工具缓存残留 | 升级Go至1.26，清空~/go/bin/pkg后重装mage/wire |

## 六、后续下一步操作（编译可魔改libwebrtc的版本）
等`mage build`纯Pion WebRTC编译成功后，执行下面命令编译带C++ libwebrtc的服务端（用于你的JitterBuffer/NACK底层优化项目）：
```bash
# 拉取内置libwebrtc子模块源码
git submodule update --init third_party/webrtc
# 编译绑定C++ libwebrtc的livekit-server
mage build:libwebrtc
```