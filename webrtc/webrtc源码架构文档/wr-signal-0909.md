


```
Offerer(主叫)                信令服务器                 Answerer(被叫)
    │                           │                          │
    │ CreateOffer               │                          │
    │ SetLocal(offer) 启动收集  │                          │
    │                           │                          │
    │─── offer ────────────────►│─── offer ──────────────►│ SetRemote(offer)
    │                           │                          │
    │ onicecandidate            │                          │
    │─── candidate#1 host ─────►│─── candidate#1 ────────►│ AddIceCandidate
    │─── candidate#2 srflx ────►│─── candidate#2 ────────►│ (注入，参与检查)
    │                           │                          │
    │                           │                          │ CreateAnswer
    │                           │                          │ SetLocal(answer)
    │                           │                          │ onicecandidate
    │                           │◄── answer ──────────────│
    │ SetRemote(answer)         │◄── candidate#A ──────────│
    │ AddIceCandidate           │◄── candidate#B ──────────│
    │                           │                          │
    │◄════ STUN 打洞（直连 UDP，不经信令）════►            │
    │   nominated → DTLS 握手 → SRTP 密钥 → 媒体双线       │
```



```
sequenceDiagram
    participant O as Offerer(主叫)
    participant S as 信令服务器
    participant A as Answerer(被叫)

    Note over O: CreateOffer + SetLocal(offer)，启动候选收集
    O->>S: offer (codec/ice-ufrag/ice-pwd/fingerprint)
    S->>A: offer
    Note over A: SetRemote(offer) 存远端参数

    rect rgb(224, 246, 239)
    Note over O: onicecandidate：边收集边发（trickle）
    O->>S: candidate#1 (host 192.168.1.100:54321)
    S->>A: candidate#1
    Note over A: AddIceCandidate 注入
    O->>S: candidate#2 (srflx 公网反射地址)
    S->>A: candidate#2
    end

    Note over A: CreateAnswer + SetLocal(answer)，启动本端收集
    A->>S: answer (对称参数)
    S->>O: answer
    Note over O: SetRemote(answer)

    rect rgb(224, 246, 239)
    Note over A: onicecandidate
    A->>S: candidate#A (host ...)
    S->>O: candidate#A
    Note over O: AddIceCandidate 注入
    end

    Note over O,A: 两端齐 → ICE 连通性检查(STUN 直连打洞) → nominated → DTLS → SRTP → 媒体
```





