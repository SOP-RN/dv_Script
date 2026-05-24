behaviour("GuidedBombVel")

function GuidedBombVel:Start()
    self.projectile = self.targets.projectile.GetComponent(Projectile)
    
    if self.projectile == nil or not self.projectile.isTargetSeekingMissileProjectile then
        self:DestroyScript()
        return
    end

    self.syncCount = 2  -- Number of updates to sync velocity with killCredit
    self.updateCounter = 0

    -- Apply initial velocity from the firing vehicle
    if self.projectile.killCredit then
        self.projectile.velocity = self.projectile.killCredit.velocity * 1
        local inheritedSpeed = self.projectile.velocity.magnitude
    end
end

function GuidedBombVel:FixedUpdate()
    if self.updateCounter < self.syncCount then
        -- Keep syncing velocity with killCredit for the first 3 updates
        if self.projectile.killCredit then
            self.projectile.velocity = self.projectile.killCredit.velocity * 1
        end
        self.updateCounter = self.updateCounter + 1
    end

    -- Simulate gravity by applying a downward force
    local gravity = Vector3(0, -9.81, 0)  -- Gravity vector, adjust magnitude if needed
    self.projectile.velocity = self.projectile.velocity + gravity * Time.fixedDeltaTime
end
