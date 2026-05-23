behaviour("MortarHUD")

function MortarHUD:Start()
    self.dataContainer = self.gameObject.GetComponent(DataContainer)
    self.vehicle = self.targets.vehicleObject.GetComponent(Vehicle)
    self.target = nil
    self.compensatedPos = nil
    self.targetObject = self.targets.targetObject.transform
    self.infoObject = self.targets.infoObject.transform
    self.lineImage = self.targets.lineImage:GetComponent(RectTransform)
    self.delay = 0

    self.canvasObject = self.targets.canvas

    self.speeds = self:Split(self.dataContainer.GetString("calibrationSpeed"), " ")
    self.gravities = self:Split(self.dataContainer.GetString("calibrationGravity"), " ")

    self.out = Vector3(5000, 5000, 0)

    self.pointLock = false
end

function MortarHUD:Update()
    self.delay = self.delay + Time.deltaTime

    self.canvasObject.SetActive(self.vehicle.playerIsInside)
    
    self.haveTarget = self.pointLock

    if Input.GetKey(KeyCode.Space) and self.vehicle.playerIsInside then
        if not self.haveTarget then
            local raycast = Physics.Raycast(PlayerCamera.activeCamera.ViewportPointToRay(Vector3(0.5, 0.5, 0)), 10000, RaycastTarget.Default)

            if raycast ~= nil then
                self.pointLock = true
                self.target = raycast.point
            else
                self.target = nil
                self.pointLock = false
                self:HideUI()
            end
        end

        if self.haveTarget and not self.vehicle.isDead then
            local tgtPos = self.target

            if self.delay >= 0.1 then
                self.delay = self.delay - 0.1

                local infoObjectPos = self:GetScreenPoint(tgtPos)
                self.infoObject.position = infoObjectPos

                local weaponGravity = self.gravities[1]
                local distance = Vector3.Distance(self.vehicle.transform.position, tgtPos)

                if weaponGravity ~= 0 then
                    local aimVector = Vector3(tgtPos.x, tgtPos.y, tgtPos.z)
                    
                    local timeToReach = distance / self.speeds[1]
                    local drop = self:CalculateDrop(timeToReach, weaponGravity)

                    aimVector.y = aimVector.y - drop

                    local pos = self:GetScreenPoint(aimVector)
                    pos.z = self.targetObject.position.z  -- Keep the original z position

                    self.compensatedPos = aimVector

                    self.targetObject.position = pos
                else
                    self.compensatedPos = tgtPos
                    self.targetObject.position = infoObjectPos
                    self.targetObject.position.z = self.targetObject.position.z  -- Keep the original z position
                end

                -- Keep the target object at a constant size
                self.targetObject.localScale = Vector3(1, 1, 1)

                -- Draw the line between the info object and the target object
                self:DrawLineBetweenPoints(self.infoObject.position, self.targetObject.position)
            end
        end
    else
        self.target = nil
        self.pointLock = false
        self:HideUI()
    end
end

function MortarHUD:GetScreenPoint(point)
    local pos = PlayerCamera.activeCamera.WorldToScreenPoint(point)

    if pos.z < 0 then
        return self.out
    end

    pos.z = 0

    return pos
end

function MortarHUD:CalculateDrop(time, gravity)
    local drop = 0.5 * Physics.gravity.y * gravity * math.pow(time, 2)
    return drop
end

function MortarHUD:DrawLineBetweenPoints(startPos, endPos)
    local direction = endPos - startPos
    local distance = direction.magnitude

    self.lineImage.sizeDelta = Vector2(distance, self.lineImage.sizeDelta.y)
    self.lineImage.position = startPos + (direction / 2)

    local angle = math.deg(math.atan2(direction.y, direction.x))
    self.lineImage.rotation = Quaternion.Euler(0, 0, angle)
end

function MortarHUD:HideUI()
    self.infoObject.localPosition = self.out
    self.targetObject.localPosition = self.out
    self.lineImage.localPosition = self.out
end

function MortarHUD:Split(s, delimiter)
    result = {}
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, tonumber(match))
    end
    return result
end
