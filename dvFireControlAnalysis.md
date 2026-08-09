# 现代火控雷达 (FCR) 新架构分析 - dvFCR

> 目标：从头构建一个和现有 dvRadar (AWACS小地图) 完全不同的火控雷达  
> 方形界面、距离/角度可调、扫描后更新+渐隐、敌机显示为线(速度矢量)、有限视场、TWS/STT、锁定图片、STT时只扫目标附近(小角度=扫得快)、联动 HMD/AtoAHUD/导弹，实现反干扰和各向异性锁定

---

## 1. 现状拆解 - 你现有脚本的雷达/火控逻辑

### dvRadar 1/2 = 伪预警机地图
- **逻辑**：`ActorManager.VehiclesInRange(pos, maxRange)` 全图搜索 → `ResetPool()` → `DrawTargets()` 实时显示
- **坐标**：圆形归一化 `radarX = Dot(delta, right)/range`, `radarY = Dot(delta, forward)/range`, `magnitude>1` 截到圆边
- **缩放**：见之前的 README
  - Radar1：默认最大，导弹接近才收缩
  - Radar2：新增 RadarZoomMode 0=最大+收缩 / 1=最小+扩张
- **缺陷**：无扫描过程、无波束宽度、无FOV限制、无延迟，是上帝视角，不是火控雷达

### AntiAirHUD / AtoAHUD = 光学/火控瞄准具，不是雷达
```lua
-- 共同模式
potentialTarget = ActorManager.vehicles 全图
for each vehicle:
  dir = vehicle.pos - camera.pos
  angle = Vector3.Angle(dir, cam.forward)
  if angle < maxLockAngle (25°/10°) and IsTargetVisible raycast通视:
     选最近的
LockTarget() 绑定 G 键
UpdateHUD():
  aimPoint = tgtPos + tgtVel * (dist/speed) + drop
  WorldToCanvasPosition() 来自 PlayerCamera.WorldToScreenPoint()
  lineImage 连接 infoObject 和 targetObject
```
- **本质**：基于 **PlayerCamera.forward** 的锥形搜索 + 视线遮挡检测 + 提前量解算，是 **机炮/防空炮的火控**，不是雷达。没有距离/角度可调的波束，没有扫描历史。

### dvHMD (dvHMDC / dvHMDM) = 头盔显示视角开关
```lua
angle = Vector3.Angle(vehicle.forward, Player.actor.facingDirection)
if angle in [min,max] then targetObject:SetActive(true)
```
- 只是 **角度阈值开关 UI**，用于HMD模式，逻辑可直接复用到FCR的 **ACM格斗模式/头盔瞄准**。

### dvProjVarVel / ADV = 导弹自驾仪 + 反干扰
- **inherit 阶段**：前几帧继承发射者速度
- **delay 0.3s 下坠**
- **Trace**：每帧 `currentTarget` 存在则 `Slerp(velocity, toTarget, dt*Smoothing)`
- ** flare 逻辑 ADV**：
```lua
if not currentTarget then -- 被干扰弹清除
  hasLastTarget=false
  StartCoroutine(FlareCoolDown) -> 0.2s后 CheckAngleRange() 若在 [min,max] 内则 SetTrackerTarget(lastTarget)
```
- 这已经是 **回合制干扰的第一次破解**：丢目标后0.2s自动重新抓。但仍会被连续干扰打断，且无法无视干扰。

### DvSpaceFire / ReSpecialProjectile 等
-  mostly 发射/特效管理，和雷达无关。

**结论**：你现有体系里，**雷达=上帝地图，火控=相机锥形，导弹=有0.2s重捕能力的追踪器**，三者完全解耦。现代空战需要的“雷达锁定→武器允许发射→导弹中制+末制+硬锁定抗干扰”链路在原版里不存在。

---

## 2. 现代火控雷达需求翻译成技术指标

