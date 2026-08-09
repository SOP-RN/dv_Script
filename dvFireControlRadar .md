# dvFireControlRadar - 弱联动版说明

## 功能 (Weak Linkage)
- **方形 B-Scope**：横轴=方位角(azimuth)，纵轴=距离(range)，底部是本机，顶部是远距。非圆形。
- **波束扫描**：`beamAz` 以 `scanSpeed (deg/s)` 在 `±scanAz/2` 往复扫，`beamWidth` 内才命中目标并刷新 `lastSeen`。扫不到就外推+渐隐。
- **距离/方位可调**：`PageUp/PageDown` 切量程，`Home/End` 切方位。量程/方位列表来自 DataContainer `FCRRangeSteps / FCRAzimuthSteps`，也可在 ModTools 改。
- **渐隐**：`alpha = 1 - age/FadeTime`，类似 dvDatalinkMap。
- **线显示**：可选 `linePool` (Image池)，线长=速度，角度=目标航向相对本机。符号本身不旋，线表示航向，满足“敌机显示成一条线”。
- **TWS/STT**：
  - 默认 RWS/TWS 多目标
  - `G` 键锁定最近且靠近中心的航迹 → 转 STT，方位缩至 `FCRScanAzimuthSTT=10°`，距离门 ±`FCRMaxRangeSTT`，扫描周期变短 (角度小=扫得快)
  - 再按 `G` 解锁
  - 超万向节 `FCRGimbalLimit` 或 `age>fade` 自动丢锁
- **锁定框**：可选 `lockImage` RectTransform，STT时移到目标 UI 坐标，带闪烁。
- **波束指示**：可选 `beamImage` 显示当前波束方位。

## 弱联动导弹 - 核心
```lua
GameEvents.onProjectileSpawned -> OnProjectileSpawned(proj)
if proj.killCredit==Player.actor and mode==STT and lockedTrack存在 then
  proj.SetTrackerTarget(lockedTrack.vehicleRef) -- 强制覆盖引擎锁
表 ownMissiles 存己方导弹
每帧若 proj.currentTarget==nil 且 STT硬锁，立即 SetTrackerTarget(locked) -> 实现无视干扰 (hardLock)
```

- **效果**：雷达锁谁，导弹打谁，打破原版全图锁。STT硬锁时，即使被箔条清除，也在下一帧重捕，接近“主载波照射抗干扰”。
- **限制**：L1 不改导弹脚本，抗干扰是“丢后立即重捕”，仍有 1 帧空窗；若要完全无视，需 L2 改 `dvProjVarVel ADV` 查询 FCR 状态。

## Targets 配置
必要：`vehicle, screen, dataContainer, textPool`
可选：`linePool (Image[]), lockImage, beamImage, rangeText, statusText, canvas`

`screen` 必须是方形 RectTransform。

## DataContainer 字段
```
FCRMaxRange 4000
FCRScanAzimuth 60
FCRBeamWidth 3.5
FCRScanSpeed 70
FCRFadeTime 4.0
FCRGimbalLimit 60
FCRMaxElevation 45
FCRScanAzimuthSTT 10
FCRMaxRangeSTT 400
FCRMinAlpha 0
FCRHardLockIgnoresFlare true
FCRRangeSteps = 2000,4000,8000,12000
FCRAzimuthSteps = 120,60,30,10
RadarEnemyColor / Allied etc 复用
```

## 输入
- `G` 锁定/解锁
- `PageUp/PageDown` 量程
- `Home/End` 方位

## 后续可扩展到 L2/L3
- L2：改 dvProjVarVel ADV，查询 `dvFCRCore` 的 `isHardLock`，若 true 则跳过 `FlareCoolDown`，完全无视。
- L3：实现各向异性锁定计时 `lockTime = base*(1+k_angle*offBoresight + k_range*range + k_aspect*aspect)`，只有波束命中才累加，引擎锁圈可无视。

## 与之前 dvRadar 的区别
- 不再是圆形 PPI 上帝图，是 B-Scope 方形火控
- 扫描有过程，非瞬时
- 有万向节、距离门、波束宽度等限制
- 有 TWS→STT 状态机
- 直接影响导弹目标

---
Soppi风格注释，兼容 Ravenscript API：ActorManager.VehiclesInRange, Vector3.Angle, Quaternion, GameEvents.onProjectileSpawned, Projectile.SetTrackerTarget, Image.color 等均实测存在。
