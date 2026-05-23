behaviour("AtoAHUD")

function AtoAHUD:Start()

    self.dataContainer =
        self.gameObject.GetComponent(DataContainer)

    self.vehicle =
        self.targets.vehicleObject:GetComponent(Vehicle)

    self.canvasObject =
        self.targets.canvas

    self.targetObject =
        self.targets.targetObject:GetComponent(RectTransform)

    self.infoObject =
        self.targets.infoObject:GetComponent(RectTransform)

    self.lineImage =
        self.targets.lineImage:GetComponent(RectTransform)

    self.targetIndicatorObject =
        self.targets.targetIndicatorObject

    self.targetIndicatorHide =
        self.targets.targetIndicatorHide

    self.Gunobj =
        self.targets.GunObj

    self.targetName =
        self.infoObject:Find("Name")
            .gameObject:GetComponent(Text)

    self.targetDistance =
        self.infoObject:Find("Distance")
            .gameObject:GetComponent(Text)

    self.targetVelocity =
        self.infoObject:Find("Velocity")
            .gameObject:GetComponent(Text)

    self.speed =
        tonumber(
            self.dataContainer.GetString(
                "calibrationSpeed"
            )
        ) or 900

    self.gravity =
        tonumber(
            self.dataContainer.GetString(
                "calibrationGravity"
            )
        ) or 1

    self.target = nil
    self.targetTransform = nil

    self.hiddenPos = Vector2(99999, 99999)

    self.targetUpdateTimer = 0
    self.targetUpdateInterval = 1

    self.uiUpdateTimer = 0
    self.uiUpdateInterval = 0.03

    self.maxLockAngle = 10

    self.potentialTarget = {}

    self.identityRotation = Quaternion.identity

    self.insideTimer = 0

    self.canvasVisible = false

    GameEvents.onVehicleSpawn.AddListener(
        self,
        "UpdateTargets"
    )

    GameEvents.onVehicleDestroyed.AddListener(
        self,
        "UpdateTargets"
    )

    self:UpdateTargets()

    self:HideUI()

end

function AtoAHUD:Update()

    self.targetUpdateTimer =
        self.targetUpdateTimer +
        Time.deltaTime

    if self.targetUpdateTimer >=
        self.targetUpdateInterval
    then
        self.targetUpdateTimer = 0
        self:UpdateTargets()
    end

    -- ONLY gate: vehicle state (no camera dependency)
    if self.vehicle.playerIsInside then
        self.insideTimer = 0
    else
        self.insideTimer =
            self.insideTimer + Time.deltaTime

        if self.insideTimer > 0.15 then
            self:HideUI()
            self:ResetIndicators()
            return
        end
    end

    if Input.GetKeyDown(KeyCode.G) then
        self:LockTarget()
    end

    if not self.vehicle.playerIsInside then
        self:ResetIndicators()
        return
    end

    if not self.target or self.target.isDead then
        self:HideUI()
        self:ResetIndicators()
        return
    end

    self.uiUpdateTimer =
        self.uiUpdateTimer +
        Time.deltaTime

    if self.uiUpdateTimer <
        self.uiUpdateInterval
    then
        return
    end

    self.uiUpdateTimer = 0

    self:UpdateHUD()

end

function AtoAHUD:LockTarget()

    local cam = PlayerCamera.activeCamera
    if not cam then
        return
    end

    local cameraTransform =
        cam.transform

    local bestTarget = nil
    local lowestAngle =
        self.maxLockAngle

    for i, vehicle in
        pairs(self.potentialTarget)
    do

        if vehicle and
           not vehicle.isDead
        then

            if vehicle.team ~= Player.team then

                local dir =
                    vehicle.transform.position -
                    cameraTransform.position

                local angle =
                    Vector3.Angle(
                        dir,
                        cameraTransform.forward
                    )

                if angle < lowestAngle then

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
        self.targetTransform =
            bestTarget.transform

        self.targetName.text =
            bestTarget.name

        self:SetHUDVisible(true)

    else

        self.target = nil
        self.targetTransform = nil

        self:SetHUDVisible(false)

    end
end

function AtoAHUD:UpdateHUD()

    if not self.target or
       not self.targetTransform
    then
        self:HideUI()
        return
    end

    local tgtPos =
        self.targetTransform.position

    local tgtVel =
        self.target.rigidbody.velocity

    local distance =
        Vector3.Distance(
            self.vehicle.transform.position,
            tgtPos
        )

    local aimPoint =
        self:CalculateAimPoint(
            tgtPos,
            tgtVel,
            distance
        )

    local infoPos =
        self:WorldToCanvasPosition(
            tgtPos
        )

    local aimPos =
        self:WorldToCanvasPosition(
            aimPoint
        )

    if not infoPos or not aimPos then
        return
    end

    self.infoObject.anchoredPosition =
        infoPos

    self.targetObject.anchoredPosition =
        aimPos

    local scale =
        self:CalculateScale(distance)

    self.targetObject.localScale =
        Vector3(scale, scale, 1)

    self.targetDistance.text =
        string.format("%.0f m", distance)

    self.targetVelocity.text =
        string.format(
            "%.0f m/s",
            tgtVel.magnitude
        )

    self:UpdateLine(
        infoPos,
        aimPos
    )

    self:RotateIndicators(tgtPos)