| 现实术语 | 游戏化需求 | 技术实现点 |
|---|---|---|
| **方形B-Scope** | 方形界面，X=方位，Y=距离 | 不再做圆形 `magnitude>1` 归一，改 `Clamp(x,-1,1)` `Clamp(y,0,1)` 映射到 `RectTransform.sizeDelta` |
| **距离可调** | RWS range 20km/40km/80km | DataContainer `FCRMaxRange` + 输入切换 `Input.GetKeyDown(KeyCode.X)` 循环 |
| **方位可调** | 60°/30°/10° | `FCRScanAzimuth` 变量，决定扫描扇区宽度 |
| **扫描后才更新** | 波束扫过才刷新 | 实现 **扫描波束 Sweep**：`beamAz = Lerp(-az/2, az/2, pingPong(t, scanPeriod))`，只有 `abs(targetAz-beamAz) < beamWidth` 的目标才 `lastSeen=now` |
| **渐隐** | 同 dvDatalinkMap | `alpha=1-age/FadeTime` 用 `Text/Image.color.a` |
| **敌机显示成一条线** | 线段=速度矢量/航向，不旋转 | 用户自做线贴图，脚本提供 `velDir` 投影，`sizeDelta.x = vel.magnitude*scale`，`euler角=atan2(velY,velX)` 但符号本身不旋 |
| **有限角度/距离** | 最大探测角、最大距离硬限制 | `if abs(targetAz)>maxAz or range>maxRange or abs(el)>maxEl then 不可探测` |
| **追踪 (TWS)** | 同时跟踪多个 | 复用 dvDatalinkMap 的 `tracks[]` 结构 |
| **锁定 + 图片** | STT单目标跟踪，显示锁定框 | `lockedTrack` 变量，切 STT 后 `Image` 池单独画框 `anchoredPosition = predictedPos` |
| **小角度扫得快** | 窄扫描=短周期 | `scanPeriod = (scanAz / scanSpeed) * barCount`，STT时 `scanAz=10°` → 周期短 → 刷新率高 |
| **与HMD/AtoAHUD联动** | HMD角度进入可直接锁 | 复用 dvHMD 的 `facingDirection` 角判断 + FCR的ACM模式 |
| **与导弹联动抗干扰** | 硬锁定无视干扰 | 见 §4 |

---

## 3. 方形雷达的具体数学 - B-Scope 实现

原雷达是俯视 PPI，已不适用。FCR典型是 B-Scope：横轴方位、纵轴距离。

```lua
-- 自机位置
myPos = vehicle.transform.position
myFwd = vehicle.transform.forward (y置零归一得到 yawForward)
myRight = ...

-- 目标极坐标 (相对自机)
delta = targetPos - myPos; delta.y=0
range = delta.magnitude
az = atan2(Dot(delta,right), Dot(delta,fwd)) * Rad2Deg  -- 左负右正

-- FOV 裁剪
if math.abs(az) > FCRMaxAz/2 or range > FCRMaxRange then 不显示

-- 波束命中判断 (RWS扫描)
beamAz = 扫描波束当前角度 ( -scanAz/2 到 +scanAz/2 往复)
if math.abs(az - beamAz) < beamWidth/2 then
   track.lastSeen = Time.time; lastPos=realPos; lastVel=realVel
end

-- 外推 (类似 datalink)
age = Time.time - lastSeen
predPos = lastPos + flatVel * age * extraFactor
predRange, predAz = 重新算 predPos 的极坐标

-- B-Scope 归一化到方形
normX = predAz / (FCRMaxAz/2)  -- -1..1
normY = predRange / FCRMaxRange -- 0..1
uiX = normX * screen.sizeDelta.x * 0.5
uiY = normY * screen.sizeDelta.y * 0.5 (或 y = (normY-0.5)*height，看你原点要底对齐还是中心)

txt.pos = Vector3(uiX, uiY, 0)
txt.color.a = 1 - age/fadeTime
lineImg: 长度 = vel.magnitude * k，角度 = 目标航向在雷达平面投影
```

**STT模式**：`scanAz=10°, scanCenter = lockedTrack.az`, `rangeGate = lockedRange ± 300m`, `scanPeriod = 0.5s`, 所以刷新率 2Hz，接近实时，但仍受角度限制——如果目标机动超出 `scanAz/2 + gimbalLimit` (比如最大60°万向节)，则丢锁。

---

## 4. API 可行性 - 能否让雷达真正影响导弹和锁定？

### 4.1 干扰/反干扰机制现状
- 原版引擎：导弹 `isTrackedByMissile` 时，若目标载具放干扰，引擎直接 `ClearTrackerTarget()`，`currentTarget=nil`
- ADV脚本已部分对抗：丢失后0.2秒重捕，但若 `CheckAngleRange()` 失败或持续被干扰，仍丢。

