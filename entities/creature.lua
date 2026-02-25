local creature = {
	extends = CharacterBody3D,
	
	base_friction = export(0.25),
	gravity = export(Vector3(0,-9.8,0)),
	terminal_velocity = export(50),
	air_drag = export(0.001),
}

return creature
