behaviour("dvPSE")

function dvPSE:Start()
    self.dataContainer = self.gameObject.GetComponent(DataContainer)
    self.vehicle = self.gameObject.GetComponent(Vehicle)
    self.animator = self.gameObject.GetComponent(Animator)
    self.requiredHoldTime = 7.5
    self.holdFireTime = 0
    self:FindLastWeaponInFirstSeat()

    -- Store the positions and rotations of critical parts
    self.positionsAndRotations = {
        engine1 = self.targets.engine1,
        engine2 = self.targets.engine2,
        wing1 = self.targets.wing1,
        wing2 = self.targets.wing2,
        hStab1 = self.targets.hStab1,
        hStab2 = self.targets.hStab2,
        vStab1 = self.targets.vStab1,
        vStab2 = self.targets.vStab2
    }

    -- Initiate critical parts at the start
    self:InitiateCriticalParts()

    -- Initialize destruction values and High G mode settings
    self:InitializeDestructionAndGMode()
end

function dvPSE:InitializeDestructionAndGMode()
    -- Initialize Destruction Values
    self.rollDestruction = 0
    self.pitchDestruction = 0
    self.yawDestruction = 0
    self.engineDestruction = 0
    self.EDS = 0
    self.ctrlDestruction = 0
    -- Initialize High G Mode Status
    self.isHighGTurnActive = false
    self.currentFactor = 0
end

function dvPSE:InitiateCriticalParts()
    -- Instantiate each critical part as a child of its corresponding transform
    self.engine1 = GameObject.Instantiate(self.dataContainer.GetGameObject("engine1Prefab"), 
                                          self.positionsAndRotations.engine1.transform.position, 
                                          self.positionsAndRotations.engine1.transform.rotation, 
                                          self.positionsAndRotations.engine1.transform)

    self.engine2 = GameObject.Instantiate(self.dataContainer.GetGameObject("engine2Prefab"), 
                                          self.positionsAndRotations.engine2.transform.position, 
                                          self.positionsAndRotations.engine2.transform.rotation, 
                                          self.positionsAndRotations.engine2.transform)

    self.wing1 = GameObject.Instantiate(self.dataContainer.GetGameObject("wing1Prefab"), 
                                        self.positionsAndRotations.wing1.transform.position, 
                                        self.positionsAndRotations.wing1.transform.rotation, 
                                        self.positionsAndRotations.wing1.transform)

    self.wing2 = GameObject.Instantiate(self.dataContainer.GetGameObject("wing2Prefab"), 
                                        self.positionsAndRotations.wing2.transform.position, 
                                        self.positionsAndRotations.wing2.transform.rotation, 
                                        self.positionsAndRotations.wing2.transform)

    self.hStab1 = GameObject.Instantiate(self.dataContainer.GetGameObject("hStab1Prefab"), 
                                         self.positionsAndRotations.hStab1.transform.position, 
                                         self.positionsAndRotations.hStab1.transform.rotation, 
                                         self.positionsAndRotations.hStab1.transform)

    self.hStab2 = GameObject.Instantiate(self.dataContainer.GetGameObject("hStab2Prefab"), 
                                         self.positionsAndRotations.hStab2.transform.position, 
                                         self.positionsAndRotations.hStab2.transform.rotation, 
                                         self.positionsAndRotations.hStab2.transform)

    self.vStab1 = GameObject.Instantiate(self.dataContainer.GetGameObject("vStab1Prefab"), 
                                         self.positionsAndRotations.vStab1.transform.position, 
                                         self.positionsAndRotations.vStab1.transform.rotation, 
                                         self.positionsAndRotations.vStab1.transform)

    self.vStab2 = GameObject.Instantiate(self.dataContainer.GetGameObject("vStab2Prefab"), 
                                         self.positionsAndRotations.vStab2.transform.position, 
                                         self.positionsAndRotations.vStab2.transform.rotation, 
                                         self.positionsAndRotations.vStab2.transform)
end


