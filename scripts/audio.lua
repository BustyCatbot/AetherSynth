local audio = {
	extends = Node,
}

function audio:play(source, path, volume, pitch, range, channel)
	if not source then return end
	if not path then return end
	
	volume = volume or 1.0
	pitch = pitch or 1.0
	range = range or 20.0
	
	local player
	if range > 0 then
		player = AudioStreamPlayer3D:new()
		player.attenuation_filter_cutoff_hz = 20500.0
		player.max_db = volume * 36 - 36
		player.max_distance = range
	else
		player = AudioStreamPlayer:new()
	end
	source:add_child(player, true)
	
	player.volume_db = volume * 36 - 36
	player.pitch_scale = pitch
	
	player.stream = ResourceLoader:load("res://audio/"..path..".wav")

	function finish_call()
		if player and player:is_inside_tree() then
			player:queue_free()
		end
	end
	
	player.finished:connect(Callable(self, "finish_call"))
	
	player:play(0)
end

function audio:stop(source, path)
	if not source then return end
	if not path then return end
	
	for k,v in pairs(source:get_children()) do
		if not path or v.stream.resource_path == "res://audio/"..path..".wav" then
			v:stop()
			v:queue_free()
		end
	end
	
end

return audio
