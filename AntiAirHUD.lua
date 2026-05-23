behaviour("AntiAirHUD")

function AntiAirHUD:Start()

    self.dataContainer = self.gameObject.GetComponent(DataContainer)

    self.vehicle = self.targets.vehicleObject.GetComponent(Vehicle)

    self.canvas = self.targets.canvas:GetComponent(RectTransform)

    self.targetObject = self.targets.targetObject:GetComponent(RectTransform)
    self.infoObject = self.targets.infoObject:GetComponent(RectTransform)
    self.lineImage = self.targets.lineImage:GetComponent(RectTransform)

    self.targetName = self.infoObject:Find("Name").gameObject.GetComponent(Text)
    self.targetDistance = self.infoObject:Find("Distance").gameObject.GetComponent(Text)
    self.targetVelocity = self.infoObject:Find("Velocity").gameObject.GetComponent(Text)

    self.speed = tonumber(self.dataContainer.GetString("calibrationSpeed")) or 900
    self.gravityMultiplier = tonumber(self.dataContainer.GetString("calibrationGravity")) or 1

    self.target = nil
    self.targetTransform = nil

    self.targetUpdateTimer = 0
    self.targetUpdateInterval = 1

    self.uiUpdateInterval = 0.03
    self.uiUpdateTimer = 0

    self.maxLockAngle = 25

    self.hiddenPos = Vector2(99999, 99999)

    self.potentialTarget = {}

    self.teams = {
        [0] = Team.Blue,
        [1] = Team.Red,
        [-1] = Team.Neutral
    }

    GameEvents.onVehicleSpawn.AddListener(self, "UpdateTargets")
    GameEvents.onVehicleDestroyed.AddListener(self, "UpdateTargets")

    self:UpdateTargets()
    self:HideUI()
end

function AntiAirHUD:Update()

    if not self.vehicle then
        return
    end

    local cam = PlayerCamera.activeCamera

    if not cam then
        self:HideUI()
        return
    end

    self.targetUpdateTimer = self.targetUpdateTimer + Time.deltaTime

    if self.targetUpdateTimer >= self.targetUpdateInterval then
        self.targetUpdateTimer = 0
        self:UpdateTargets()
    end

    if Input.GetKeyDown(KeyCode.G) and self.vehicle.playerIsInside then
        self:LockTarget()
    end

    if not self.vehicle.playerIsInside then
        self:HideUI()
        return
    end

    if not self.target then
        self:HideUI()
        return
    end

    if self.target.isDead then
        self.target = nil
        self.targetTransform = nil
        self:HideUI()
        return
    end

    self.uiUpdateTimer = self.uiUpdateTimer + Time.deltaTime

    if self.uiUpdateTimer >= self.uiUpdateInterval then
        self.uiUpdateTimer = 0
        self:UpdateHUD()
    end
end

function AntiAirHUD:LockTarget()

    local cam = PlayerCamera.activeCamera

    if not cam then
        return
    end

    local cameraTransform = cam.transform

    local lowestAngle = self.maxLockAngle
    local bestTarget = nil

    for i, vehicle in pairs(self.potentialTarget) do

        if vehicle and not vehicle.isDead then

            local dir = vehicle.transform.position - cameraTransform.position

            local angle = Vector3.Angle(dir, cameraTransform.forward)

            if angle < lowestAngle then

                if vehicle.team ~= Player.team then

                    if self:IsTargetVisible(vehicle) then

                        lowestAngle = angle
                        bestTarget = vehicle

                    end
                end
            end
        end
    end

    if bestTarget then

        self.target = bestTarget
        self.targetTransform = bestTarget.transform

        self.targetName.text = bestTarget.name

    else

        self.target = nil
        self.targetTransform = nil

    end
end

