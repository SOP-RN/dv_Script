behaviour("dvInputDamp")

function dvInputDamp:Start()
    self.animator = self.gameObject.GetComponent(Animator)
    self.dampTime = 0.9   -- Damping time for Animator SetFloat
end

function dvInputDamp:FixedUpdate()
    local yFloat = self.animator.GetFloat("input y")
    local wFloat = self.animator.GetFloat("input w")
    local zVel = self.animator.GetFloat("velocity z")

    self.animator.SetFloat("input y damp", yFloat, self.dampTime, Time.fixedDeltaTime)
    self.animator.SetFloat("input w damp", wFloat, 0.1, Time.fixedDeltaTime)
    self.animator.SetFloat("velocity z damp", zVel, 8, Time.fixedDeltaTime)

end

