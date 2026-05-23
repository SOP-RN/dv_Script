behaviour("ReSpecialProjectile")

function ReSpecialProjectile:Start()
	self.projectile = self.targets.projectile.GetComponent(Projectile)
	
	if self.projectile ~= nil and not self.projectile.isTargetSeekingMissileProjectile then
		self:DestroyScript()
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
	
	self.lastTarget = nil
	self.isReady = true
	self.hasLastTarget = false
	self.onceLostTarget = false
	
	self.lastDistanceTravelled = 0

    self.smoothingFactor = self.dataContainer.GetFloat("SmoothingFactor")
end

function ReSpecialProjectile:Update()
	if self.projectile ~= nil and self.lastDistanceTravelled ~= self.projectile.distanceTravelled then
		self.lastDistanceTravelled = self.projectile.distanceTravelled
		self:TraceProjectileeUpdate()
	else
		if not self.onceDestroyScript then
			self:DestroyScript()
		end
	end
end

function ReSpecialProjectile:StartFlareCoolDown()
	self.isReady = false
	coroutine.yield(WaitForSeconds(self.flareDuration))
	if self:CheckAngleRange() then
        self.projectile.SetTrackerTarget(self.lastTarget)
        self.onceLostTarget = true
		self.isReady = true
    end
end

function ReSpecialProjectile:TraceProjectileeUpdate()
    if not self.isReady then
        return
    end

    if self.projectile.isTrackingTarget or self.onceLostTarget then
        if not self.hasLastTarget then
            self.hasLastTarget = true
            self.lastTarget = self.projectile.currentTarget
        end

        local currentTime = Time.time - self.startTime
        local speed = self:EvaluateAcceleration(currentTime)

        local target = self.projectile.currentTarget
        local direction = target.transform.position - self.gameObject.transform.position

        local currentDirection = self.projectile.velocity.normalized
        local smoothDirection = Vector3.Slerp(currentDirection, Vector3.Normalize(direction), Time.deltaTime * self.smoothingFactor)
        local velocity = Vector3.zero

        if self.inheritVelocity then
            velocity = self.projectile.killCredit.velocity + smoothDirection * speed
        else
            velocity = smoothDirection * speed
        end

        self.projectile.velocity = velocity
    else
        if self.hasLastTarget then
            self.hasLastTarget = false
            self.script.StartCoroutine("StartFlareCoolDown")
        end
    end
end

function ReSpecialProjectile:EvaluateAcceleration(currentTime)
    local normalizedTime = Mathf.Clamp01(currentTime / self.timeToReachMaxSpeed)
    local curveTime = normalizedTime * self.accelerationCurve.length

    local speed = self.accelerationCurve.Evaluate(curveTime)

    speed = Mathf.Lerp(self.minAcceleration, self.maxAcceleration, speed)

    return speed
end

function ReSpecialProjectile:CheckAngleRange()
    local target = self.projectile.currentTarget
    local direction = target.transform.position - self.gameObject.transform.position

    local angle = Vector3.Angle(self.gameObject.transform.forward, direction)

    return angle >= self.minAngle and angle <= self.maxAngle
end

function ReSpecialProjectile:DestroyScript()
	self.onceDestroyScript = true
    GameObject.Destroy(self.script)
end