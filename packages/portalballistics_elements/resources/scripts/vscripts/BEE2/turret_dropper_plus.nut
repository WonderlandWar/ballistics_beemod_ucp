template <- EntityGroup[0] // point_template
fizzler <- EntityGroup[1] // env_entity_dissolver for fizzling the turret
lower_door <- EntityGroup[2] // The door for lowering the turret
claw <- EntityGroup.len() > 3 ? EntityGroup[3] : null

turret_waiting <- null
turret_spawned <- null
constraint <- null
claw_delta <- 0
turret_yaw <- 0
IncludeScript("BEE2/tdp_patterns", this)
pattern_rank <- 0
lower_speed_str <- "200"
return_speed_str <- "400"
turret_color_str <- "255 255 255"

conf_respawn <- false
conf_ready_to_spawn <- false
conf_want_spawn <- false
// Are we lowering the turret down?
is_lowering <- false

// If I'm Different is the background music.
has_turr_music <- false
// The point at which the turret was placed, for the music.
// If the turret moves away (tipped/picked up), play music.
// Resetting this to null allows us to ensure each turret
// only plays it once.
turr_land_pos <- null;

function find_spawned(classname, skip) {
	local centre = template.GetOrigin()
	local best = null
	local best_dist = 128 * 128
	for (local ent = Entities.FindByClassname(null, classname); ent != null; ent = Entities.FindByClassname(ent, classname)) {
		local dist = (ent.GetOrigin() - centre).LengthSqr()
		if (ent != skip && dist < best_dist) {
			best = ent
			best_dist = dist
		}
	}
	return best
}

function on_turret_spawn() {
	// Grab references to the spawned things.
	// The template is with the spawned ents.
	turret_waiting = find_spawned("npc_portal_turret_floor", turret_spawned)
	constraint = find_spawned("phys_constraint", null)
	if (turret_waiting != null) {
		EntFireByHandle(turret_waiting, "DisablePickup", "", 0.00, self, self)
		tdp_turret_model(turret_waiting, pattern_rank)
	}
	local pair = find_spawned("logic_collision_pair", null)
	if (pair != null) {
		EntFireByHandle(pair, "DisableCollisions", "", 0.00, self, self)
		EntFireByHandle(pair, "Kill", "", 0.05, self, self)
	}
}

function pick_pattern() {
	pattern_rank = tdp_pattern_rank()
	local tube = Entities.FindByName(null, self.GetName().slice(0, -6) + "dropper_tube")
	if (tube != null && turret_color_str != "255 255 255") {
		EntFireByHandle(tube, "Skin", (1 + pattern_rank % 2).tostring(), 0.00, self, self)
	}
}

function drop_constraint() {
	if (constraint != null && constraint.IsValid()) {
		EntFireByHandle(constraint, "Kill", "", 0.00, self, self)
	}
	constraint = null
}

function speed_of(text, fallback) {
	try {
		local v = text.tofloat()
		if (v > 0) return v
	} catch (e) {}
	return fallback
}

function upright_turret() {
	if (turret_spawned == null || !turret_spawned.IsValid()) return
	EntFireByHandle(turret_spawned, "DisableMotion", "", 0.00, self, self)
	EntFireByHandle(self, "RunScriptCode", "set_upright()", 0.05, self, self)
	EntFireByHandle(turret_spawned, "EnableMotion", "", 0.30, self, self)
}

function set_upright() {
	if (turret_spawned == null || !turret_spawned.IsValid()) return
	turret_spawned.SetAngles(0, turret_yaw, 0)
}

function vec_yaw(v) {
	return atan2(v.y, v.x) * 57.29578
}

function apply_pose() {
	local centre = template.GetOrigin()
	local pose = null
	local best = 0
	for (local ent = Entities.FindByClassname(null, "info_target"); ent != null; ent = Entities.FindByClassname(ent, "info_target")) {
		if (ent.GetName().find("tdp_pose") == null) continue
		local off = ent.GetOrigin() - centre
		if (off.x * off.x + off.y * off.y > 48 * 48) continue
		if (pose == null || off.LengthSqr() < best) {
			pose = ent
			best = off.LengthSqr()
		}
	}
	local fwd = self.GetForwardVector()
	turret_yaw = vec_yaw(fwd * -1)
	if (pose == null) return
	turret_yaw = vec_yaw(pose.GetForwardVector())
	claw_delta = turret_yaw - vec_yaw(fwd * -1)
	local ang = template.GetAngles()
	template.SetAngles(ang.x, ang.y + claw_delta, ang.z)
	if (claw != null) {
		EntFireByHandle(claw, "ClearParent", "", 0.00, self, self)
		EntFireByHandle(self, "RunScriptCode", "rotate_claw()", 0.05, self, self)
	}
	EntFireByHandle(pose, "Kill", "", 0.00, self, self)
}

function rotate_claw() {
	local before = claw.GetAngles()
	claw.SetAngles(before.x, before.y + claw_delta, before.z)
	EntFireByHandle(claw, "SetParent", lower_door.GetName(), 0.00, self, self)
}

