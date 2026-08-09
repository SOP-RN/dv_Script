# dvDatalinkMap - 数据链地图脚本说明

## 1. 功能概述
`dvDatalinkMap` 在 `dvRadar 1/2` 基础上增加了战术数据链的真实感：

- **扫描间隔**：不再实时刷新，而是每 `DatalinkScanTime` (默认1.0s) 扫描一次。两次扫描之间，航迹按最后已知速度外推。
- **机动滞后**：目标剧烈机动时，外推位置与真实位置偏差变大，产生“需要打提前量”的效果。可通过 `DatalinkExtraFactor` 调节滞后程度。
- **渐隐消失**：航迹年龄 `age = Time.time - lastSeen`，透明度 `alpha = 1 - age / fadeTime`，超过 `DatalinkFadeTime` (默认3.0s) 自动移除。
- **兼容性**：Targets、DataContainer字段、符号系统完全兼容 dvRadar 2。

## 2. 关键实现

### 2.1 为什么能直接改材质透明度？
Ravenscript 的 `Text` 组件继承自 Unity `UI.Text`，有 `color` 属性，类型是 `UnityEngine.Color`，包含 `r,g,b,a`。API 文档显示：
- `Text.color` 可读可写
- `Color(r,g,b,a)` 构造函数存在，且 `Color.a` 可访问

所以不需要像你说的那样 Instantiate + Animator，直接每帧：
```lua
local alpha = 1 - age / fadeTime
txt.color = Color(base.r, base.g, base.b, base.a * alpha)
```
即可实现越旧越淡。如果想做更复杂的尾迹特效，也可以用 `GameObject.Instantiate(prefab)` 生成带 Animator 的小点，但池化方案性能更差，且需要额外 prefab 配置。颜色 alpha 方案零额外资源。

### 2.2 扫描与外推
```lua
-- 扫描层：低频
scanTimer += deltaTime
if scanTimer >= scanInterval then
  ScanDatalink() -- 更新 lastPos, lastVel, lastSeen
end

-- 绘制层：每帧
predictedPos = lastPos + flatVel * age * extraFactor
```
- `flatVel` 只取 `x,z`，因为雷达是俯视2D投影（原脚本 delta.y=0）。
- `extraFactor = 1.0` 为真实死推算(dead reckoning)，`<1.0` 人为增加滞后，`=0` 则航迹冻结在最后位置，滞后最大。

### 2.3 排序与限数
沿用 dvRadar 的 `MaxGroundVehicles / MaxBoats / MaxFriendlyAir`，但改为针对**存活航迹池**计数，避免新目标无限增加。

## 3. dvRadar 1 vs dvRadar 2 缩放策略区别

### dvRadar 1 (原版简化)
```lua
targetRange = radarMaxRange
if missiles > 0 then
  nearest = min(dist missiles)
  targetRange = nearest * 1.25 clamp(min,max)
radarRange = Lerp(radarRange, targetRange, dt*zoomSpeed)
```
- **策略**：**默认最大，导弹接近时收缩**。
- 只有 missile 接近才 zoom in，保证导弹始终在雷达圈内可见，避免导弹在边缘看不到。
- 无配置项，行为固定。

### dvRadar 2 (进阶)
新增 `RadarZoomMode` int：

- **Mode 0 - 默认最大 / 导弹收缩 (同 Radar1)**：
  `targetRange = radarMaxRange` → 有 missile 时 `nearest *1.25` → Clamp → Lerp
  适合**攻击型**视角，平时看全图，导弹来时聚焦近距。

- **Mode 1 - 默认最小 / 导弹扩张**：
  `targetRange = radarMinRange` → 有 missile 时 `farthest *1.25` → Clamp → Lerp
  逻辑相反：平时用小范围高分辨率，导弹在远处时自动扩张，确保最远的 missile 也在圈内。
  适合**防御型**视角，平时专注近距格斗，有远距威胁时才放大。

**其他区别**：
- dvRadar2 符号可配置：`RadarEnemyAirSymbol` 等 7 个 string，可在 DataContainer 中自定义图标字符，不再硬编码 "C/D/G/H/F"。
- dvRadar2 敌我地面/船也区分颜色（友军地面/船用 friendlyColor），而 dvRadar1 地面/船固定 enemyColor。
- 共同点：两者都用 `Mathf.Lerp` 平滑过渡，`RadarZoomSpeed` 控制平滑速度。

## 4. DataContainer 配置建议

| ID | 类型 | 推荐值 | 说明 |
|---|---|---|---|
| RadarEffectDistance | float | 3000 | 最大显示距离 |
| RadarMinDistance | float | 500 | 最小缩放 |
| RadarZoomSpeed | float | 2.0 | |
| RadarZoomMode | int | 0 | 0/1 |
| RadarUpdateTime | float | 0.1 | 作为 DatalinkScanTime fallback |
| DatalinkScanTime | float | 1.0-1.5 | 扫描间隔，越大越滞后 |
| DatalinkFadeTime | float | 3.0 | 渐隐时长 |
| DatalinkExtraFactor | float | 0.8 | 0=冻结，1=真实死推 |
| DatalinkMinAlpha | float | 0.0 | |
| DatalinkUseScaleFade | bool | false | 旧航迹缩小 |
| MaxGroundVehicles | int | 6 | |
| MaxBoats | int | 3 | |
| MaxFriendlyAir | int | 4 | |
| RadarEnemyColor | color | (1,0.2,0.2) | |
| RadarAlliedColor | color | (0.3,0.8,1) | |
| RadarEnemyAirSymbol | string | C | |
| RadarFriendlyAirSymbol | string | D | |
| ... | ... | ... | |

Targets 保持 4 个：vehicle, screen, dataContainer, textPool。

## 5. 性能与扩展
- 文本池复用，O(n log n) 排序，n<~30，性能足够。
- 如果想做“尾迹点”而不是单点，可把一个航迹对应多个 Text，历史位置队列即可。
- 如果需要 IFF 闪烁，可在 alpha 基础上再乘 `Mathf.Repeat(Time.time*2,1)`。

---
Soppi 风格注释，保持与原脚本相同的习惯，使用 `Vector3.zero`, `Color`, `Quaternion.Euler` 等 Ravenscript 可用 API。