function dvPSE:Update()
    -- Check if any critical part is destroyed
    self:CheckCriticalPartsStatus()
    -- Continue with the original script's logic
    self:UpdateDestructionValues()

    self.ctrlDestruction = self.rollDestruction + self.pitchDestruction + self.yawDestruction
    self.animator:SetFloat("RollDestruction", self.rollDestruction)
    self.animator:SetFloat("PitchDestruction", self.pitchDestruction)
    self.animator:SetFloat("YawDestruction", self.yawDestruction)
    self.animator:SetFloat("engineDestructionStatus", self.EDS)
    --print(self.engineDestruction)
    self.animator:SetFloat("EngineDestruction", self.engineDestruction)
    self.animator:SetFloat("ctrl destruction", self.ctrlDestruction)
    self:HandleHighGMode()

end

function dvPSE:FixedUpdate()

    -- Apply angular velocity adjustment for engine imbalance
    self:ApplyEngineImbalance()

    if self.lastWeapon and self.lastWeapon.isHoldingFire then
        self.holdFireTime = self.holdFireTime + Time.deltaTime

        if self.holdFireTime >= self.requiredHoldTime then
            self:RepairCriticalParts()
            self.holdFireTime = 0  -- Reset the timer after the repair
        end
    else
        self.holdFireTime = 0  -- Reset the timer if fire is not being held continuously
    end
end


function dvPSE:CheckCriticalPartsStatus()
    -- Check the status of each critical part and update destruction values if necessary
    if not self.engine1 or not self.engine2 or 
       not self.wing1 or not self.wing2 or 
       not self.hStab1 or not self.hStab2 or 
       not self.vStab1 or not self.vStab2 then
        self:HandleCriticalPartDestruction()
    end

    if not self.engine1.activeSelf and not self.engine2.activeSelf then
        self.EDS = 3  -- Both engines damaged
    elseif not self.engine1.activeSelf then
        self.EDS = 1  -- Left engine damaged
    elseif not self.engine2.activeSelf then
        self.EDS = 2  -- Right engine damaged
    else
        self.EDS = 0  -- No engines damaged
    end
end

function dvPSE:HandleCriticalPartDestruction()

    self.engineDestruction = (not self.engine1 and not self.engine2) and 1 or 0
    self.rollDestruction = (not self.wing1 and not self.wing2) and 1 or 0
    self.pitchDestruction = (not self.hStab1 and not self.hStab2) and 1 or 0
    self.yawDestruction = (not self.vStab1 and not self.vStab2) and 1 or 0
end