function OnPostSpawn() {
	pick_pattern()
	apply_pose()
	// Trigger an output so we can start getting a turret.
	EntFireByHandle(self, "FireUser4", "", 0.00, self, self)

	// Check if we should do the turret music logic.
	has_turr_music = Entities.FindByName(self, "@music_turret") != null
}

// Turret triggers this when it falls over, so we respawn it.
function turret_died() {
	if (has_turr_music && turr_land_pos != null) {
		EntFire("@music_turret", "PlaySound")
		turr_land_pos = null
	}
	// If lowering, cancel.
	if (is_lowering) {
		if (conf_respawn) {
			const_break()
		}
	} else {
		fizzle_active_turret()
		if (conf_respawn) {
			conf_want_spawn = true
		}
	}
}

// Request to spawn a turret.
function spawn() {
	fizzle_active_turret()
	conf_want_spawn = true
	// Don't delay.
	if (conf_want_spawn && conf_ready_to_spawn) {
		do_spawn()
	}
}

// Called when the turret is fully respawned.
function is_ready_to_spawn() {
	conf_ready_to_spawn = true
}

// When the turret starts lowering..
function start_lower() {
	is_lowering = true
}

// Turret is fully lowered, release it.
function release_turret() {
	local r = speed_of(return_speed_str, 400.0)
	EntFireByHandle(lower_door, "SetSpeed", (r / 4).tostring(), 0.50, self, self)
	EntFireByHandle(lower_door, "SetSpeed", (r / 2).tostring(), 0.70, self, self)
	EntFireByHandle(lower_door, "SetSpeed", r.tostring(), 0.80, self, self)
	if (turret_waiting == null || !turret_waiting.IsValid() || constraint == null || !constraint.IsValid()) {
		is_lowering = false
		if (turret_waiting != null && turret_waiting.IsValid()) {
			EntFireByHandle(fizzler, "Dissolve", "!activator", 0.00, turret_waiting, self)
		}
		turret_waiting = null
		drop_constraint()
		conf_want_spawn = true
		return
	}
	turret_spawned = turret_waiting
	// Respawning turrets set this, ignore from the turret.
	conf_want_spawn = false
	is_lowering = false
	turret_waiting = null
	EntFireByHandle(turret_spawned, "Enable", "", 0.50, self, self) // Make it active
	EntFireByHandle(turret_spawned, "EnablePickup", "", 0.60, self, self)
	upright_turret()
	EntFireByHandle(constraint, "Break", "", 0.00, self, self)
	constraint = null

	if (has_turr_music) {
		// Record the point the turret was dropped at to detect tipping.
		turr_land_pos = turret_spawned.GetOrigin();
	}
}

// Fired if the constraint snaps - the turret hit a bridge or something
// so we need to fizzle, and retry.
function const_break() {
	if (is_lowering) {
		// Turret might have died while lifting - ignore if so.

		// Clean up the dead turret after a second or so.
		if (turret_waiting != null && turret_waiting.IsValid()) {
			EntFireByHandle(fizzler, "Dissolve", "!activator", 1.50, turret_waiting, self)
		}
		drop_constraint()
		is_lowering = false
		turret_waiting = null
		conf_want_spawn = true
		// Should be null, but just in case.
		fizzle_active_turret()
		EntFireByHandle(lower_door, "Close", "", 0.00, self, self)
	} else if (turret_waiting != null && turret_waiting.IsValid()) {
		EntFireByHandle(fizzler, "Dissolve", "!activator", 0.00, turret_waiting, self)
		turret_waiting = null
		drop_constraint()
		conf_want_spawn = true
	}
}


// Internal functions

function do_spawn() {
	// Execute a spawn.
	fizzle_active_turret()
	EntFireByHandle(lower_door, "SetSpeed", speed_of(lower_speed_str, 200.0).tostring(), 0.00, self, self)
	conf_want_spawn = false
	conf_ready_to_spawn = false
	EntFireByHandle(self, "FireUser1", "", 0.00, self, self)
}
// If the turret is alive, fizzle it.
function fizzle_active_turret() {
	if (turret_spawned != null && turret_spawned.IsValid()) {
		// Dissolve activator, and pass the turret along as that.
		EntFireByHandle(fizzler, "Dissolve", "!activator", 0.00, turret_spawned, self)
		turr_land_pos = null
		turret_spawned = null
	}
}

function Think() {
	// If the spawned turret is invalid, it's been killed.
	// so we want to respawn it again.
	if (turret_spawned != null) {
		if(!turret_spawned.IsValid()) {
			turret_spawned = null
			if(conf_respawn) {
				conf_want_spawn = true
			}
		} else if (turret_spawned.GetHealth() <= 0) {
			turret_died()
		} else if (
			turr_land_pos != null &&
			(turret_spawned.GetOrigin() - turr_land_pos).LengthSqr() > 256 // 16^2
		) {
		    // Turret has been bumped a fair bit, treat this as killed.
			EntFire("@music_turret", "PlaySound")
			turr_land_pos = null
		}
	}
	// Check if we can actually spawn.
	if (conf_want_spawn && conf_ready_to_spawn) {
		do_spawn()
	}
	// Nothing is time-critical.
	// Put randomness in so lots of these don't all
	// think on the same frame.
	return RandomFloat(0.5, 1.5);
}
