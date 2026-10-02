hurt <- Entities.FindByName(null, "@tdp_accurate_hurt")
push <- Entities.FindByName(null, "@tdp_accurate_push")
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
	scope.pt_on_pickup <- function() { pt_held = true }
	scope.pt_on_drop <- function() { pt_held = false }
	turret.ConnectOutput("OnTipped", "pt_on_tipped")
	turret.ConnectOutput("OnPhysGunPickup", "pt_on_pickup")
	turret.ConnectOutput("OnPhysGunDrop", "pt_on_drop")
	turrets[turret] <- scope
}

function can_hit(ent, shooter) {
	if (ent == shooter) return false
	local cls = ent.GetClassname()
	return cls == "player" || cls == "prop_dynamic" || cls == "phys_bone_follower"
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
	local stop = start + dir * 4096
	local frac = TraceLine(start, stop, turret)
	local hit = start + (stop - start) * frac
	local enemy = aimed_enemy(start, dir, frac * 4096 + 32)
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
	push.SetOrigin(hit - dir * 16)
	push.SetAngles(ang.x, ang.y, 0)
	EntFireByHandle(push, "Enable", "", 0.00, turret, turret)
	EntFireByHandle(push, "Disable", "", 0.05, turret, turret)
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