### 4.2 雷达→导弹联动的三种等级

**L1 弱联动 (不改导弹脚本，FCR单脚本完成) - 可行**
- 利用 `GameEvents.onProjectileSpawned`
```lua
GameEvents.onProjectileSpawned.AddListener(self, "OnMissileSpawn")
function FCR:OnMissileSpawn(proj)
  if proj.source == self.vehicle.driver and self.lockedTrack and self.mode==STT then
     -- 强制把刚发射的导弹目标设为雷达锁定的目标，无视武器自己的锁定
     if proj.isTargetSeekingMissileProjectile then
        proj.SetTrackerTarget(self.lockedTrack.vehicleRef)
     end
  end
end
```
- 效果：你雷达锁谁，导弹就打谁，即使武器锁的是别人。已可打破原版“全图锁”。
- 限制：飞行中被干扰后，仍会走导弹自己的重捕逻辑，FCR帮不上。

**L2 中联动 (FCR+导弹脚本协同，需要小改 dvProjVarVel ADV) - 推荐**
- FCR 暴露全局状态：在同一 `GameObject` 上挂一个 `ScriptedBehaviour` 叫 `dvFCRState`
```lua
behaviour("dvFCRCore")
self.lockedTarget = Vehicle
self.isHardLock = bool -- STT时true
self.lockQuality = 0..1
```
- 导弹脚本启动时 `self.fcr = self.gameObject.GetComponentInParent/dvFCRCore` 或 `GameObject.FindObjectOfType(dvFCRCore)` 遍历找同载具的
- 改 `StartFlareCoolDown`：
```lua
if fcr and fcr.lockedTarget == self.lastTarget and fcr.isHardLock then
   -- 硬锁定：无视干扰，立即重捕
   self.projectile.SetTrackerTarget(self.lastTarget)
   self.isReady=true; return
end
-- 否则走原0.2s逻辑
```
- 可再扩展 DataContainer `FCR_HardLockIgnoresFlare` bool, `FCR_HardLockMaxAngle` 扩大判定角。
- 效果：STT硬锁定时，导弹完全无视干扰，实现类似 AIM-120 被主载波照射的抗干扰。TWS或RWS时仍可被干扰。

**L3 强联动 (完全重写锁定难度+发射许可) - 接近现代**
- **各向异性锁定难度**：FCR自己实现锁定计时器
```lua
lockTimeRequired = baseTime * (1 + k1*offBoresight + k2*range/maxRange + k3*aspect)
-- aspect: 目标朝向与你的夹角，正面1，尾部0
aspect = (Vector3.Angle(targetVel, -toTarget)/180)
```
- 只有当 `beamAz` 扫过目标且在FOV内，才累加 `lockProgress += dt`，否则衰减。
- 锁定满才允许 `weapon.canFire` 或自己调用 `weapon.Shoot(true)`。
- **武器 API**：`Weapon.canFire` 只读，`Weapon.isLocked` 可能存在，`Weapon.Shoot(force)` 可强制射。但无法直接改引擎的锁距 (在 WeaponEntry 里配 `TargetTracker` 配置)。所以最好自己控制射击时机，引擎的超视距锁可视为 disabled——通过把武器配置里锁距设短，或脚本里 `if not fcr.isLocked then return` 阻止发射。
- **答案**：有解，但需要你改武器配置 + 脚本协同，不是纯视觉。

### 4.3 与 AtoAHUD / HMD 联动
- **AtoAHUD**：它现在 `WorldToScreenPoint` 画提前量，可直接把 `target` 来源改成 `fcr.lockedTrack.vehicleRef`，这样HUD的弹道线就跟雷达锁一致。
```lua
-- 在 AtoAHUD:Update() 里优先取 FCR
local fcr = self.gameObject.GetComponent(dvFCRCore)
if fcr and fcr.lockedTrack then self.target = fcr.lockedTrack.vehicleRef end
```
- **HMD**：dvHMD 已算 `facingDirection` vs `vehicle.forward`。FCR增加 `ACM_BORE` 模式，扫描 `az=10°, el=10°, forward`，当 `Player.actor.facingDirection` 在阈值内且目标在 HUD 中心，可自动转STT，实现头瞄。

