behaviour("dvFireControlRadar")
-- =================================================
-- dvFireControlRadar - 现代火控雷达 弱联动版 (B-Scope方形)
-- 从头构建，非 AWACS 小地图
--
-- 特性：
-- 1) 方形 B-Scope：X=方位(az)，Y=距离(range)，非圆形PPI
-- 2) 距离可调，方位可调，扫描波束 Sweep，扫到才更新 (扫描后同步)
-- 3) 敌机显示成线：速度矢量线，符号不旋转 (线贴图用户自备)
-- 4) 航迹渐隐：age/fadeTime -> Text/Image alpha，超阈值消失
-- 5) TWS多目标 + STT单目标锁定，STT时只扫目标附近，角度小=扫得更快
-- 6) 锁定框：锁定目标处显示 Image (用户自备贴图)
-- 7) 弱联动导弹：监听 onProjectileSpawned，发射瞬间强制把导弹目标设为雷达锁定目标；
--    并在 Update 中对己方导弹做丢锁后硬锁重捕 (STT时无视干扰)
-- 8) 最大角度/距离限制：Gimbal + FOV 裁剪
--
-- DataContainer 字段 (都有默认值)：
-- FCRMaxRange 3000 初始距离
-- FCRScanAzimuth 60 初始方位扇区
-- FCRBeamWidth 3.5 波束宽度
-- FCRScanSpeed 70 deg/s 扫描速度
-- FCRFadeTime 4.0 渐隐时长
-- FCRGimbalLimit 60 万向节极限，超此角度丢锁
-- FCRMaxElevation 45 (预留)
-- FCRRangeSteps float[] 例如 2000,4000,8000,12000
-- FCRAzimuthSteps float[] 例如 120,60,30,10
-- FCRScanAzimuthSTT 10 STT时方位
-- FCRMaxRangeSTT 1500 STT时距离门半宽 ±
-- FCRMinAlpha 0.0
-- RadarEnemyColor / RadarAlliedColor 复用
-- FCRHardLockIgnoresFlare true 弱联动中 STT无视干扰
-- FCRUseScaleFade false
-- 符号同 RadarEnemyAirSymbol 等
--
-- Targets (必要 + 可选)：
-- vehicle (Vehicle)
-- screen (RectTransform) 方形雷达容器
-- dataContainer (DataContainer)
-- textPool (Text[] 池)
-- -- 可选 --
-- linePool (Image[] 或 RectTransform[] 池，用于速度线)
-- lockImage (RectTransform/Image) 单个锁定框，STT时移到目标上
-- beamImage (RectTransform) 波束位置指示器 (横向一条)
-- rangeText (Text) 显示距离/方位/模式
-- statusText (Text) 显示锁定信息
-- =================================================
local RadarType = { MISSILE=1, AIR=2, GROUND=3, BOAT=4 }
local FCRMode = { RWS=0, TWS=1, STT=2, ACM=3 }
local function SafeCall(dc, fn, id, def)
    local ok, val = pcall(function() return dc[fn](dc, id) end)
    if ok and val ~= nil then
        if type(val)=="number" and val==0 and def~=0 then
            if string.find(id,"FCR") then return def end
        end
        if type(val)=="string" and val=="" and def~="" then
            if string.find(id,"FCR") or string.find(id,"Radar") then return def end
        end
        return val
    end
    return def
end
local function SafeCallArray(dc, fn, id, def)
    local ok, val = pcall(function() return dc[fn](dc, id) end)
    if ok and val ~= nil and #val>0 then return val end
    return def
