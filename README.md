# Ravenfield_random
Soppi's script for ravenfield

Some script's are based on Red's (penguin) and Lezvin's script (some are inspired by some scripts from debil)

https://github.com/SOP-RN/Ravenfield_random/wiki

Here are some brief explanations of scripts.
AntiAirHUD: 自动弹道解算 (稳定）

AtoAHUD old: 空对空版本的 AntiAirHUD ，拥有特殊功能 (偏稳定）

AtoAHUD: 空对空版本的 AntiAirHUD ，拥有特殊功能 (稳定）

MortarHUD: 抛射武器用的自动弹道解算，和AntiAirHUD来自同一个基础脚本的迭代 (稳定）

DvADS:在一定范围内提前引爆来自敌方的火箭弹类型投射物的主动防御脚本

DvBrakeGate:基于纵向速度变化率触发粒子效果的刹车触发器

DvDampVelZ: 缓冲 Velocity Z 并输出一个缓冲过的Vel Z

DvSpaceFire: 按下空格射击某副武器

DvSpaceFireMounted:未测试

dvProjVarVel: dv标准导弹脚本，特点是可变速度 (稳定）

dvProjVarVel ADV: dv高级导弹脚本，特点是可变速度 (稳定）

GPTSpecialProjectile:dvProjVarVel的前身

GuidedBombVel: 企鹅 的 specialprojectile 脚本的简化版，可以使滑翔炸弹继承速度 (稳定）

dvHMDC/M: HMD 头戴式显示器脚本, 2个脚本对应两个物体，可同时使用， 按照角度控制物体可见性 （可能需要更新功能，但是以前运行很稳定）

dvInputDamp: 缓冲输入并输出一个缓冲过的输入 (稳定)

dvPSE：highGturn功能，动画机控制

dvPSE ADV：飞机部件损坏系统（不可修复），包含 结构损伤（机翼/尾翼/引擎）+ 非对称推力 + 控制退化 + highGturn功能，动画机控制 (疑似功能异常)

dvPSE ADV2：飞机部件损坏系统（可修复），包含ADV的所有功能，严重依赖动画机控制，目前在AFX635上使用 (稳定)

High G turn：dvPSE 的原始版本，可以增强飞机的转向能力 (稳定)

High G turn 2：原本作为 dvPSE 的基础 (功能异常)

High G turn pg: 目前在用的版本，企鹅制作 (稳定)

dv_CCam：电影运镜摄像机（已经在创意工坊中） (老版本下稳定，新版本下疑似失效)

dv_Gloc：基于 dvGsim 衍生的载具通用 mutator 脚本（已经在创意工坊中） (稳定)

dv_Hitsfx：载具被击中时播放音效的 mutator 脚本（已经在创意工坊中） (老版本下稳定，新版本下疑似失效)

dvGPstat：用于计算并显示飞机所需参数的脚本（G、M、alpha、高度等） (稳定)

dvGsim(noanim)：用于 G 力计算与模拟的脚本，会向 animator 输出 float（“noanim”版本不包含 animator 相关功能）

gear controller：控制飞机起落架 (稳定)

dvRWR：RWR，简化版 dvRadar，显示导弹方向并通过闪烁速度显示导弹距离，(稳定)

dvRadar1：雷达，敌我不同图标不同颜色，具有 2 种尺寸调整模式，(稳定)

dvRadar2：雷达，敌我相同图标不同颜色，具有 1 种尺寸调整模式，(稳定)

ReSpecialProjectile: 制导导弹脚本，被flare之后可以再锁定

ReSpecialProjectile Direct: 所有投射物都可使用，效果同上，但是不带平滑

ReProjectileBox: 导弹碰撞箱脚本，碰撞箱被击毁即引爆导弹

ReModelsController: 控制弹药消失（炸弹，火箭弹等）