end

function AtoAHUD:CalculateAimPoint(
    tgtPos,
    targetVelocity,
    distance
)

    local timeToReach =
        distance / self.speed

    local drop =
        self:CalculateDrop(
            timeToReach,
            self.gravity
        )

    local predicted =
        tgtPos +
        (targetVelocity * timeToReach)

    return Vector3(
        predicted.x,
        predicted.y + drop,
        predicted.z
    )

end

function AtoAHUD:CalculateDrop(
    time,
    gravity
)

    return
        0.5 *
        math.abs(Physics.gravity.y) *
        gravity *
        time *
        time

end

function AtoAHUD:CalculateScale(distance)

    local minScale = 0.5
    local maxScale = 1.0
    local maxDistance = 1000

    local t =
        distance / maxDistance

    local scale =
        maxScale -
        t * (maxScale - minScale)

    return self:Clamp(
        scale,
        minScale,
        maxScale
    )

end

function AtoAHUD:Clamp(v, a, b)

    return math.max(
        a,
        math.min(b, v)
    )

end

function AtoAHUD:IsTargetVisible(vehicle)

    local cam = PlayerCamera.activeCamera
    if not cam then
        return false
    end

    local camPos =
        cam.transform.position

    local dir =
        vehicle.transform.position -
        camPos

    local ray =
        Ray(
            camPos,
            dir.normalized
        )

    local hit =
        Physics.Raycast(
            ray,
            dir.magnitude,
            RaycastTarget.Default
        )

    if hit then
        return hit.transform ==
            vehicle.transform
    end

    return true

end

function AtoAHUD:WorldToCanvasPosition(worldPos)

    local cam =
        PlayerCamera.activeCamera

    if not cam then
        return nil
    end

    local screen =
        cam.WorldToScreenPoint(worldPos)

    if screen.z < 0 then
        return nil
    end

    return Vector2(
        screen.x - Screen.width * 0.5,
        screen.y - Screen.height * 0.5
    )

end

function AtoAHUD:UpdateLine(startPos, endPos)

    local dir =
        endPos - startPos

    local dist =
        dir.magnitude

    if dist < 1 then

        self.lineImage.anchoredPosition =
            self.hiddenPos

        return

    end

    local mid =
        (startPos + endPos) * 0.5

    self.lineImage.anchoredPosition =
        mid

    local size =
        self.lineImage.sizeDelta

    size.x = dist

    self.lineImage.sizeDelta =
        size

    local angle =
        math.atan2(
            dir.y,
            dir.x
        ) * Mathf.Rad2Deg

    self.lineImage.localEulerAngles =
        Vector3(0, 0, angle)

end

function AtoAHUD:RotateIndicators(tgtPos)

    local parent =
        self.targetIndicatorObject
            .transform.parent

    if not parent then
        return
    end

    local worldDir =
        tgtPos -
        self.targetIndicatorObject
            .transform.position

    local localDir =
        parent:InverseTransformDirection(
            worldDir.normalized
        )

    local rot =
        Quaternion.LookRotation(
            localDir
        )

    self.targetIndicatorObject
        .transform.localRotation =
            rot

    self.targetIndicatorHide
        .transform.localRotation =
            rot

end

function AtoAHUD:ResetIndicators()

    self.targetIndicatorObject
        .transform.localRotation =
            Quaternion.Lerp(
                self.targetIndicatorObject
                    .transform.localRotation,
                self.identityRotation,
                Time.deltaTime * 5
            )

    self.targetIndicatorHide
        .transform.localRotation =
            Quaternion.Lerp(
                self.targetIndicatorHide
                    .transform.localRotation,
                self.identityRotation,
                Time.deltaTime * 5
            )

end

function AtoAHUD:SetHUDVisible(state)

    if self.canvasVisible == state then
        return
    end

    self.canvasVisible = state

    self.canvasObject:SetActive(state)

    self.targetIndicatorHide:SetActive(state)

    self.Gunobj:SetActive(state)

end

function AtoAHUD:HideUI()

    self.infoObject.anchoredPosition =
        self.hiddenPos

    self.targetObject.anchoredPosition =
        self.hiddenPos

    self.lineImage.anchoredPosition =
        self.hiddenPos

    self:SetHUDVisible(false)

end

function AtoAHUD:UpdateTargets()

    local result = {}
    local playerTeam = Player.team

    for i, vehicle in
        pairs(ActorManager.vehicles)
    do

        if vehicle and
           not vehicle.isTurret and
           not vehicle.isDead
        then

            if vehicle.team ~= playerTeam then
                result[#result + 1] = vehicle
            end
        end
    end

    self.potentialTarget = result

end
