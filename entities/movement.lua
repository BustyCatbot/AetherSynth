local movement = {
	extends = CharacterBody3D,
	
	base_friction = export(0.25),
	gravity = export(Vector3(0,-9.8,0)),
	terminal_velocity = export(50),
	air_drag = export(0.001),
	desired_height = export(1.0),
	height = export(1.0),
	
	look_sensitivity = export(0.006),
	look_direction = export(Vector3()),
	velocity = export(Vector3()),
	move_direction = export(Vector3()),
	desired_move_direction = export(Vector3()),
	
	movement_state = export("walk"),
	can_jump = export(false),
	base_speed = export(7.5),
	acceleration = export(0.15),
	grip_max = export(30),
	
	air_control = export(0.1),
	air_modifier = export(0.25),
	air_grip_max = export(30),
	
	jump_power = export(5),
	
	run_modifier = export(1.75),
	
	crouch_modifier = export(0.5),
	crouch_speed = export(1),
	
	slide_boost = export(1.1),
	slide_jump_boost = export(1.1),
	slide_friction = export(0.01),
	slide_cooldown = export(0.5),
	slide_cooldown_max = export(0.5),
	
	wallrun_boost = export(1.1),
	wallrun_jump_boost = export(1.1),
	wallrun_friction = export(0.01),
	wallrun_gravity = export(0.1),
	wallrun_cooldown = export(0),
	wallrun_cooldown_max = export(0.5),
	wall = nil,
	
	climb_speed = export(4),
	climb_friction = export(0.15),
	climb_gravity = export(0.75),
	climb_velocity = export(0),
	climb_tick = export(0),
	climb_tick_max = export(1),
	climb_cooldown = export(0),
	climb_cooldown_max = export(0.25),
	
	bonk_threshold = export(10),
	bonk_magnitude = export(Vector3()),
}

function movement:_unhandled_input(event)
	if event:is_class(InputEventMouseButton) then
		Input:set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elseif Input:is_action_pressed("ui_cancel") then
		Input:set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	end
	
	if Input:get_mouse_mode() == Input.MOUSE_MODE_CAPTURED then
		if event:is_class(InputEventMouseMotion) then
			self:rotate_y(-event.relative.x * self.look_sensitivity)
			self:get_node("Head"):rotate_x(-event.relative.y * self.look_sensitivity)
			self:get_node("Head"):set_rotation(Vector3(clamp(self:get_node("Head").rotation.x, deg_to_rad(-90), deg_to_rad(90)),0,0))
		end
	end
end

local previous_velocity = Vector3()
local previous_grounded = false
local previous_collided = false

local smoothmovedir = Vector3(0,0,1)
local smoothmovespeed = 0.0
local smoothjump = 0.0
local smoothwalldir = Vector3(0,0,1)
local smoothwalltilt = 0.0

