behaviour("dvProjVarVel")

function dvProjVarVel:Start()
    self.projectile = self.targets.projectile.GetComponent(Projectile)

    if self.projectile == nil then
        self:DestroyScript()
        return
    end

    self.startTime = Time.time
    self.dataContainer = self.gameObject.GetComponent(DataContainer)

    self.timeToReachMaxSpeed = self.dataContainer.GetFloat("TimeToReachMaxSpeed")
    self.accelerationCurve = self.dataContainer.GetAnimationCurve("AccelerationCurve")
    self.minAcceleration = self.dataContainer.GetFloat("MinAcceleration")
    self.maxAcceleration = self.dataContainer.GetFloat("MaxAcceleration")

    self.syncCount = 10
    self.updateCounter = 0
    self.syncing = true

    self.accumulatedSpeed = 0
end
function dvProjVarVel:Update()

    -- 1. 继承阶段（只做初始化速度）
    if self.syncing and self.updateCounter < self.syncCount then
        if self.projectile.killCredit then
            self.projectile.velocity = self.projectile.killCredit.velocity
        end

        self.updateCounter = self.updateCounter + 1

        if self.updateCounter >= self.syncCount then
            self.syncing = false
            self.accumulatedSpeed = self.projectile.velocity.magnitude
        end

        return
    end

    -- 2. 时间
    local t = Time.time - self.startTime

    -- 3. 曲线加速度（关键变化）
    local curve = self:EvaluateAcceleration(t)

    local acceleration =
        Vector3.Normalize(self.projectile.velocity) * curve * Time.deltaTime

    -- 4. 速度累加（核心修复点）
    self.projectile.velocity = self.projectile.velocity + acceleration

    -- 5. 方向修正（只改方向，不重置速度大小）
    if self.projectile.currentTarget then
        local dir =
            (self.projectile.currentTarget.transform.position
            - self.gameObject.transform.position).normalized

        local speed = self.projectile.velocity.magnitude
        self.projectile.velocity = dir * speed
    end

    -- 6. 生命周期
    if Time.time - self.startTime > 25 then
        self.projectile.Stop(false)
    end
end

function dvProjVarVel:EvaluateAcceleration(currentTime)
    local normalizedTime = Mathf.Clamp01(currentTime / self.timeToReachMaxSpeed)
    local curveTime = normalizedTime * self.accelerationCurve.length

    local speed = self.accelerationCurve.Evaluate(curveTime)
    speed = Mathf.Lerp(self.minAcceleration, self.maxAcceleration, speed)

    return speed
end

function dvProjVarVel:DestroyScript()
    GameObject.Destroy(self.script)
end