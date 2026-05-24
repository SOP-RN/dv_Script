behaviour("GPTProjectile")

function GPTProjectile:Start()
    self.projectile = self.targets.projectile.GetComponent(Projectile)

    if self.projectile == nil then
        self:DestroyScript()
        return
    end

    self.startTime = Time.time
    self.dataContainer = self.gameObject.GetComponent(DataContainer)

    self.inheritVelocity = self.dataContainer.GetBool("InheritVelocity")
    self.timeToReachMaxSpeed = self.dataContainer.GetFloat("TimeToReachMaxSpeed")
    self.flareDuration = self.dataContainer.GetFloat("FlareDuration")
    self.minAcceleration = self.dataContainer.GetFloat("MinAcceleration")
    self.maxAcceleration = self.dataContainer.GetFloat("MaxAcceleration")
    self.minAngle = self.dataContainer.GetFloat("MinAngle")
    self.maxAngle = self.dataContainer.GetFloat("MaxAngle")
    self.accelerationCurve = self.dataContainer.GetAnimationCurve("AccelerationCurve")
    self.smoothingFactor = self.dataContainer.GetFloat("SmoothingFactor")
    self.steeringCostFactor = self.dataContainer.GetFloat("SteeringCostFactor")
    self.gravityFactor = self.dataContainer.GetFloat("GravityFactor")
    self.climbFactor = self.dataContainer.GetFloat("ClimbFactor")

    self.lastTarget = nil
    self.isReady = true
    self.hasLastTarget = false
    self.onceLostTarget = false
    self.lastDistanceTravelled = 0
    self.cumulativeSpeedLoss = 0
end

function GPTProjectile:Update()
    if self.projectile and self.lastDistanceTravelled ~= self.projectile.distanceTravelled then
        self.lastDistanceTravelled = self.projectile.distanceTravelled
        self:TraceProjectileUpdate()
    else
        if not self.onceDestroyScript then
            self:DestroyScript()
        end
    end

    -- Self-destruct after activeTime seconds
    if Time.time - self.startTime > 25 then
        self.projectile.Stop(false)
    end
end

function GPTProjectile:StartFlareCoolDown()
    self.isReady = false
    coroutine.yield(WaitForSeconds(self.flareDuration))
    if self:CheckAngleRange() then
        self.projectile.SetTrackerTarget(self.lastTarget)
        self.onceLostTarget = true
        self.isReady = true
    end
end

function GPTProjectile:TraceProjectileUpdate()
    if not self.isReady then
        return
    end

    if self.projectile.isTrackingTarget or self.onceLostTarget then
        if not self.hasLastTarget then
            self.hasLastTarget = true
            self.lastTarget = self.projectile.currentTarget
        end

        local currentTime = Time.time - self.startTime
        local baseSpeed = self:EvaluateAcceleration(currentTime)
        local verticalSpeed = self.gravityFactor * Time.deltaTime

        local target = self.projectile.currentTarget
        local direction = target.transform.position - self.gameObject.transform.position
        local currentDirection = self.projectile.velocity.normalized

        local angle = Vector3.Angle(currentDirection, direction)

        -- Adjust speed based on turning and accumulate
        local speedLossFactor = angle * (baseSpeed / 400) * self.steeringCostFactor
        self.cumulativeSpeedLoss = self.cumulativeSpeedLoss + speedLossFactor * Time.deltaTime

        -- Apply upward force if target is far enough
        local climbEffect = Vector3.zero
        if currentTime <= 2.5 and currentTime >= 0.3 and direction.magnitude >= 1900 then
            climbEffect = Vector3.up * self.climbFactor * Time.deltaTime
        end

        -- Gravity impact on speed only
        local heightDifference = target.transform.position.y - self.gameObject.transform.position.y
        if heightDifference > 0 then  
            self.cumulativeSpeedLoss = self.cumulativeSpeedLoss - verticalSpeed
        else
            self.cumulativeSpeedLoss = self.cumulativeSpeedLoss + verticalSpeed
        end

        -- Calculate final speed and apply minimum speed limit
        local speed = math.max(baseSpeed - self.cumulativeSpeedLoss, 100)

        -- Smooth transition for smoothingMultiplier
        local smoothingMultiplier = Mathf.Clamp01((1200 - baseSpeed) / 1000) * 0.5 + 0.5

        local smoothDirection = Vector3.Slerp(currentDirection, Vector3.Normalize(direction), Time.deltaTime * self.smoothingFactor * smoothingMultiplier)

        -- Check if the angle exceeds the max angle
        if angle > self.maxAngle and currentTime >= 1.5 then
            self.projectile.Stop(false)
            return
        end

        local velocity = smoothDirection * speed + climbEffect

        self.projectile.velocity = velocity
    else
        if self.hasLastTarget then
            self.hasLastTarget = false
            self.script.StartCoroutine("StartFlareCoolDown")
        end
    end
end

function GPTProjectile:EvaluateAcceleration(currentTime)
    local normalizedTime = Mathf.Clamp01(currentTime / self.timeToReachMaxSpeed)
    local curveTime = normalizedTime * self.accelerationCurve.length

    local speed = self.accelerationCurve.Evaluate(curveTime)

    speed = Mathf.Lerp(self.minAcceleration, self.maxAcceleration, speed)

    return speed
end

function GPTProjectile:CheckAngleRange()
    local target = self.projectile.currentTarget
    local direction = target.transform.position - self.gameObject.transform.position

    local angle = Vector3.Angle(self.gameObject.transform.forward, direction)

    return angle >= self.minAngle and angle <= self.maxAngle
end

function GPTProjectile:DestroyScript()
    self.onceDestroyScript = true
    GameObject.Destroy(self.script)
end