0000000000000
<html style="margin:0;padding:0;">
<div style="background-color:transparent;box-sizing:border-box;font-family:'Roboto','PingFang SC','Segoe UI',Arial,sans-serif;color:#1A1B1C;">
  <div style="max-width:820px;padding:2px 2px 16px;box-sizing:border-box;">
    <div style="font-size:15px;font-weight:600;margin-bottom:2px;">信令流程图 · 两大步框架（Offerer 视角，trickle ICE）</div>
    <div style="font-size:11px;color:#6B7280;margin-bottom:10px;">时间从上往下；蓝=第一步 SDP 协商，绿=第二步 ICE 配对（与第一步交织），灰=传输面（不经信令）</div>

    <!-- 泳道表头 -->
    <div style="display:flex;gap:6px;margin-bottom:8px;">
      <div style="flex:1 1 0;padding:6px 8px;background:rgba(155,187,244,0.15);border:1px solid rgba(155,187,244,0.5);border-radius:8px;font-size:11.5px;font-weight:600;text-align:center;">Offerer 主叫（你侧）</div>
      <div style="flex:1 1 0;padding:6px 8px;background:rgba(228,227,221,0.4);border:1px solid #E4E3DD;border-radius:8px;font-size:11.5px;font-weight:600;text-align:center;color:#555;">信令服务器（WebSocket 等）</div>
      <div style="flex:1 1 0;padding:6px 8px;background:rgba(148,216,195,0.15);border:1px solid rgba(148,216,195,0.55);border-radius:8px;font-size:11.5px;font-weight:600;text-align:center;">Answerer 被叫（对端）</div>
    </div>

    <!-- 第一步 -->
    <div style="padding:5px 10px;background:rgba(155,187,244,0.12);border-radius:6px;font-size:11.5px;font-weight:600;color:#2E5F9E;margin-bottom:6px;">第一步 · SDP 协商（信令面：谈"内容契约"）</div>

    <div style="display:flex;gap:6px;margin-bottom:6px;">
      <div style="flex:1 1 0;padding:6px 8px;background:#fff;border:1px solid #E4E3DD;border-radius:8px;font-size:10.5px;line-height:1.6;">
        <b>CreateOffer</b> 生成 SDP 文本<br><b>SetLocal(offer)</b> → 启动候选收集
      </div>
      <div style="flex:1 1 0;padding:6px 8px;background:rgba(155,187,244,0.12);border:1px solid rgba(155,187,244,0.5);border-radius:8px;font-size:10.5px;text-align:center;align-self:center;">
        ────► <b>offer</b><br><span style="color:#6B7280;font-size:9.5px;">codec / sendrecv / ice-ufrag / ice-pwd / fingerprint<br>（m= 端口 9 = 候选稍后单独给）</span>
      </div>
      <div style="flex:1 1 0;padding:6px 8px;background:#fff;border:1px solid #E4E3DD;border-radius:8px;font-size:10.5px;line-height:1.6;">
        <b>SetRemote(offer)</b><br><span style="color:#6B7280;">存远端参数，不启动任何东西</span>
      </div>
    </div>

    <!-- 第二步标记（交织） -->
    <div style="padding:5px 10px;background:rgba(148,216,195,0.14);border-radius:6px;font-size:11.5px;font-weight:600;color:#1E6E5A;margin-bottom:6px;">第二步 · ICE 配对（trickle：与第一步交织，边收集边发）</div>

    <div style="display:flex;gap:6px;margin-bottom:6px;">
      <div style="flex:1 1 0;padding:6px 8px;background:#fff;border:1px solid #E4E3DD;border-radius:8px;font-size:10.5px;line-height:1.6;">
        <b>onicecandidate</b><br><span style="color:#6B7280;">host 候选立即回调，不等收齐</span>
      </div>
      <div style="flex:1 1 0;padding:6px 8px;background:rgba(148,216,195,0.15);border:1px solid rgba(148,216,195,0.55);border-radius:8px;font-size:10.5px;text-align:center;align-self:center;">
        ────► <b>candidate #1</b><br><span style="color:#6B7280;font-size:9.5px;">host 192.168.1.100:54321<br>（之后 srflx / relay 陆续发）</span>
      </div>
      <div style="flex:1 1 0;padding:6px 8px;background:#fff;border:1px solid #E4E3DD;border-radius:8px;font-size:10.5px;line-height:1.6;">
        <b>AddIceCandidate</b><br><span style="color:#6B7280;">注入 ICE transport，立即可参与检查</span>
      </div>
    </div>

    <div style="display:flex;gap:6px;margin-bottom:6px;">
      <div style="flex:1 1 0;padding:6px 8px;background:#fff;border:1px solid #E4E3DD;border-radius:8px;font-size:10.5px;line-height:1.6;">
        <b>SetRemote(answer)</b><br><span style="color:#6B7280;">远端参数落位</span>
      </div>
      <div style="flex:1 1 0;padding:6px 8px;background:rgba(155,187,244,0.12);border:1px solid rgba(155,187,244,0.5);border-radius:8px;font-size:10.5px;text-align:center;align-self:center;">
        ◄──── <b>answer</b><br><span style="color:#6B7280;font-size:9.5px;">对称：ufrag / pwd / fingerprint / codec</span>
      </div>
      <div style="flex:1 1 0;padding:6px 8px;background:#fff;border:1px solid #E4E3DD;border-radius:8px;font-size:10.5px;line-height:1.6;">
        <b>CreateAnswer + SetLocal(answer)</b><br><span style="color:#6B7280;">启动本端收集</span>
      </div>
    </div>

    <div style="display:flex;gap:6px;margin-bottom:8px;">
      <div style="flex:1 1 0;padding:6px 8px;background:#fff;border:1px solid #E4E3DD;border-radius:8px;font-size:10.5px;line-height:1.6;">
        <b>AddIceCandidate</b><br><span style="color:#6B7280;">远端候选注入</span>
      </div>
      <div style="flex:1 1 0;padding:6px 8px;background:rgba(148,216,195,0.15);border:1px solid rgba(148,216,195,0.55);border-radius:8px;font-size:10.5px;text-align:center;align-self:center;">
        ◄──── <b>candidate #A / #B</b><br><span style="color:#6B7280;font-size:9.5px;">对端 host / srflx 候选陆续回传</span>
      </div>
      <div style="flex:1 1 0;padding:6px 8px;background:#fff;border:1px solid #E4E3DD;border-radius:8px;font-size:10.5px;line-height:1.6;">
        <b>onicecandidate</b><br><span style="color:#6B7280;">对端边收集边发</span>
      </div>
    </div>

    <!-- 传输面 -->
    <div style="padding:5px 10px;background:rgba(228,227,221,0.5);border-radius:6px;font-size:11.5px;font-weight:600;color:#555;margin-bottom:6px;">传输面 · 连通性检查（不经信令，直接 UDP）</div>
    <div style="padding:8px 10px;background:#fff;border:1px solid #E4E3DD;border-radius:8px;font-size:10.5px;line-height:1.7;">
      <span style="color:#6B7280;">两端 SDP + candidate 齐备后：</span> 双方 ICE agent 互发 <b>STUN Binding</b>（打洞）→ 某一对候选 <b>nominated</b>（选路成功）→ <b>DTLS 握手</b> → 导出 <b>SRTP 密钥</b> → 媒体双线传输
      <div style="color:#6B7280;font-size:9.5px;margin-top:2px;">关键：candidate 通过信令传（绿），连通性检查通过媒体通道的 UDP 直传（灰）——两者不同通道</div>
    </div>

    <div style="font-size:10px;color:#6B7280;margin-top:6px;">示意：trickle ICE 下 offer/answer 只带 ufrag/pwd/fingerprint，候选全部走 onicecandidate 单独消息；传统 vanilla ICE 则把所有候选内嵌进 SDP 一次性发（m144 兼容此路径：UseCandidatesInRemoteDescription）。</div>
  </div>
</div>
</html>