function dvPSE:FindLastWeaponInFirstSeat()
    -- Get the first seat in the vehicle
    local firstSeat = self.vehicle.seats[1]

    -- Get the last weapon in the first seat
    if firstSeat and firstSeat.weapons then
        self.lastWeapon = firstSeat.weapons[#firstSeat.weapons]
    end
end

function dvPSE:RepairCriticalParts()
    -- Destroy and reinitiate parts if health is above a certain threshold
    if self.engine1 then GameObject.Destroy(self.engine1) end
    if self.engine2 then GameObject.Destroy(self.engine2) end
    if self.wing1 then GameObject.Destroy(self.wing1) end
    if self.wing2 then GameObject.Destroy(self.wing2) end
    if self.hStab1 then GameObject.Destroy(self.hStab1) end
    if self.hStab2 then GameObject.Destroy(self.hStab2) end
    if self.vStab1 then GameObject.Destroy(self.vStab1) end
    if self.vStab2 then GameObject.Destroy(self.vStab2) end

    -- Reinitialize parts
    self:InitiateCriticalParts()

    -- Reset destruction values
    self.rollDestruction = 0
    self.pitchDestruction = 0
    self.yawDestruction = 0
    self.engineDestruction = 0
    self.EDS = 0
    self.ctrlDestruction = 0
end

function dvPSE:UpdateDestructionValues()
    -- Update Roll Destruction
    local wingCount = (self.wing1 and self.wing1.activeSelf and 1 or 0) + (self.wing2 and self.wing2.activeSelf and 1 or 0)
    self.rollDestruction = 1 - (wingCount / 2)
    
    -- Update Pitch Destruction
    local hStabCount = (self.hStab1 and self.hStab1.activeSelf and 1 or 0) + (self.hStab2 and self.hStab2.activeSelf and 1 or 0)
    self.pitchDestruction = 1 - (hStabCount / 2)

    -- Update Yaw Destruction
    local vStabCount = (self.vStab1 and self.vStab1.activeSelf and 1 or 0) + (self.vStab2 and self.vStab2.activeSelf and 1 or 0)
    self.yawDestruction = 1 - (vStabCount / 2)

    -- Update Engine Destruction
    local engineCount = (self.engine1 and self.engine1.activeSelf and 1 or 0) + (self.engine2 and self.engine2.activeSelf and 1 or 0)
    self.engineDestruction = 1 - (engineCount / 2)


end

function dvPSE:HandleHighGMode()
    if self.ctrlDestruction > 1 then
        self.isHighGTurnActive = true
    else
        self.isHighGTurnActive = false
    end
end

function dvPSE:HandleHighGMode()
    if Input.GetKey(KeyCode.Space) and self.ctrlDestruction < 1 then
        self.isHighGTurnActive = true
        self.animator:SetBool("HighGActive", true)
    else
        self.isHighGTurnActive = false
        self.animator:SetBool("HighGActive", false)
    end
end

function dvPSE:ApplyEngineImbalance()
    -- Check if the vehicle has a driver
    if self.vehicle.hasDriver then
        local velocityMagnitude = self.vehicle.rigidbody.velocity.magnitude

        -- Check if the driver is a bot
        if self.vehicle.driver.isBot then
            -- Use velocity-based angular velocity adjustment for bots
            local angularVelocityAdjustment = math.min(velocityMagnitude * 0.01, 0.1)

            if not self.engine1.activeSelf and self.engine2.activeSelf then
                -- Only engine 2 is active
                local localAngularVelocity = Vector3(0, -self.engineDestruction * angularVelocityAdjustment, 0)
                self.vehicle.rigidbody.angularVelocity = self.vehicle.transform:TransformDirection(localAngularVelocity) * 0.1 + self.vehicle.rigidbody.angularVelocity
            elseif not self.engine2.activeSelf and self.engine1.activeSelf then
                -- Only engine 1 is active
                local localAngularVelocity = Vector3(0, self.engineDestruction * angularVelocityAdjustment, 0)
                self.vehicle.rigidbody.angularVelocity = self.vehicle.transform:TransformDirection(localAngularVelocity) * 0.1 + self.vehicle.rigidbody.angularVelocity
            end
        else
            -- Use throttle and velocity-based angular velocity adjustment for human players
            local throttleInput = Input.GetKeyBindAxis(KeyBinds.PlaneThrottle)

            if throttleInput > 0 then
                -- Calculate velocity-based multiplier (0.1 at 300m/s, linearly decreasing to 1 at 0m/s)
                local velocityMultiplier = Mathf.Clamp(1 - (velocityMagnitude / 600), 1, 5, 9)

                if not self.engine1.activeSelf and self.engine2.activeSelf then
                    -- Only engine 2 is active
                    local localAngularVelocity = Vector3(0, -self.engineDestruction * throttleInput * velocityMultiplier, 0)
                    self.vehicle.rigidbody.angularVelocity = self.vehicle.transform:TransformDirection(localAngularVelocity) * 0.02 + self.vehicle.rigidbody.angularVelocity
                elseif not self.engine2.activeSelf and self.engine1.activeSelf then
                    -- Only engine 1 is active
                    local localAngularVelocity = Vector3(0, self.engineDestruction * throttleInput * velocityMultiplier, 0)
                    self.vehicle.rigidbody.angularVelocity = self.vehicle.transform:TransformDirection(localAngularVelocity) * 0.02 + self.vehicle.rigidbody.angularVelocity
                end
            end
        end
    end
end


