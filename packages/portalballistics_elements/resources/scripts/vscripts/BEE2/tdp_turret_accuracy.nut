hurt <- Entities.FindByName(null, "@tdp_accurate_hurt")
turrets <- {}
LOCK_TIME <- 0.9
LOCK_RANGE <- 1024.0

function watch(turret) {
	turret.ValidateScriptScope()
	local scope = turret.GetScriptScope()
	scope.pt_tipped <- false
	scope.pt_held <- false
	scope.pt_enemy <- null
	scope.pt_since <- 0.0
	scope.pt_on_tipped <- function() { pt_tipped = true }
	// The stock turret keeps firing at its targets while carried (bug in P1 and P2).
	// Make it like them until dropped, then restore the ranks from persistent_target_globals / target_cube.
	scope.pt_on_pickup <- function() {
		pt_held = true
		EntFireByHandle(self, "SetRelationship", "persistenttarget* D_LI 99", 0.00, null, null)
		EntFireByHandle(self, "SetRelationship", "cube_addon_bullseye_target_box D_LI 99", 0.00, null, null)
	}
	scope.pt_on_drop <- function() {
		pt_held = false
		EntFireByHandle(self, "SetRelationship", "persistenttarget* D_HT 1", 0.00, null, null)
		EntFireByHandle(self, "SetRelationship", "cube_addon_bullseye_target_box D_HT 2", 0.00, null, null)
	}
	turret.ConnectOutput("OnTipped", "pt_on_tipped")
	turret.ConnectOutput("OnPhysGunPickup", "pt_on_pickup")
	turret.ConnectOutput("OnPhysGunDrop", "pt_on_drop")
	turrets[turret] <- scope
}

function can_hit(ent, shooter) {
	if (ent == shooter) return false
	local cls = ent.GetClassname()
	return cls == "prop_dynamic" || cls == "phys_bone_follower" // props only, never the player
}

function ray_dist(point, start, dir, length) {
	local t = (point - start).Dot(dir)
	if (t < 0 || t > length) return 99999
	return (point - (start + dir * t)).Length()
}

function enemy_point(ent) {
	if (ent.GetClassname() == "player") return ent.GetOrigin() + Vector(0, 0, 36)
	return ent.GetOrigin()
}

function aimed_enemy(start, dir, length) {
	local player = Entities.FindByClassname(null, "player")
	if (player != null && ray_dist(enemy_point(player), start, dir, length) <= 32) return player
	for (local ent = Entities.FindByClassname(null, "npc_bullseye"); ent != null; ent = Entities.FindByClassname(ent, "npc_bullseye")) {
		if (ray_dist(ent.GetOrigin(), start, dir, length) <= 32) return ent
	}
	return null
}

// TraceLine only hits the world, so cubes etc. are tested by bounding box (same as aperture_gun_aim.nut).
BLOCKERS <- ["player", "prop_weighted_cube", "prop_monster_box", "prop_physics", "prop_physics_override", "npc_portal_turret_floor"]

// Distance along dir to e's box, or 99999. Boxes the ray starts inside (the shooter) are ignored.
function ray_box(start, dir, e) {
	local lo = e.GetBoundingMins(), hi = e.GetBoundingMaxs()
	local los = [lo.x, lo.y, lo.z], his = [hi.x, hi.y, hi.z]
	local axes = e.GetClassname() == "player" ? [Vector(1, 0, 0), Vector(0, 1, 0), Vector(0, 0, 1)]
		: [e.GetForwardVector(), e.GetLeftVector(), e.GetUpVector()]
	local p = start - e.GetOrigin(), t0 = -99999.0, t1 = 99999.0
	for (local i = 0; i < 3; i++) {
		local s = p.Dot(axes[i]), d = dir.Dot(axes[i])
		if (fabs(d) < 0.000001) {
			if (s < los[i] || s > his[i]) return 99999
			continue
		}
		local a = (los[i] - s) / d, b = (his[i] - s) / d
		if (a > b) { local tmp = a; a = b; b = tmp }
		if (a > t0) t0 = a
		if (b < t1) t1 = b
		if (t0 > t1) return 99999
	}
	return t0 < 0 ? 99999 : t0
}

// Where the shot stops: the world, or the nearest cube/turret/player box.
function shot_dist(start, dir) {
	local dist = 4096 * TraceLine(start, start + dir * 4096, null)
	foreach (cls in BLOCKERS)
		for (local e = Entities.FindByClassname(null, cls); e != null; e = Entities.FindByClassname(e, cls)) {
			local d = ray_box(start, dir, e)
			if (d < dist) dist = d
		}
	return dist
}

function victim_at(point, shooter) {
	for (local ent = Entities.FindInSphere(null, point, 4); ent != null; ent = Entities.FindInSphere(ent, point, 4)) {
		if (can_hit(ent, shooter)) return ent
	}
	return null
}

function shoot(turret, scope) {
	local id = turret.LookupAttachment("eyes")
	local start = turret.GetAttachmentOrigin(id)
	local ang = turret.GetAttachmentAngles(id)
	local pitch = ang.x * PI / 180
	local yaw = ang.y * PI / 180
	local dir = Vector(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), -sin(pitch))
	local reach = shot_dist(start, dir)
	local hit = start + dir * reach
	local enemy = aimed_enemy(start, dir, reach + 32)
	if (enemy != scope.pt_enemy) {
		scope.pt_enemy = enemy
		scope.pt_since = Time()
	}
	if (enemy == null) return
	local dist = (enemy_point(enemy) - start).Length()
	local delay = LOCK_TIME * (dist < LOCK_RANGE ? dist / LOCK_RANGE : 1.0)
	if (Time() - scope.pt_since < delay) return
	local victim = victim_at(hit, turret)
	if (victim == null) return
	EntFireByHandle(hurt, "Hurt", "", 0.00, victim, turret)
}

function Think() {
	for (local ent = Entities.FindByClassname(null, "npc_portal_turret_floor"); ent != null; ent = Entities.FindByClassname(ent, "npc_portal_turret_floor")) {
		if (!(ent in turrets) && (ent.GetName().find("tdrpp") == 0 || ent.GetName().find("tdturr") == 0)) watch(ent)
	}
	local gone = []
	foreach (turret, scope in turrets) {
		if (!turret.IsValid()) {
			gone.append(turret)
		} else if (!scope.pt_tipped && !scope.pt_held && turret.GetHealth() > 0) {
			shoot(turret, scope)
		}
	}
	foreach (turret in gone) delete turrets[turret]
	return 0.1
}