end
function dvFireControlRadar:Start()
    self.vehicle = self.targets.vehicle.GetComponent(Vehicle)
    self.rtScreen = self.targets.screen.GetComponent(RectTransform)
    self.dc = self.targets.dataContainer.GetComponent(DataContainer)
    self.textPool = self.targets.textPool.GetComponentsInChildren(Text)
    -- 可选池
    self.linePool = nil
    if self.targets.linePool then
        local ok, comps = pcall(function() return self.targets.linePool.GetComponentsInChildren(Image) end)
        if ok and comps then self.linePool = comps else self.linePool = nil end
    end
    self.lockImageRT = nil
    if self.targets.lockImage then
        self.lockImageRT = self.targets.lockImage.GetComponent(RectTransform)
        -- 初始隐藏
        if self.lockImageRT then self.lockImageRT.localScale = Vector3.zero end
    end
    self.beamImageRT = nil
    if self.targets.beamImage then
        self.beamImageRT = self.targets.beamImage.GetComponent(RectTransform)
    end
    self.rangeText = nil
    if self.targets.rangeText then self.rangeText = self.targets.rangeText.GetComponent(Text) end
    self.statusText = nil
    if self.targets.statusText then self.statusText = self.targets.statusText.GetComponent(Text) end
    ------------------------------------------------
    -- FCR 参数
    ------------------------------------------------
    self.maxRange = SafeCall(self.dc, "GetFloat", "FCRMaxRange", 4000)
    self.scanAz = SafeCall(self.dc, "GetFloat", "FCRScanAzimuth", 60)
    self.beamWidth = SafeCall(self.dc, "GetFloat", "FCRBeamWidth", 3.5)
    self.scanSpeed = SafeCall(self.dc, "GetFloat", "FCRScanSpeed", 70)
    self.fadeTime = SafeCall(self.dc, "GetFloat", "FCRFadeTime", 4.0)
    self.gimbalLimit = SafeCall(self.dc, "GetFloat", "FCRGimbalLimit", 60)
    self.maxElevation = SafeCall(self.dc, "GetFloat", "FCRMaxElevation", 45)
    self.scanAzSTT = SafeCall(self.dc, "GetFloat", "FCRScanAzimuthSTT", 10)
    self.rangeGateSTT = SafeCall(self.dc, "GetFloat", "FCRMaxRangeSTT", 400) -- ±
    self.minAlpha = SafeCall(self.dc, "GetFloat", "FCRMinAlpha", 0.0)
    self.hardLockIgnoresFlare = SafeCall(self.dc, "GetBool", "FCRHardLockIgnoresFlare", true)
    self.ranges = SafeCallArray(self.dc, "GetFloatArray", "FCRRangeSteps", {2000, 4000, 8000, 12000})
    self.azimuths = SafeCallArray(self.dc, "GetFloatArray", "FCRAzimuthSteps", {120, 60, 30, 10})
    -- 确保当前在列表内
    self.rangeIdx = 1
    for i=1,#self.ranges do if math.abs(self.ranges[i]-self.maxRange)<1 then self.rangeIdx=i break end end
    self.azIdx = 1
    for i=1,#self.azimuths do if math.abs(self.azimuths[i]-self.scanAz)<1 then self.azIdx=i break end end
    ------------------------------------------------
    -- 颜色符号
    ------------------------------------------------
    self.enemyColor = SafeCall(self.dc, "GetColor", "RadarEnemyColor", Color(1,0.2,0.2,1))
    self.friendlyColor = SafeCall(self.dc, "GetColor", "RadarAlliedColor", Color(0.3,0.8,1,1))
    self.enemyAirSymbol = SafeCall(self.dc, "GetString", "RadarEnemyAirSymbol", "C")
    self.friendlyAirSymbol = SafeCall(self.dc, "GetString", "RadarFriendlyAirSymbol", "D")
    self.enemyGroundSymbol = SafeCall(self.dc, "GetString", "RadarEnemyGroundSymbol", "G")
    self.friendlyGroundSymbol = SafeCall(self.dc, "GetString", "RadarFriendlyGroundSymbol", "G")
    self.enemyBoatSymbol = SafeCall(self.dc, "GetString", "RadarEnemyBoatSymbol", "H")
    self.friendlyBoatSymbol = SafeCall(self.dc, "GetString", "RadarFriendlyBoatSymbol", "H")
    self.missileSymbol = SafeCall(self.dc, "GetString", "RadarMissileSymbol", "E")
    self.lockedSymbol = SafeCall(self.dc, "GetString", "FCRLockedSymbol", "[ ]")
    ------------------------------------------------
    -- 扫描波束状态
    ------------------------------------------------
    self.beamAz = -self.scanAz/2
    self.beamDir = 1
    self.mode = FCRMode.RWS
    self.lockedTrack = nil
    self.tracks = {}
    self.ownMissiles = {} -- {proj=Projectile, spawnTime}
    ------------------------------------------------
    -- 输入计时
    ------------------------------------------------
    self.lockKey = KeyCode.G
    self.rangeUpKey = KeyCode.PageUp
    self.rangeDownKey = KeyCode.PageDown
    -- 方位调节
    self.azUpKey = KeyCode.Home
    self.azDownKey = KeyCode.End
    ------------------------------------------------
    -- 监听导弹发射 (弱联动核心)
    ------------------------------------------------
    local ok = pcall(function()
        GameEvents.onProjectileSpawned.AddListener(self, "OnProjectileSpawned")
    end)
    if not ok then print("[FCR] onProjectileSpawned listener failed") end