### 4.4 锁定框 Image
- 原雷达只用 `Text` 池，现代FCR需要 `Image`。Ravenscript API 有 `Image` 组件 (`GetComponent(Image)`), `color`, `rectTransform`, `sprite`。你可以：
  - 在 Mod Tools 里建两个池：`textPool` (线符号) + `imagePool` (锁定框贴图)
  - STT 时 `imagePool[1].rectTransform.anchoredPosition = lockedUI`
  - 闪烁可用 `CrossFadeAlpha` 或 `Mathf.Repeat(Time.time*2,1)>0.5`

---

## 5. 建议的新脚本群架构

```
Vehicle (同一载具)
 ├─ DataContainer (所有FCR参数)
 ├─ dvFCRCore (behaviour)
 │   ├─ targets: vehicle, screen, dataContainer, textPool, imagePool, canvas, lockImagePrefab
 │   ├─ state: RWS/TWS/STT/ACM
 │   ├─ tracks[] 带 age/lastPos/lastVel
 │   ├─ lockedTrack
 │   ├─ scanBeamAz, scanPeriod
 │   └─ onProjectileSpawned 监听 -> 强制 SetTrackerTarget
 ├─ dvFCRDisplay (可选，拆分显示层)
 │   └─ 负责 B-Scope Draw + 渐隐 + 线长
 ├─ dvProjVarVelFCR (改自 ADV)
 │   └─  query dvFCRCore 是否 hardLock -> 无视干扰
 └─ AtoAHUD_FCR (可选，AtoAHUD 改版，优先用 FCR锁)
```

**DataContainer 推荐字段**
```
FCRMaxRange 3000
FCRMinRange 500
FCRScanAzimuth 60
FCRScanAzimuthSTT 10
FCRScanSpeed 70 deg/s
FCRBeamWidth 3.5
FCRMaxElevation 45
FCRGimbalLimit 60  -- 超过丢锁
FCRFadeTime 4
FCRScanBar 4 -- 暂不用，留给以后三维
FCRLockTimeBase 1.5
FCRLockK_Angle 0.02
FCRLockK_Range 0.001
FCRLockK_Aspect 0.5
FCRHardLockIgnoresFlare true
FCRUseHMD true
FCRHMDMaxAngle 60
FCRUseSquare true
```

---

## 6. 开发路线图

**Phase1 - MVP方形B-Scope (纯视觉，可独立)**
- 实现 scanBeam Sweep + track 更新 + B-Scope 映射 + fade
- 距离/角度可调 (按键切换)
- 敌机显示成线 (velocity线)
- 提交为 dvFCR_RWS.txt

**Phase2 - STT + 锁定框**
- G键锁定最近track，切 STT，小角度高速扫描
- Image池画锁定框
- Gimbal限制 超出丢锁
- 各向异性 lockProgress

**Phase3 - 联动**
- L1 onProjectileSpawned 强制目标
- L2 改 dvProjVarVel ADV 查询 FCR，硬锁抗干扰
- AtoAHUD 改为可选读 FCR 锁

**Phase4 - HMD/ACM + 平衡**
- ACM模式：BORE/垂直扫描，复用 dvHMD 角度
- 被干扰率 = f(lockQuality, chaff?)，而非回合制
- 文档 + 预制体

---

## 7. 风险与边界

- **API 无 Set-only 限制**：`Weapon` 的锁距、锁角部分是只读 Entry，改不了引擎默认全图锁，只能通过脚本层面阻止发射或覆盖导弹目标来间接实现“雷达制约”。这意味着原版武器的锁圈UI可能仍会全图亮，但你的雷达脚本不让你打。
- **多载具通信**：DataContainer 不支持运行时 Set，所以跨载具 (如多人联机) 同步雷达状态靠 FCR 自己同步不了，只能本机有效。单机够用。
- **性能**：`VehiclesInRange` 每扫一次全图遍历，若 scanInterval 0.2s + 多架飞机，O(n) 可接受，n<100。
- **艺术资源**：线贴图和锁定框需你自做 Sprite，脚本只负责位置/透明度/旋转。

**总结**：完全可行，且是 Ravenfield 空战从“回合制干扰”进化到“雷达主导”的关键。先做视觉版 dvFCR，再做 L1 联动，再考虑是否改导弹脚本做 L2 硬抗干扰。各向异性锁定难度和距离/角度限制都能用 API 模拟，虽然不能改引擎底层锁距，但能通过控制发射许可达到同样游戏体验。
