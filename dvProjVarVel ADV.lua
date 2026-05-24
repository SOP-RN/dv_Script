behaviour("dvProjVarVel")

function dvProjVarVel:Start()
    self.projectile = self.targets.projectile.GetComponent(Projectile)

    if self.projectile == nil then
        self:DestroyScript()
        return
    end

    self.startTime = Time.time
    self.dataContainer = self.gameObject.GetComponent(DataContainer)

    -- acceleration system
    self.timeToReachMaxSpeed = self.dataContainer.GetFloat("TimeToReachMaxSpeed")
    self.accelerationCurve = self.dataContainer.GetAnimationCurve("AccelerationCurve")
    self.minAcceleration = self.dataContainer.GetFloat("MinAcceleration")
    self.maxAcceleration = self.dataContainer.GetFloat("MaxAcceleration")

    -- guidance
    self.minAngle = self.dataContainer.GetFloat("MinAngle")
    self.maxAngle = self.dataContainer.GetFloat("MaxAngle")

    self.smoothingFactor = self.dataContainer.GetFloat("SmoothingFactor")

    -- state
    self.syncCount = 2
    self.updateCounter = 0
    self.syncing = true

    self.delayStartTime = nil

    self.lastTarget = nil
    self.hasLastTarget = false
    self.onceLostTarget = false
    self.isReady = true
end

function dvProjVarVel:Update()

    -- inherit velocity phase
    if self.syncing and self.updateCounter < self.syncCount then
        if self.projectile.killCredit then
            self.projectile.velocity = self.projectile.killCredit.velocity
        end

        self.updateCounter = self.updateCounter + 1

        if self.updateCounter >= self.syncCount then
            self.syncing = false
            self.delayStartTime = Time.time
        end

        return
    end

    -- short delay phase
    if self.delayStartTime and Time.time - self.delayStartTime < 0.3 then
        local downward = Vector3.down * 30 * Time.fixedDeltaTime
        self.projectile.velocity =
            self.projectile.velocity +
            self.gameObject.transform.TransformDirection(downward)
        return
    end

    -- lifecycle fail-safe
    if self.projectile.distanceTravelled == self.lastDistanceTravelled then
        if not self.onceDestroyScript then
            self:DestroyScript()
        end
        return
    end
    self.lastDistanceTravelled = self.projectile.distanceTravelled

    self:TraceProjectileUpdate()

    if Time.time - self.startTime > 25 then
        self.projectile.Stop(false)
    end
end

function dvProjVarVel:TraceProjectileUpdate()

    if not self.projectile.currentTarget then
        if self.hasLastTarget then
            self.hasLastTarget = false
            self.script.StartCoroutine("StartFlareCoolDown")
        end
        return
    end

    if not self.hasLastTarget then
        self.hasLastTarget = true
        self.lastTarget = self.projectile.currentTarget
    end

    local t = Time.time - (self.delayStartTime or self.startTime)

    -- acceleration (ONLY speed source)
    local curve = self:EvaluateAcceleration(t)
    local acceleration = curve * Time.deltaTime

    local dir = self.projectile.velocity.normalized

    self.projectile.velocity =
        self.projectile.velocity +
        dir * acceleration

    -- steering (direction only)
    local target = self.projectile.currentTarget
    local toTarget = (target.transform.position - self.gameObject.transform.position).normalized

    local currentSpeed = self.projectile.velocity.magnitude

    local smoothDir = Vector3.Slerp(
        self.projectile.velocity.normalized,
        toTarget,
        Time.deltaTime * self.smoothingFactor
    )

    self.projectile.velocity = smoothDir * currentSpeed

    -- angle cutoff
    local angle = Vector3.Angle(self.projectile.velocity.normalized, toTarget)

    if angle > self.maxAngle and t > 1.5 then
        self.projectile.Stop(false)
        return
    end
end

function dvProjVarVel:EvaluateAcceleration(currentTime)
    local normalizedTime =
        Mathf.Clamp01(currentTime / self.timeToReachMaxSpeed)

    local curveTime =
        normalizedTime * self.accelerationCurve.length

    local value = self.accelerationCurve.Evaluate(curveTime)

    return Mathf.Lerp(
        self.minAcceleration,
        self.maxAcceleration,
        value
    )
end

function dvProjVarVel:StartFlareCoolDown()
    self.isReady = false
    coroutine.yield(WaitForSeconds(0.2))

    if self:CheckAngleRange() then
        self.projectile.SetTrackerTarget(self.lastTarget)
        self.onceLostTarget = true
        self.isReady = true
    end
end

function dvProjVarVel:CheckAngleRange()
    local target = self.projectile.currentTarget
    if not target then return false end

    local dir =
        (target.transform.position - self.gameObject.transform.position)

    local angle = Vector3.Angle(self.gameObject.transform.forward, dir)

    return angle >= self.minAngle and angle <= self.maxAngle
end

function dvProjVarVel:DestroyScript()
    self.onceDestroyScript = true
    GameObject.Destroy(self.script)
end