function AntiAirHUD:UpdateHUD()

    local cam = PlayerCamera.activeCamera

    if not cam then
        self:HideUI()
        return
    end

    if not self.target or not self.targetTransform then
        self:HideUI()
        return
    end

    local tgtPos = self.targetTransform.position
    local tgtVel = self.target.rigidbody.velocity

    local distance = Vector3.Distance(
        self.vehicle.transform.position,
        tgtPos
    )

    local aimPoint = self:CalculateAimPoint(
        tgtPos,
        tgtVel,
        distance
    )

    local targetScreen = self:WorldToCanvasPosition(tgtPos)
    local aimScreen = self:WorldToCanvasPosition(aimPoint)

    if not targetScreen or not aimScreen then
        self:HideUI()
        return
    end

    self.infoObject.anchoredPosition = targetScreen
    self.targetObject.anchoredPosition = aimScreen

    local scale = self:CalculateScale(distance)

    self.targetObject.localScale = Vector3(scale, scale, 1)

    self.targetDistance.text =
        string.format("%.0f m", distance)

    self.targetVelocity.text =
        string.format("%.0f m/s", tgtVel.magnitude)

    self:UpdateLine(targetScreen, aimScreen)

end

function AntiAirHUD:UpdateLine(startPos, endPos)

    local dir = endPos - startPos

    local distance = dir.magnitude

    if distance < 1 then

        self.lineImage.anchoredPosition = self.hiddenPos
        return

    end

    local midpoint = (startPos + endPos) * 0.5

    self.lineImage.anchoredPosition = midpoint

    local size = self.lineImage.sizeDelta
    size.x = distance
    self.lineImage.sizeDelta = size

    local angle =
        math.atan2(dir.y, dir.x) * Mathf.Rad2Deg

    self.lineImage.localEulerAngles =
        Vector3(0, 0, angle)

end

function AntiAirHUD:CalculateAimPoint(
    tgtPos,
    targetVelocity,
    distance
)

    local timeToReach = distance / self.speed

    local drop =
        self:CalculateDrop(
            timeToReach,
            self.gravityMultiplier
        )

    local predictedPos =
        tgtPos + targetVelocity * timeToReach

    predictedPos =
        Vector3(
            predictedPos.x,
            predictedPos.y + drop,
            predictedPos.z
        )

    return predictedPos
end

function AntiAirHUD:CalculateDrop(time, gravityMultiplier)

    return
        0.5 *
        math.abs(Physics.gravity.y) *
        gravityMultiplier *
        time *
        time

end

function AntiAirHUD:CalculateScale(distance)

    local minScale = 0.5
    local maxScale = 1.0
    local maxDistance = 1500

    local scale =
        maxScale -
        (distance / maxDistance) *
        (maxScale - minScale)

    return self:Clamp(
        scale,
        minScale,
        maxScale
    )
end

function AntiAirHUD:Clamp(value, min, max)

    return math.max(
        min,
        math.min(max, value)
    )

end

function AntiAirHUD:IsTargetVisible(vehicle)

    local cam = PlayerCamera.activeCamera

    if not cam then
        return false
    end

    local camPos = cam.transform.position

    local direction =
        vehicle.transform.position - camPos

    local ray =
        Ray(camPos, direction.normalized)

    local hit =
        Physics.Raycast(
            ray,
            direction.magnitude,
            RaycastTarget.Default
        )

    if hit then
        return hit.transform == vehicle.transform
    end

    return true

end

function AntiAirHUD:WorldToCanvasPosition(worldPos)

    local cam = PlayerCamera.activeCamera

    if not cam then
        return nil
    end

    local screenPos =
        cam.WorldToScreenPoint(worldPos)

    if screenPos.z < 0 then
        return nil
    end

    local x =
        screenPos.x - (Screen.width * 0.5)

    local y =
        screenPos.y - (Screen.height * 0.5)

    return Vector2(x, y)

end

function AntiAirHUD:HideUI()

    self.infoObject.anchoredPosition =
        self.hiddenPos

    self.targetObject.anchoredPosition =
        self.hiddenPos

    self.lineImage.anchoredPosition =
        self.hiddenPos

end

function AntiAirHUD:UpdateTargets()

    local result = {}

    local playerTeam = Player.team

    for i, vehicle in pairs(ActorManager.vehicles) do

        if vehicle then

            if not vehicle.isTurret then

                if vehicle.team ~= playerTeam then

                    if not vehicle.isDead then

                        result[#result + 1] = vehicle

                    end
                end
            end
        end
    end

    self.potentialTarget = result

end