end
function dvFireControlRadar:OnDestroy()
    pcall(function() GameEvents.onProjectileSpawned.RemoveListener(self, "OnProjectileSpawned") end)
end
------------------------------------------------
-- 主循环
------------------------------------------------
function dvFireControlRadar:Update()
    if not self.vehicle or not self.vehicle.playerIsInside then
        self:ResetPool()
        self:HideLockImage()
        self.tracks = {}
        self.lockedTrack = nil
        self.mode = FCRMode.RWS
        self.ownMissiles = {}
        return
    end
    self:HandleInputs()
    self:UpdateBeam(Time.deltaTime)
    self:ScanAndUpdateTracks()
    self:PruneTracks()
    self:UpdateLockState()
    self:UpdateOwnMissilesHardLock()
    self:ResetPool()
    self:DrawTracksBScope()
    self:DrawBeamIndicator()
    self:DrawLockImage()
    self:DrawInfoTexts()
end
------------------------------------------------
-- 输入：距离/方位/锁定
------------------------------------------------
function dvFireControlRadar:HandleInputs()
    if Input.GetKeyDown(self.rangeUpKey) then
        self.rangeIdx = math.min(self.rangeIdx+1, #self.ranges)
        if self.mode ~= FCRMode.STT then
            self.maxRange = self.ranges[self.rangeIdx]
        end
    end
    if Input.GetKeyDown(self.rangeDownKey) then
        self.rangeIdx = math.max(self.rangeIdx-1, 1)
        if self.mode ~= FCRMode.STT then
            self.maxRange = self.ranges[self.rangeIdx]
        end
    end
    if Input.GetKeyDown(self.azUpKey) then
        self.azIdx = math.min(self.azIdx+1, #self.azimuths)
        if self.mode ~= FCRMode.STT then
            self.scanAz = self.azimuths[self.azIdx]
        end
    end
    if Input.GetKeyDown(self.azDownKey) then
        self.azIdx = math.max(self.azIdx-1, 1)
        if self.mode ~= FCRMode.STT then
            self.scanAz = self.azimuths[self.azIdx]
        end
    end
    if Input.GetKeyDown(self.lockKey) then
        if self.mode == FCRMode.STT and self.lockedTrack then
            -- 解锁 -> 回 TWS
            self.lockedTrack = nil
            self.mode = FCRMode.TWS
            -- 恢复之前扫描参数
            self.scanAz = self.azimuths[self.azIdx]
            self.maxRange = self.ranges[self.rangeIdx]
            self.beamAz = -self.scanAz/2
        else
            self:TryLockNearest()
        end
    end
end
function dvFireControlRadar:TryLockNearest()
    -- 在当前有效航迹中找最靠近中心 (az~0) 且最近的
    local best = nil
    local bestScore = 1e9
    local now = Time.time
    for i=1,#self.tracks do
        local tr = self.tracks[i]
        local age = now - tr.lastSeen
        if age < self.fadeTime then
            -- 预测方位
            local predAz, predRange = self:GetTrackPolar(tr)
            if math.abs(predAz) < self.scanAz/2 and predRange < self.maxRange then
                -- 评分：az权重高
                local score = math.abs(predAz)*2 + predRange*0.001
                if tr.type == RadarType.AIR then score = score - 10 end -- 优先空
                if score < bestScore then bestScore=score best=tr end
            end
        end
    end
    if best then
        self.lockedTrack = best
        self.mode = FCRMode.STT
        self.scanAz = self.scanAzSTT
        -- 距离门以锁定目标为中心，暂时扩展显示范围以看门
        -- 扫描中心会跟随目标
        self.beamAz = self:GetTrackPolar(best) -- 设到目标az
        self.beamDir = 1
    end
end
------------------------------------------------
-- 波束更新
------------------------------------------------
function dvFireControlRadar:UpdateBeam(dt)
    local centerAz = 0
    local halfAz = self.scanAz/2
    if self.mode == FCRMode.STT and self.lockedTrack then
        local lockedAz, _ = self:GetTrackPolar(self.lockedTrack)
        centerAz = lockedAz
        -- STT时万向节限制
        if math.abs(centerAz) > self.gimbalLimit then
            -- 超万向节，丢锁
            self.lockedTrack = nil
            self.mode = FCRMode.TWS
            self.scanAz = self.azimuths[self.azIdx]
            self.maxRange = self.ranges[self.rangeIdx]
            centerAz = 0
            halfAz = self.scanAz/2
        end
    end
    self.beamAz = self.beamAz + self.beamDir * self.scanSpeed * dt
    if self.beamAz > centerAz + halfAz then
        self.beamAz = centerAz + halfAz
        self.beamDir = -1
    elseif self.beamAz < centerAz - halfAz then
        self.beamAz = centerAz - halfAz
        self.beamDir = 1
    end
end
------------------------------------------------
-- 扫描并更新航迹 (只有波束打中才刷新)
------------------------------------------------
function dvFireControlRadar:ScanAndUpdateTracks()
    local myPos = self.vehicle.transform.position
    -- 用最大可能范围搜，减少调用
    local searchRange = self.ranges[#self.ranges]
    if self.maxRange > searchRange then searchRange = self.maxRange end
    local vehicles = ActorManager.VehiclesInRange(myPos, searchRange)
    local now = Time.time
    for i=1,#vehicles do
        local v = vehicles[i]
        if v and v~=self.vehicle and not v.isDead and v.hasDriver and not v.isTurret then
            local delta = v.transform.position - myPos
            local flatDelta = Vector3(delta.x,0,delta.z)
            local range = delta.magnitude
            -- 方位角
            local yawFwd = Vector3(self.vehicle.transform.forward.x,0,self.vehicle.transform.forward.z).normalized
            local yawRight = Vector3(yawFwd.z,0,-yawFwd.x)
            local az = math.atan2(Vector3.Dot(delta, yawRight), Vector3.Dot(delta, yawFwd)) * Mathf.Rad2Deg
            local el = math.atan2(delta.y, flatDelta.magnitude) * Mathf.Rad2Deg
            -- 硬限制：万向节 + 距离 + 仰角
            if math.abs(az) > self.gimbalLimit then goto continue end
            if range > self.maxRange then
                -- STT时允许距离门 ± rangeGateSTT
                if self.mode==FCRMode.STT and self.lockedTrack then
                    local _, lockedRange = self:GetTrackPolar(self.lockedTrack)
                    if math.abs(range - lockedRange) > self.rangeGateSTT then goto continue end
                else
                    goto continue
                end
            end
            if math.abs(el) > self.maxElevation then goto continue end
            -- 是否被当前波束照射
            if math.abs(az - self.beamAz) > self.beamWidth/2 then
                -- 波束未命中，不刷新，但已有的track继续外推
                goto continue
            end
            -- 命中，更新/新建航迹
            local idx = self:FindTrackByRef(v)
            local vel = Vector3.zero
            if v.rigidbody then vel = v.rigidbody.velocity end
            if idx then
                local tr = self.tracks[idx]
                tr.lastPos = v.transform.position
                tr.lastVel = vel
                tr.lastSeen = now
                tr.team = v.team
                tr.range = range
                tr.az = az
                tr.el = el
            else
                local rType = RadarType.GROUND
                if v.isAirplane or v.isHelicopter then rType=RadarType.AIR
                elseif v.isBoat then rType=RadarType.BOAT end
                local nt = {
                    vehicleRef=v,
                    type=rType,
                    team=v.team,
                    lastPos=v.transform.position,
                    lastVel=vel,
                    lastSeen=now,
                    range=range,
                    az=az,
                    el=el
                }
                table.insert(self.tracks, nt)
            end
        end
        ::continue::
    end
    -- 导弹也作为目标？可选，这里只跟踪己方被锁导弹已在 missile list，空战一般不把导弹画在FCR上，忽略
end
function dvFireControlRadar:FindTrackByRef(ref)
    for i=1,#self.tracks do if self.tracks[i].vehicleRef==ref then return i end end
    return nil
end
function dvFireControlRadar:GetTrackPolar(track)
    -- 外推后计算方位距离
    local predPos = self:GetExtrapolatedPos(track)
    local myPos = self.vehicle.transform.position
    local delta = predPos - myPos
    local yawFwd = Vector3(self.vehicle.transform.forward.x,0,self.vehicle.transform.forward.z).normalized
    local yawRight = Vector3(yawFwd.z,0,-yawFwd.x)
    local az = math.atan2(Vector3.Dot(delta, yawRight), Vector3.Dot(delta, yawFwd)) * Mathf.Rad2Deg
    local range = delta.magnitude
    return az, range
end
function dvFireControlRadar:GetExtrapolatedPos(track)
    local age = Time.time - track.lastSeen
    -- 死推，0.8系数增加滞后感
    local flatVel = Vector3(track.lastVel.x,0,track.lastVel.z)
    return track.lastPos + flatVel * age * 0.85
end
function dvFireControlRadar:PruneTracks()
    local now = Time.time
    local i=1
    while i<=#self.tracks do
        local tr=self.tracks[i]
        local age=now-tr.lastSeen
        if age>self.fadeTime then
            -- 若是锁定目标，丢锁
            if self.lockedTrack and self.lockedTrack.vehicleRef==tr.vehicleRef then
                self.lockedTrack=nil
                self.mode=FCRMode.TWS
                self.scanAz=self.azimuths[self.azIdx]
                self.maxRange=self.ranges[self.rangeIdx]
            end
            table.remove(self.tracks,i)
        else
            if tr.vehicleRef and tr.vehicleRef.isDead and age>1.0 then
                -- 死亡目标1秒后淡出
                if age>self.fadeTime then table.remove(self.tracks,i) else i=i+1 end
            else
                i=i+1
            end
        end
    end
end
function dvFireControlRadar:UpdateLockState()
    if self.mode==FCRMode.STT and self.lockedTrack then
        -- 检查锁定目标是否仍满足
        local az, range = self:GetTrackPolar(self.lockedTrack)
        local age = Time.time - self.lockedTrack.lastSeen
        -- 距离门
        if range > self.maxRange and math.abs(range - self.maxRange) > self.rangeGateSTT then
            -- 目标飞出距离门且STT扫描已无法覆盖，丢锁
            -- 允许一定宽容
        end
        if age > self.fadeTime then
            self.lockedTrack=nil
            self.mode=FCRMode.TWS
            self.scanAz=self.azimuths[self.azIdx]
            self.maxRange=self.ranges[self.rangeIdx]
        end
    end
end
------------------------------------------------
-- 弱联动导弹
------------------------------------------------
function dvFireControlRadar:OnProjectileSpawned(proj)
    -- 只关心己方发射的追踪导弹
    if not proj then return end
    if not proj.isTargetSeekingMissileProjectile then return end
    if not proj.killCredit then return end
    if proj.killCredit ~= Player.actor then return end
    if not self.vehicle.playerIsInside then return end
    -- 记录
    table.insert(self.ownMissiles, {proj=proj, spawnTime=Time.time})
    -- 立即硬锁覆盖
    if self.mode==FCRMode.STT and self.lockedTrack and self.lockedTrack.vehicleRef then
        local tgt = self.lockedTrack.vehicleRef
        if tgt.team ~= self.vehicle.team then
            -- 强制
            local ok = pcall(function() proj.SetTrackerTarget(tgt) end)
            if ok then print("[FCR] missile retargeted to locked "..tgt.name) end
        end
    end
end
function dvFireControlRadar:UpdateOwnMissilesHardLock()
    if not self.hardLockIgnoresFlare then return end
    if not self.lockedTrack or self.mode~=FCRMode.STT then return end
    local lockedVeh = self.lockedTrack.vehicleRef
    if not lockedVeh or lockedVeh.isDead then return end
    local i=1
    while i<=#self.ownMissiles do
        local entry = self.ownMissiles[i]
        local proj = entry.proj
        if not proj or not proj.isActive then
            table.remove(self.ownMissiles,i)
        else
            -- 如果丢锁，重捕
            if not proj.currentTarget then
                pcall(function() proj.SetTrackerTarget(lockedVeh) end)
            else
                -- 若当前目标不是锁定目标，强制纠正 (硬锁)
                if proj.currentTarget ~= lockedVeh then
                    -- 只有在STT硬锁模式下才强制，防止误伤
                    if self.hardLockIgnoresFlare then
                        pcall(function() proj.SetTrackerTarget(lockedVeh) end)
                    end
                end
            end
            i=i+1
        end
    end
end
------------------------------------------------
-- 绘制：B-Scope方形
------------------------------------------------
function dvFireControlRadar:ResetPool()
    for i=1,#self.textPool do
        self.textPool[i].rectTransform.localScale = Vector3.zero
    end
    if self.linePool then
        for i=1,#self.linePool do
            self.linePool[i].rectTransform.localScale = Vector3.zero
        end
    end
end
function dvFireControlRadar:HideLockImage()
    if self.lockImageRT then self.lockImageRT.localScale = Vector3.zero end
end
function dvFireControlRadar:DrawTracksBScope()
    local now = Time.time
    local poolIdx=1
    local lineIdx=1
    -- 按距离排序，近的优先画
    table.sort(self.tracks, function(a,b)
        local _, ra = self:GetTrackPolar(a)
        local _, rb = self:GetTrackPolar(b)
        return ra < rb
    end)
    local screenW = self.rtScreen.sizeDelta.x
    local screenH = self.rtScreen.sizeDelta.y
    for i=1,#self.tracks do
        if poolIdx > #self.textPool then break end
        local tr = self.tracks[i]
        local age = now - tr.lastSeen
        local ageNorm = age / self.fadeTime
        if ageNorm>=1 then goto cont end
        local az, range = self:GetTrackPolar(tr)
        -- 是否在当前显示扇区内？STT时中心跟随
        local centerAz = 0
        if self.mode==FCRMode.STT and self.lockedTrack then
            centerAz, _ = self:GetTrackPolar(self.lockedTrack)
        end
        local relAz = az - centerAz
        if math.abs(relAz) > self.scanAz/2 then goto cont end
        if range > self.maxRange then
            if self.mode==FCRMode.STT then
                local _, lockR = self:GetTrackPolar(self.lockedTrack)
                if math.abs(range-lockR) > self.rangeGateSTT then goto cont end
            else
                goto cont
            end
        end
        -- B-Scope 归一
        local normX = relAz / (self.scanAz/2) -- -1..1
        -- Y: 0=底部( own ), 1=顶部(远)
        local normY
        if self.mode==FCRMode.STT then
            local _, lockR = self:GetTrackPolar(self.lockedTrack)
            -- STT时以 lockR 为中心，显示 ±rangeGate
            normY = (range - (lockR - self.rangeGateSTT)) / (self.rangeGateSTT*2)
        else
            normY = range / self.maxRange
        end
        if normY<0 or normY>1 then goto cont end
        local uiX = normX * screenW * 0.5
        local uiY = -screenH*0.5 + normY*screenH -- 底部是0
        local txt = self.textPool[poolIdx]
        -- 颜色渐隐
        local baseCol = (tr.team==self.vehicle.team) and self.friendlyColor or self.enemyColor
        local alpha = 1 - ageNorm
        alpha = Mathf.Clamp(alpha, self.minAlpha, 1)
        txt.color = Color(baseCol.r, baseCol.g, baseCol.b, baseCol.a*alpha)
        -- 符号：锁定目标用特殊符号
        if self.lockedTrack and self.lockedTrack.vehicleRef==tr.vehicleRef then
            txt.text = self.lockedSymbol
        else
            if tr.type==RadarType.AIR then
                txt.text = (tr.team==self.vehicle.team) and self.friendlyAirSymbol or self.enemyAirSymbol
            elseif tr.type==RadarType.GROUND then
                txt.text = (tr.team==self.vehicle.team) and self.friendlyGroundSymbol or self.enemyGroundSymbol
            elseif tr.type==RadarType.BOAT then
                txt.text = (tr.team==self.vehicle.team) and self.friendlyBoatSymbol or self.enemyBoatSymbol
            else
                txt.text = self.missileSymbol
            end
        end
        txt.rectTransform.localPosition = Vector3(uiX, uiY, 0)
        txt.rectTransform.localScale = Vector3.one
        txt.rectTransform.localRotation = Quaternion.identity
        -- 线：速度矢量线 (可选)
        if self.linePool and lineIdx <= #self.linePool then
            local lineImg = self.linePool[lineIdx]
            local vel = tr.lastVel
            local flatVel = Vector3(vel.x,0,vel.z)
            local velAz = math.atan2(Vector3.Dot(flatVel, Vector3(self.vehicle.transform.forward.z,0,-self.vehicle.transform.forward.x)), Vector3.Dot(flatVel, Vector3(self.vehicle.transform.forward.x,0,self.vehicle.transform.forward.z))) * Mathf.Rad2Deg
            local relVelAz = velAz - az -- 相对目标方位的航向
            -- 长度按速度
            local lineLen = flatVel.magnitude * 0.05 -- 可调系数
            lineLen = Mathf.Clamp(lineLen, 5, 40)
            lineImg.rectTransform.localPosition = Vector3(uiX, uiY, 0)
            lineImg.rectTransform.sizeDelta = Vector2(lineLen, 2)
            lineImg.rectTransform.localEulerAngles = Vector3(0,0, relVelAz)
            lineImg.color = Color(baseCol.r, baseCol.g, baseCol.b, baseCol.a*alpha*0.8)
            lineImg.rectTransform.localScale = Vector3.one
            lineIdx = lineIdx+1
        end
        poolIdx=poolIdx+1
        ::cont::
    end
end
function dvFireControlRadar:DrawBeamIndicator()
    if not self.beamImageRT then return end
    local centerAz = 0
    if self.mode==FCRMode.STT and self.lockedTrack then
        centerAz, _ = self:GetTrackPolar(self.lockedTrack)
    end
    local relBeam = self.beamAz - centerAz
    local normX = relBeam / (self.scanAz/2)
    local screenW = self.rtScreen.sizeDelta.x
    local uiX = normX * screenW * 0.5
    -- 固定在顶部或按需求
    self.beamImageRT.localPosition = Vector3(uiX, self.rtScreen.sizeDelta.y*0.5 -2, 0)
    self.beamImageRT.localScale = Vector3.one
end
function dvFireControlRadar:DrawLockImage()
    if not self.lockImageRT then return end
    if not self.lockedTrack or self.mode~=FCRMode.STT then
        self.lockImageRT.localScale = Vector3.zero
        return
    end
    local az, range = self:GetTrackPolar(self.lockedTrack)
    local centerAz = az
    -- 若 STT 扫描中心就是目标，relAz=0, X=0 中心，若要显示真实位置，用B-Scope映射
    -- 这里按之前的映射算UI坐标
    local screenW = self.rtScreen.sizeDelta.x
    local screenH = self.rtScreen.sizeDelta.y
    local relAz = 0 -- STT 中心
    local normX = relAz / (self.scanAz/2)
    local normY
    if self.mode==FCRMode.STT then
        normY = 0.5 -- 锁定时固定在中部或按距离门中心
        -- 也可以用 range 映射
        local _, lockR = self:GetTrackPolar(self.lockedTrack)
        normY = 0.5 -- 简化居中
        -- 若想要距离对应：normY = 0.5 (固定)
    else
        normY = range / self.maxRange
    end
    local uiX = normX * screenW * 0.5
    local uiY = -screenH*0.5 + normY*screenH
    self.lockImageRT.localPosition = Vector3(uiX, uiY, 0)
    self.lockImageRT.localScale = Vector3.one
    -- 可加闪烁
    local blink = (Mathf.Repeat(Time.time*2,1)>0.5) and 1 or 0.6
    local img = self.lockImageRT.GetComponent(Image)
    if img then
        local c = img.color
        img.color = Color(c.r,c.g,c.b, blink)
    end
end
function dvFireControlRadar:DrawInfoTexts()
    if self.rangeText then
        local modeStr = ({"RWS","TWS","STT","ACM"})[self.mode+1]
        self.rangeText.text = string.format("%s %dm Az%.0f Beam%.1f", modeStr, self.maxRange, self.scanAz, self.beamAz)
    end
    if self.statusText then
        if self.lockedTrack then
            local az, range = self:GetTrackPolar(self.lockedTrack)
            local age = Time.time - self.lockedTrack.lastSeen
            self.statusText.text = string.format("LOCK %s %.0fm Az%.1f Age%.1fs", self.lockedTrack.vehicleRef.name, range, az, age)
        else
            self.statusText.text = string.format("SEARCH Tracks:%d OwnMis:%d", #self.tracks, #self.ownMissiles)
        end
    end
end
