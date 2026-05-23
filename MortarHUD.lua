behaviour("MortarHUD")

function MortarHUD:Start()

    self.dataContainer =
        self.gameObject.GetComponent(DataContainer)

    self.vehicle =
        self.targets.vehicleObject:GetComponent(Vehicle)

    self.canvas =
        self.targets.canvas:GetComponent(RectTransform)

    self.targetObject =
        self.targets.targetObject:GetComponent(RectTransform)

    self.infoObject =
        self.targets.infoObject:GetComponent(RectTransform)

    self.lineImage =
        self.targets.lineImage:GetComponent(RectTransform)

    self.speeds =
        self:Split(
            self.dataContainer.GetString("calibrationSpeed"),
            " "
        )

    self.gravities =
        self:Split(
            self.dataContainer.GetString("calibrationGravity"),
            " "
        )

    self.target = nil
    self.compensatedPos = nil

    self.pointLock = false

    self.hiddenPos = Vector2(99999, 99999)

    self.updateInterval = 0.03
    self.updateTimer = 0

    self:HideUI()

end

function MortarHUD:Update()

    if not self.vehicle then
        self:HideUI()
        return
    end

    local cam = PlayerCamera.activeCamera

    if not cam then
        self:HideUI()
        return
    end

    self.updateTimer =
        self.updateTimer + Time.deltaTime

    self.targets.canvas.SetActive(
        self.vehicle.playerIsInside
    )

    if not self.vehicle.playerIsInside then
        self:HideUI()
        return
    end

    if self.vehicle.isDead then
        self:HideUI()
        return
    end

    if Input.GetKeyDown(KeyCode.G) then

        if self.pointLock then

            self.pointLock = false
            self.target = nil

            self:HideUI()

        else

            local ray =
                cam.ViewportPointToRay(
                    Vector3(0.5, 0.5, 0)
                )

            local hit =
                Physics.Raycast(
                    ray,
                    10000,
                    RaycastTarget.Default
                )

            if hit and hit.point then

                self.pointLock = true
                self.target = hit.point

            end
        end
    end

    if not self.pointLock then
        self:HideUI()
        return
    end

    if not self.target then
        self:HideUI()
        return
    end

    if self.updateTimer < self.updateInterval then
        return
    end

    self.updateTimer = 0

    self:UpdateHUD()

end

function MortarHUD:UpdateHUD()

    local cam = PlayerCamera.activeCamera

    if not cam then
        self:HideUI()
        return
    end

    local tgtPos = self.target

    local infoPos =
        self:WorldToCanvasPosition(tgtPos)

    if not infoPos then
        self:HideUI()
        return
    end

    self.infoObject.anchoredPosition =
        infoPos

    local gravity =
        self.gravities[1] or 1

    local speed =
        self.speeds[1] or 500

    local distance =
        Vector3.Distance(
            self.vehicle.transform.position,
            tgtPos
        )

    local aimPoint

    if gravity ~= 0 then

        local timeToReach =
            distance / speed

        local drop =
            self:CalculateDrop(
                timeToReach,
                gravity
            )

        aimPoint =
            Vector3(
                tgtPos.x,
                tgtPos.y + drop,
                tgtPos.z
            )

    else

        aimPoint = tgtPos

    end

    self.compensatedPos = aimPoint

    local aimPos =
        self:WorldToCanvasPosition(aimPoint)

    if not aimPos then
        self:HideUI()
        return
    end

    self.targetObject.anchoredPosition =
        aimPos

    self.targetObject.localScale =
        Vector3(1, 1, 1)

    self:UpdateLine(
        infoPos,
        aimPos
    )

end

function MortarHUD:UpdateLine(startPos, endPos)

    local direction =
        endPos - startPos

    local distance =
        direction.magnitude

    if distance < 1 then

        self.lineImage.anchoredPosition =
            self.hiddenPos

        return

    end

    local midpoint =
        (startPos + endPos) * 0.5

    self.lineImage.anchoredPosition =
        midpoint

    local size =
        self.lineImage.sizeDelta

    size.x = distance

    self.lineImage.sizeDelta = size

    local angle =
        math.atan2(
            direction.y,
            direction.x
        ) * Mathf.Rad2Deg

    self.lineImage.localEulerAngles =
        Vector3(0, 0, angle)

end

function MortarHUD:WorldToCanvasPosition(worldPos)

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

function MortarHUD:CalculateDrop(time, gravity)

    return
        0.5 *
        math.abs(Physics.gravity.y) *
        gravity *
        time *
        time

end

function MortarHUD:HideUI()

    self.infoObject.anchoredPosition =
        self.hiddenPos

    self.targetObject.anchoredPosition =
        self.hiddenPos

    self.lineImage.anchoredPosition =
        self.hiddenPos

end

function MortarHUD:Split(s, delimiter)

    local result = {}

    for match in
        (s .. delimiter):gmatch("(.-)" .. delimiter)
    do

        result[#result + 1] =
            tonumber(match)

    end

    return result

end