function movement:_physics_process(delta)

	local gravity_parallel = self.gravity:normalized()
	local gravity_perpendicular = Vector3(1,1,1) - Vector3(math.abs(gravity_parallel.x), math.abs(gravity_parallel.y), math.abs(gravity_parallel.z))

	local head = self:get_node("Head")
	local camera = self:get_node("Head/Camera")
	local collider = self:get_node("Collider")
	local model = self:get_node("Model")
	
	local ground_casts = self:get_node("GroundCasts")
	local ground_gap = self:get_node("GroundCasts/GroundGap")
	local ground_check = self:get_node("GroundCasts/GroundCheck")
	local grounded = ground_check:is_colliding()
	
	local casts = self:get_node("Casts")
	local hang = self:get_node("Casts/Hang")
	local move_dir = self:get_node("Casts/MoveDir")
	local bonk_align = self.velocity * -move_dir:get_collision_normal()
	
	local full_collide = self:get_node("Casts/FullCollide")
	local collided = full_collide:is_colliding()
	
	local top_check = self:get_node("TopCheck")
	
	local ground_angle = self:get_node("GroundCasts/GroundAngle")
	local ground_angle_normal = Vector3()
	local ground_slope = 0
	if ground_angle:is_colliding() then
		ground_angle_normal = ground_angle:get_collision_normal()
		ground_slope = rad_to_deg(math.acos(ground_angle_normal:dot(-gravity_parallel))) / 90
	end
	local ground_up = self.move_direction:dot(ground_angle_normal * gravity_parallel:dot(ground_angle_normal) - gravity_parallel) / ((self.move_direction - ground_angle_normal * self.move_direction:dot(ground_angle_normal))):length() * (gravity_parallel - ground_angle_normal * gravity_parallel:dot(ground_angle_normal)):length()
	
	local wallrun_left = self:get_node("Casts/WallrunLeft")
	local wallrun_left_slope = 0
	if wallrun_left:is_colliding() then
		wallrun_left_slope = rad_to_deg(math.acos(wallrun_left:get_collision_normal():dot(-gravity_parallel))) / 90
	end
	
	local wallrun_right = self:get_node("Casts/WallrunRight")
	local wallrun_right_slope = 0
	if wallrun_right:is_colliding() then
		wallrun_right_slope = rad_to_deg(math.acos(wallrun_right:get_collision_normal():dot(-gravity_parallel))) / 90
	end
	
	local wallrun_back = self:get_node("Casts/WallrunBack")
	local wallrun_back_slope = 0
	if wallrun_back:is_colliding() then
		wallrun_back_slope = rad_to_deg(math.acos(wallrun_back:get_collision_normal():dot(-gravity_parallel))) / 90
	end
	
	local climb = self:get_node("Casts/Climb")
	local climb_slope = 0
	if climb:is_colliding() then
		climb_slope = rad_to_deg(math.acos(climb:get_collision_normal():dot(-gravity_parallel))) / 90
	end
	
	local audio = self:get_node("Audio")
	
	camera:set_rotation(Vector3())
	local walldir = gravity_parallel
	local walltilt = 0.0
	
	self.desired_move_direction = Vector3()

	if Input:is_action_pressed("move_forward") then
		self.desired_move_direction.z = self.desired_move_direction.z - 1
	end
	if Input:is_action_pressed("move_left") then
		self.desired_move_direction.x = self.desired_move_direction.x - 1
	end
	if Input:is_action_pressed("move_down") then
		--self.desired_move_direction.y = self.desired_move_direction.y - 1
	end
	if Input:is_action_pressed("move_backward") then
		self.desired_move_direction.z = self.desired_move_direction.z + 1
	end
	if Input:is_action_pressed("move_right") then
		self.desired_move_direction.x = self.desired_move_direction.x + 1
	end
	if Input:is_action_pressed("move_up") then
		--self.desired_move_direction.y = self.desired_move_direction.y + 1
	end
	
	if self.desired_move_direction:length() > 0 then
		self.desired_move_direction = self.basis * self.desired_move_direction:normalized()
	else
		self.desired_move_direction = Vector3()
	end
	
	if ground_angle:is_colliding() and grounded and self.desired_move_direction:length() > 0 then
		self.desired_move_direction = (self.desired_move_direction - ground_angle_normal * self.desired_move_direction:dot(ground_angle_normal)):normalized()
	end
	
	local move_speed = self.base_speed
	if self.movement_state == "run" and self.desired_move_direction:length() > 0 then
		move_speed = self.base_speed * self.run_modifier
		self.desired_height = 1.0
	elseif self.movement_state == "crouch" then
		move_speed = self.base_speed * self.crouch_modifier
		self.desired_height = 0.5
	elseif self.movement_state == "air" then
		move_speed = self.base_speed * self.air_modifier
		self.desired_height = 1.0
	else
		move_speed = self.base_speed * self.height
		self.desired_height = 1.0
	end
	
	move_dir:set_target_position(self.move_direction * clamp(self.velocity:length(),0,1))
	move_dir:set_position(self.global_position + -gravity_parallel * 0.1)
	if (self.velocity * -gravity_parallel) > -gravity_parallel and not grounded then
		move_dir:set_position(self.global_position + Vector3(0,1.5,0))
	end
	
	self:get_node("VectorVisual"):set_position(move_dir:get_position() + move_dir:get_target_position())
	
	-- State Definition
	
	if grounded and ground_slope <= 0.5 then
	
		if not previous_grounded then
			Audio:play(audio, "physics/concrete/concrete_step"..randi_range(1,4), clamp(bonk_align:length() * 0.5, 0, 1), 1.0, 5.0, "physics")
		end
	
		if self.movement_state ~= "slide" then
	
			if Input:is_action_pressed("crouch") and self.movement_state ~= "run" then
				self.movement_state = "crouch"
				self.can_jump = false
			elseif Input:is_action_pressed("run") and self.desired_move_direction:length() > 0 and self.movement_state ~= "crouch" and self.height > 0.75 then
				self.movement_state = "run"
				self.can_jump = true
			else
				self.movement_state = "walk"
				self.can_jump = true
			end
			
			if Input:is_action_pressed("run") and Input:is_action_pressed("crouch") and self.velocity:length() > self.base_speed * 1.1 then
				self.movement_state = "slide"
				Audio:play(audio, "physics/body/body_slide", 0.5, 1.0, 5.0, "physics")
				if self.slide_cooldown <= 0 then
					self.velocity = self.velocity * self.slide_boost
				end
			end
		
		end
		
	else
	
		if self.movement_state ~= "slide" and
		self.movement_state ~= "wallrun" and
		self.movement_state ~= "climb" and
		self.movement_state ~= "hang" then
	
			if Input:is_action_pressed("crouch") then
				self.movement_state = "brace"
				self.desired_height = 0.5
			elseif Input:is_action_pressed("move_forward") and Input:is_action_pressed("run") and not Input:is_action_pressed("crouch") and climb:is_colliding() and not ground_gap:is_colliding() and climb_slope > 0.8 then
				if self.climb_cooldown <= 0 then
					self.movement_state = "climb"
					self.climb_velocity = self.climb_speed
					self.climb_tick = 0
					self.desired_height = 1.0
				end
			elseif wallrun_left:is_colliding() and not ground_gap:is_colliding() and wallrun_left_slope > 0.8 then
				if self.wallrun_cooldown <= 0 then
					self.movement_state = "wallrun"
					smoothwalldir = wallrun_left:get_collision_normal():rotated(Vector3(0,1,0), deg_to_rad(-90))
					self.velocity = self.velocity * 0.5 + wallrun_left:get_collision_normal():rotated(Vector3(0,1,0), deg_to_rad(90)) * self.velocity:length() * self.wallrun_boost + self.gravity * -0.1
					self.desired_height = 1.0
				end
			elseif wallrun_right:is_colliding() and not ground_gap:is_colliding() and wallrun_right_slope > 0.8 then
				if self.wallrun_cooldown <= 0 then
					self.movement_state = "wallrun"
					smoothwalldir = wallrun_right:get_collision_normal():rotated(Vector3(0,1,0), deg_to_rad(-90))
					self.velocity = self.velocity * 0.5 + wallrun_right:get_collision_normal():rotated(Vector3(0,1,0), deg_to_rad(-90)) * self.velocity:length() * self.wallrun_boost + self.gravity * -0.1
					self.desired_height = 1.0
				end
			else
				self.movement_state = "air"
				self.desired_height = 1.0
			end
		
		end
		
		if self.movement_state == "climb" and not hang:is_colliding() and climb:is_colliding() then
			self.movement_state = "hang"
			Audio:play(audio, "physics/concrete/concrete_step"..randi_range(1,4), 1, 0.85, 5.0, "physics")
			self.climb_cooldown = self.climb_cooldown_max
		end
		
		self.can_jump = false
		
	end
	
	-- State Behavior
	
	if self.movement_state == "walk" or
	self.movement_state == "run" or
	self.movement_state == "crouch" then
	
		local factor = move_speed * self.acceleration * clamp(1 - self.velocity:dot(self.desired_move_direction) / move_speed, 0, 1)
		local friction = (self.velocity - self.desired_move_direction * self.velocity:dot(self.desired_move_direction)) * self.base_friction
		if self.velocity:length() > move_speed then
			friction = self.velocity * self.base_friction
		end
		local grip = clamp((1 - (self.velocity:length() / self.grip_max))^2, 0.1, 1)
		
		self.velocity = self.velocity + self.desired_move_direction * factor - friction * grip
		
	elseif self.movement_state == "slide" then
	
		self.desired_height = 0.35
		self.can_jump = false
	
		if not Input:is_action_pressed("crouch") or not Input:is_action_pressed("run") then
			self.movement_state = "walk"
			Audio:stop(audio, "physics/body/body_slide")
			self.slide_cooldown = self.slide_cooldown_max
		end
		
		if not grounded then
			self.movement_state = "brace"
			Audio:stop(audio, "physics/body/body_slide")
			self.slide_cooldown = self.slide_cooldown_max
		end
		
		if self.velocity:length() <= self.base_speed * self.crouch_modifier then
			self.movement_state = "crouch"
			Audio:stop(audio, "physics/body/body_slide")
			self.slide_cooldown = self.slide_cooldown_max
		end
		
		if Input:is_action_just_pressed("jump") then
			self.movement_state = "air"
			Audio:stop(audio, "physics/body/body_slide")
			Audio:play(audio, "physics/body/body_impact_soft"..randi_range(1,3), 0.75, 1.0, 5.0, "physics")
			self.velocity = self.velocity * gravity_perpendicular + -gravity_parallel * self.jump_power * self.slide_jump_boost
			self.slide_cooldown = self.slide_cooldown_max
		end
		
		self.velocity = self.velocity - self.velocity * (ground_up * 5 + 1) * self.slide_friction
		
	elseif self.movement_state == "air" or
	self.movement_state == "brace" then
	
		local grip = clamp((1 - (self.velocity:length() / self.air_grip_max))^2, 0.1, 1)
		local factor = move_speed * self.air_control * grip * clamp(1 - self.velocity:dot(self.desired_move_direction) / move_speed, 0, 1)
		local friction = (self.velocity - self.desired_move_direction * self.velocity:dot(self.desired_move_direction)) * self.air_drag
		if self.velocity:length() > move_speed then
			friction = self.velocity * self.air_drag
		end
	
		self.velocity = self.velocity + self.desired_move_direction * factor - friction + (self.gravity * delta)
		
	elseif self.movement_state == "wallrun" then
	
		local wallrotation = 0
	
		if wallrun_left:is_colliding() and not wallrun_right:is_colliding() then
			self.wall = wallrun_left
			wallrotation = 90
		elseif wallrun_right:is_colliding() and not wallrun_left:is_colliding() then
			self.wall = wallrun_right
			wallrotation = -90
		elseif wallrun_back:is_colliding() then
			self.wall = wallrun_back
		end
		
		walltilt = -7.5
		
		self.velocity = self.velocity - self.velocity * self.wallrun_friction + ((self.gravity * self.wallrun_gravity) * delta) + -self.wall:get_collision_normal()
		
		if grounded then
			self.movement_state = "walk"
			self.wallrun_cooldown = self.wallrun_cooldown_max
		end
		
		if self.velocity:length() <= self.base_speed * self.crouch_modifier then
			self.movement_state = "walk"
			self.wallrun_cooldown = self.wallrun_cooldown_max
		end
		
		if not self.wall:is_colliding() then
			self.movement_state = "air"
			self.wallrun_cooldown = self.wallrun_cooldown_max
		end
		
		if Input:is_action_pressed("crouch") or not Input:is_action_pressed("run") then
			self.movement_state = "air"
			self.wallrun_cooldown = self.wallrun_cooldown_max
		end
		
		if Input:is_action_just_pressed("jump") then
			self.movement_state = "air"
			self.velocity = self.velocity * 0.75 + self.wall:get_collision_normal() * 2 * self.wallrun_jump_boost + -gravity_parallel * self.wallrun_jump_boost * 4 + head.basis.z * 1 * self.wallrun_jump_boost
			self.slide_cooldown = 0.0
			self.wallrun_cooldown = self.wallrun_cooldown_max
			Audio:play(audio, "physics/concrete/concrete_step"..randi_range(1,4), 1.0, 1.0, 5.0, "physics")
			Audio:play(audio, "physics/body/body_impact_soft"..randi_range(1,3), 0.5, 1.0, 5.0, "physics")
		end
		
	elseif self.movement_state == "climb" then
		
		self.velocity = self.velocity + self.gravity * self.climb_gravity * delta
	
		if Time:get_unix_time_from_system() > self.climb_tick then
			self.velocity = self.velocity * gravity_perpendicular * 0.5 + gravity_parallel * -self.climb_velocity
			self.climb_velocity = self.climb_velocity * (1 - self.climb_friction)
			self.climb_tick = Time:get_unix_time_from_system() + self.climb_tick_max / self.climb_velocity
			Audio:play(audio, "physics/concrete/concrete_step"..randi_range(1,4), 0.75, 1.0, 5.0, "physics")
		end
		
		if grounded then
			self.movement_state = "walk"
			self.climb_cooldown = self.climb_cooldown_max
		end
		
		if self.climb_velocity <= 1.5 then
			self.movement_state = "air"
			self.climb_cooldown = self.climb_cooldown_max
		end
		
		if not climb:is_colliding() then
			self.movement_state = "air"
			self.climb_cooldown = self.climb_cooldown_max
		end
		
		if Input:is_action_pressed("crouch") or not Input:is_action_pressed("run") or not Input:is_action_pressed("move_forward") then
			self.movement_state = "air"
			self.climb_cooldown = self.climb_cooldown_max
		end
		
	elseif self.movement_state == "hang" then
	
		self.velocity = Vector3(0,0,0)
		
		if Input:is_action_pressed("crouch") then
			self.movement_state = "air"
		end
		
		if Input:is_action_pressed("jump") then
			self.movement_state = "air"
			self.velocity = -self.gravity * 0.65
			Audio:play(audio, "physics/concrete/concrete_step"..randi_range(1,4), 1.0, 1.0, 5.0, "physics")
			Audio:play(audio, "physics/body/body_impact_soft"..randi_range(1,3), 0.5, 1.0, 5.0, "physics")
		end

	end
	
	if self.can_jump and Input:is_action_just_pressed("jump") then
		self.can_jump = false
		self.velocity = self.velocity * gravity_perpendicular + -gravity_parallel * self.jump_power
		Audio:play(audio, "physics/concrete/concrete_step"..randi_range(1,4), 1.0, 1.0, 5.0, "physics")
		Audio:play(audio, "physics/body/body_impact_soft"..randi_range(1,3), 0.25, 1.0, 5.0, "physics")
	end
	
	if collided and not previous_collided then
		if bonk_align:length() > self.bonk_threshold then
			Audio:play(audio, "physics/body/body_impact_soft"..randi_range(1,3), 0.75, 1.0, 5.0, "physics")
			print("BONK")
		end
	end
	
	self.velocity.x = clamp(self.velocity.x, -self.terminal_velocity, self.terminal_velocity)
	self.velocity.y = clamp(self.velocity.y, -self.terminal_velocity, self.terminal_velocity)
	self.velocity.z = clamp(self.velocity.z, -self.terminal_velocity, self.terminal_velocity)
	
	if not (top_check:is_colliding() and self.desired_height > self.height) then
		self.height = lerp(self.height, self.desired_height, 0.1)
	end
	
	model:set_scale(Vector3(1, self.height, 1))
	model:set_position(Vector3(0, self.height, 0))
	collider:set_scale(Vector3(1, self.height, 1))
	collider:set_position(Vector3(0, self.height, 0))
	head:set_position(Vector3(0, self.height * 1.75, 0))
	casts:set_scale(Vector3(1, self.height, 1))
	ground_casts:set_position(Vector3(0, self.height * 0.25, 0))
	top_check:set_position(Vector3(0, self.height * 1.75, 0))
	
	smoothmovedir = lerp(smoothmovedir, (self.move_direction * gravity_perpendicular):rotated(Vector3(0,1,0), deg_to_rad(90)), 0.25):normalized()
	
	local forward = clamp(math.abs(smoothmovedir:dot(self.basis.z)), 0.5, 1.0)
	
	if self.movement_state == "slide" then
		smoothmovespeed = lerp(smoothmovespeed, clamp(-self.velocity:length() * 0.75, -15.0, 15.0), 0.05) * forward
	elseif self.movement_state == "wallrun" then
		smoothmovespeed = clamp(lerp(smoothmovespeed, 0.0, 0.05), -15.0, 15.0) * forward
	else
		smoothmovespeed = lerp(smoothmovespeed, clamp(self.velocity:length() * 0.5, -15.0, 15.0), 0.05) * forward
	end
	
	if self.wall ~= nil then
		walldir = self.wall:get_collision_normal()
	end
	
	local jump = clamp(self.velocity.y * 1.5, -15.0, 15.0)
	
	if self.movement_state == "brace" or grounded then
		jump = 0.0
	end
	
	smoothjump = lerp(smoothjump, jump, 0.1)
	smoothwalldir = lerp(smoothwalldir, walldir:rotated(Vector3(0,1,0), deg_to_rad(-90)), 0.05):normalized()
	smoothwalltilt = lerp(smoothwalltilt, walltilt, 0.1)
	
	smoothmovedir = Vector3(clamp(smoothmovedir.x,-1,1),clamp(smoothmovedir.y,-1,1),clamp(smoothmovedir.z,-1,1)):normalized()
	
	camera:global_rotate(smoothmovedir, deg_to_rad(smoothmovespeed))
	camera:set_rotation(Vector3(camera.rotation.x + deg_to_rad(smoothjump),camera.rotation.y,camera.rotation.z))
	camera:global_rotate(smoothwalldir, deg_to_rad(smoothwalltilt))
	
	local previous_position = self.global_position
	
	self:set("velocity", self.velocity)
	self:move_and_slide()
	
	self.move_direction = (self.global_position - previous_position):normalized()
	
	if self.slide_cooldown > 0 and grounded then
		self.slide_cooldown = self.slide_cooldown - delta
	end
	
	if self.wallrun_cooldown > 0 then
		self.wallrun_cooldown = self.wallrun_cooldown - delta
	end
	
	if self.climb_cooldown > 0 and grounded then
		self.climb_cooldown = self.climb_cooldown - delta
	end
	
	local velocity_correct = ((self.velocity) - (self.global_position - previous_position) / delta):length()
	print((math.ceil(self.velocity:length() * 10) / 10).."/"..(math.ceil(move_speed * 10) / 10)..", "..self.movement_state.." | "..(math.ceil(self.desired_move_direction.x * 10) / 10)..", "..(math.ceil(self.desired_move_direction.y * 10) / 10)..", "..(math.ceil(self.desired_move_direction.z * 10) / 10).." | "..(math.ceil(ground_slope * 100) / 100 * 90).." | "..(math.floor(velocity_correct * 10) / 10).." : "..(math.ceil(self.velocity.x - (self.global_position - previous_position).x * 10) / 10)..", "..(math.ceil(self.velocity.y - (self.global_position - previous_position).y * 10) / 10)..", "..(math.ceil(self.velocity.z - (self.global_position - previous_position).z * 10) / 10))
	
	if velocity_correct > 0.1 then
		--self.velocity = (self.global_position - previous_position) / delta
	end
	
	previous_grounded = ground_check:is_colliding()
	previous_collided = full_collide:is_colliding()
	
end

return movement
