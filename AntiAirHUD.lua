behaviour("AntiAirHUD")

function AntiAirHUD:Start()
    self.dataContainer = self.gameObject.GetComponent(DataContainer)
    self.vehicle = self.targets.vehicleObject.GetComponent(Vehicle)
    self.target = nil
    self.targetTransform = nil
    self.compensatedPos = nil
    self.targetObject = self.targets.targetObject.transform
    self.infoObject = self.targets.infoObject.transform
    self.targetName = self.infoObject:Find("Name").gameObject.GetComponent(Text)
    self.targetDistance = self.infoObject:Find("Distance").gameObject.GetComponent(Text)
    self.targetVelocity = self.infoObject:Find("Velocity").gameObject.GetComponent(Text)
    self.lineImage = self.targets.lineImage:GetComponent(RectTransform)
    self.delay = 0

    self.canvasObject = self.targets.canvas

    -- Assume only one weapon calibration
    self.speed = tonumber(self.dataContainer.GetString("calibrationSpeed"))
    self.gravity = tonumber(self.dataContainer.GetString("calibrationGravity"))

    self.potentialTarget = {}
    self.teams = { [0] = Team.Blue, [1] = Team.Red, [-1] = Team.Neutral }

    self.out = Vector3(5000, 5000, 0)

    GameEvents.onVehicleSpawn.AddListener(self, "UpdateTargets")
    GameEvents.onVehicleDestroyed.AddListener(self, "UpdateTargets")
    self:UpdateTargets()
end

function AntiAirHUD:FixedUpdate()
    if #self.potentialTarget == 0 then
        self:UpdateTargets()
    end

    self.delay = self.delay + Time.fixedDeltaTime

    if Input.GetKeyDown(KeyCode.G) and self.vehicle.playerIsInside then
        self:LockTarget()
    end

    if self.target and self.vehicle.playerIsInside then
        self:UpdateHUD()
    else
        self:HideUI()
    end
end

function AntiAirHUD:LockTarget()
    local lowestAngle = 25
    local targetVehicle = nil
    local cameraTransform = PlayerCamera.activeCamera.transform

    for i, vehicle in pairs(self.potentialTarget) do
        local vector = vehicle.transform.position - cameraTransform.position
        local angle = Vector3.Angle(vector, cameraTransform.forward)
        
        if angle < lowestAngle and self.teams[vehicle.team] ~= Player.team and self:IsTargetVisible(vehicle) then
            lowestAngle = angle
            targetVehicle = vehicle
        end
    end

    if targetVehicle then
        self.target = targetVehicle
        self.targetTransform = self.target.transform
        self.targetName.text = self.target.name
    else
        self.target = nil
        self.targetTransform = nil
    end
end

function AntiAirHUD:UpdateHUD()
    if not self.target or self.target.isDead then
        self:HideUI()
        return
    end

    if self.delay >= Time.fixedDeltaTime then
        self.delay = self.delay - Time.fixedDeltaTime

        local tgtPos = self.targetTransform.position
        local distance = Vector3.Distance(self.vehicle.transform.position, tgtPos)
        local altitude = tgtPos.y
        local targetVelocity = self.target.rigidbody.velocity

        self.targetDistance.text = string.format("%.0f m", distance)
        self.targetVelocity.text = string.format("%.0f m/s", targetVelocity.magnitude)

        local aimVector = self:CalculateAimPoint(tgtPos, targetVelocity, distance)

        local infoObjectPos = self:GetScreenPoint(tgtPos)
        self.infoObject.position = infoObjectPos

        local pos = self:GetScreenPoint(aimVector)
        self.targetObject.position = pos

        local newScale = self:CalculateScale(distance)
        self.targetObject.localScale = Vector3(newScale, newScale, 1)
    end
end

function AntiAirHUD:CalculateAimPoint(tgtPos, targetVelocity, distance)
    local timeToReach = distance / self.speed
    local drop = self:CalculateDrop(timeToReach, self.gravity)

    local aimVector = tgtPos
    aimVector.y = tgtPos.y - drop

    if targetVelocity ~= Vector3.zero then
        aimVector = aimVector + targetVelocity * timeToReach
    end

    return aimVector
end

function AntiAirHUD:CalculateScale(distance)
    local minScale = 0.5
    local maxScale = 1.0
    local maxDistance = 1000

    local scale = maxScale - (distance / maxDistance) * (maxScale - minScale)
    return self:Clamp(scale, minScale, maxScale)
end

function AntiAirHUD:Clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

function AntiAirHUD:IsTargetVisible(vehicle)
    local cameraTransform = PlayerCamera.activeCamera.transform
    local direction = vehicle.transform.position - cameraTransform.position
    local ray = Ray(cameraTransform.position, direction)
    local hit = Physics.Raycast(ray, direction.magnitude, RaycastTarget.Default)
    return hit == nil or hit.transform == vehicle.transform
end

function AntiAirHUD:GetScreenPoint(point)
    local pos = PlayerCamera.activeCamera.WorldToScreenPoint(point)

    if pos.z < 0 then
        return self.out
    end

    pos.z = 0
    return pos
end

function AntiAirHUD:CalculateDrop(time, gravity)
    return 0.5 * Physics.gravity.y * gravity * math.pow(time, 2)
end

function AntiAirHUD:HideUI()
    self.infoObject.localPosition = self.out
    self.targetObject.localPosition = self.out
    self.lineImage.localPosition = self.out
end

function AntiAirHUD:UpdateTargets()
    local result = {}
    local playerTeam = Player.team  -- Get the player's team

    for i, vehicle in pairs(ActorManager.vehicles) do
        if not vehicle.isTurret and vehicle.team ~= playerTeam then
            result[#result + 1] = vehicle
        end
    end

    self.potentialTarget = result
end
