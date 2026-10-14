// Ballistics Aperture Gun: aims the gun at the mounted player's crosshair.

// Pose ranges of aperture_gun_p2.mdl. Yaw + = left, pitch - = up.
YAW_MIN   <- -90.0;  YAW_MAX   <- 90.0;
PITCH_MIN <- -80.0;  PITCH_MAX <- 30.0;
MAX_DIST  <- 8192.0;

local me = self.GetName();
PREFIX <- me.slice(0, me.len() - "gun_script".len());

gun <- null;
grab <- null;
eye_measure <- null;

function Resolve() {
	gun        	= Entities.FindByName(null, PREFIX + "gun");
	eye        	<- Entities.FindByName(null, PREFIX + "gun_eye");
	pivot      	<- Entities.FindByName(null, PREFIX + "gun_pivot");
	hit_target 	<- Entities.FindByName(null, PREFIX + "gun_hit");
	yaw_ctrl   	<- Entities.FindByName(null, PREFIX + "gun_yaw");
	pitch_ctrl 	<- Entities.FindByName(null, PREFIX + "gun_pitch");
	grab       	<- Entities.FindByName(null, PREFIX + "gun_grab");
	laser      	<- Entities.FindByName(null, PREFIX + "gun_laser");
	laser_exit 	<- Entities.FindByName(null, PREFIX + "gun_laser_exit");
	hit_exit   	<- Entities.FindByName(null, PREFIX + "gun_hit_exit");
	bullets    	<- Entities.FindByName(null, PREFIX + "gun_bullets_base");
	eye_measure	<- Entities.FindByName(null, PREFIX + "gun_eye_measure");
}

// P2's TraceLine only hits the world; env_laser also stops at entities, so test these by bounding box.
BLOCKERS <- ["player", "prop_weighted_cube", "prop_monster_box", "prop_physics", "prop_physics_override", "npc_portal_turret_floor"];

// Distance along dir to e's box (oriented by its angles; the player's box is world-aligned), or MAX_DIST.
// Boxes the ray starts inside are ignored.
function RayBox(start, dir, e) {
	local lo = e.GetBoundingMins(), hi = e.GetBoundingMaxs();
	local los = [lo.x, lo.y, lo.z], his = [hi.x, hi.y, hi.z];
	local axes = e.GetClassname() == "player" ? [Vector(1, 0, 0), Vector(0, 1, 0), Vector(0, 0, 1)]
		: [e.GetForwardVector(), e.GetLeftVector(), e.GetUpVector()];
	local p = start - e.GetOrigin(), t0 = -MAX_DIST, t1 = MAX_DIST;
	for (local i = 0; i < 3; i++) {
		local s = p.Dot(axes[i]), d = dir.Dot(axes[i]);
		if (fabs(d) < 0.000001) {
			if (s < los[i] || s > his[i]) return MAX_DIST;
			continue;
		}
		local a = (los[i] - s) / d, b = (his[i] - s) / d;
		if (a > b) { local tmp = a; a = b; b = tmp; }
		if (a > t0) t0 = a;
		if (b < t1) t1 = b;
		if (t0 > t1) return MAX_DIST;
	}
	return t0 < 0 ? MAX_DIST : t0;
}

// Where a beam from start along dir stops: the world or the nearest blocker (our own entities excluded).
function Trace(start, dir) {
	local dist = MAX_DIST * TraceLine(start, start + dir * MAX_DIST, null);
	foreach (cls in BLOCKERS)
		for (local e = null; e = Entities.FindByClassname(e, cls);)
			if (e.GetName().find(PREFIX) != 0) {
				local d = RayBox(start, dir, e);
				if (d < dist) dist = d;
			}
	return start + dir * dist;
}

// Portal pass-through for the laser.
PORTAL_HALF_W <- 32.0;  PORTAL_HALF_H <- 56.0;
exit_on <- false;

function SetExit(on) {
	if (on == exit_on) return;
	exit_on = on;
	EntFireByHandle(laser_exit, on ? "TurnOn" : "TurnOff", "", 0, null, null);
	EntFire(PREFIX + "gun_hit_exit_sprite", on ? "ShowSprite" : "HideSprite", "", 0, null);
}

// The beam follows the model's "laser" attachment, straight out of the barrel (attachment -Y).
// Not parented (env_laser parenting is buggy, see VDC): LaserThink moves it every tick. It is on from
// map start (gun_laser and gun_hit_sprite start on) and never stops, so portals placed later still bend it.
// It also carries gun_bullets_base (the P1-style func_tanks, sprites and beam end hang off it) on "muzzle".
laser_active <- true;
mounted <- false; // set by gun_ui PlayerOn / PlayerOff

// Single driver for aiming and the laser: one fixed order every tick. (SetPoseValue is queued I/O,
// so the laser still reads the pose from one tick behind.)
function LaserThink() {
	if (mounted) Aim();
	if (laser_active) Laser();
	return 0.01; // next tick; 0 or nothing falls back to sv_script_think_interval (0.1s)
}

function Laser() {
	if (!gun) Resolve();
	local muzzleid = gun.LookupAttachment("muzzle");
	local laserid = gun.LookupAttachment("laser");
	local startMuzzle = gun.GetAttachmentOrigin(muzzleid);
	local startLaser = gun.GetAttachmentOrigin(laserid);
	local ang = gun.GetAttachmentAngles(laserid);
	laser.SetOrigin(startLaser);
	laser.SetAngles(ang.x, ang.y, ang.z);
	local dir = laser.GetLeftVector() * -1;
	bullets.SetOrigin(startMuzzle);
	bullets.SetForwardVector(dir);
	hit_target.SetOrigin(LaserExit(Trace(startMuzzle, dir), dir));
}

// The 15 gun_bullets func_tanks only fire when they think, every 0.1s, and they all spawn active on
// the same tick, so they fire in one volley per think. The Activate input restarts a tank's think
// clock, so activating them staggered across one think interval spreads their shots out. Called by
// gun_fire_start, which also sets SetFireRate 12: at exactly 10, int(0.1 * 10) can round down to 0
// and skip a think (0.2s gaps let the persistent target's 0.15s timer run out). 12 still fires one
// bullet per think, so each tank stays at 10 shots/s.
THINK_INTERVAL <- 0.1; // func_tank's think interval when aiming at a target entity

function StartBullets() {
	local tanks = [];
	for (local e = null; e = Entities.FindByName(e, PREFIX + "gun_bullets");) tanks.append(e);
	foreach (i, e in tanks) {
		EntFireByHandle(e, "SetTargetEntityName", PREFIX + "gun_beam_end", 0, null, null);
		EntFireByHandle(e, "Activate", "", i * THINK_INTERVAL / tanks.len(), null, null);
	}
}

// A fizzled or never-placed prop_portal stays in the map (inactive, at its last spot), so the
// gun_portal_detector (a func_portal_detector covering the whole map, all portal IDs) reports each
// portal opening (OnStartTouchPortal) and closing (OnEndTouchPortal) here, with the portal as !activator.
// The flag lives in the portal's own scope, so every gun shares it.
function SetPortalActive(on) {
	if (!activator || activator.GetClassname() != "prop_portal") return;
	activator.ValidateScriptScope();
	activator.GetScriptScope().bal_active <- on;
}

function IsActive(p) {
	local s = p.GetScriptScope();
	return s != null && ("bal_active" in s) && s.bal_active;
}

function PortalAt(pos) {
	for (local p = null; p = Entities.FindByClassname(p, "prop_portal");) {
		if (!IsActive(p)) continue;
		local d = pos - p.GetOrigin();
		if (fabs(d.Dot(p.GetForwardVector())) <= 8.0
			&& fabs(d.Dot(p.GetLeftVector())) <= PORTAL_HALF_W
			&& fabs(d.Dot(p.GetUpVector())) <= PORTAL_HALF_H) return p;
	}
	return null;
}

// Finds the linked portal based on the portal's team.
function OtherPortal(portal) {
	for (local p = null; p = Entities.FindByClassname(p, "prop_portal");)
	{
		if (p == portal) continue;
		if ( portal.GetTeam() != p.GetTeam() ) continue;
		if (!IsActive(p)) continue; // unlinked: the partner isn't placed
		
		return p;
	}
	
	return null;
}

// Entry -> exit: turn 180 degrees around the portal's up axis.
function Through(v, a, b) {
	return b.GetForwardVector() * -v.Dot(a.GetForwardVector())
		+ b.GetLeftVector() * -v.Dot(a.GetLeftVector())
		+ b.GetUpVector() * v.Dot(a.GetUpVector());
}

// Returns where the main beam should end: the wall hit, or the point on the portal's surface.
function LaserExit(hit, dir) {
	local a = PortalAt(hit);
	local b = a ? OtherPortal(a) : null;
	if (!b) { SetExit(false); return hit; }

	// The trace passes through the portal to the wall behind it; step back to the portal's own plane.
	local n = a.GetForwardVector();
	local entry = hit + dir * ((a.GetOrigin() - hit).Dot(n) / dir.Dot(n));

	local out_dir = Through(dir, a, b);
	local start   = b.GetOrigin() + Through(entry - a.GetOrigin(), a, b) + out_dir * 1.0; // nudge along the beam, not the normal

	laser_exit.SetOrigin(start);
	hit_exit.SetOrigin(Trace(start, out_dir));
	SetExit(true);
	return entry;
}

// Called when the game_ui entity activates
function OnGrab() {
	if (!activator) return;
	
	grab.SetTeam( activator.GetTeam() );
	
	if ( activator.GetTeam() == 0 ) // In singleplayer, the player doesn't have a name.
	{
		EntFireByHandle( eye_measure, "SetMeasureTarget", "!player", 0.00, activator, activator );	
	}
	else
	{
		EntFireByHandle( eye_measure, "SetMeasureTarget", activator.GetName(), 0.00, activator, activator );	
	}
}

// gun_grab is held while mounted; +use drops it, and the drop dismounts.
function GrabHome() {
	if (!gun) Resolve();
	if (!grab) return;
	grab.SetOrigin(pivot.GetOrigin());
	grab.SetAngles(0, 0, 0);
	grab.SetVelocity(Vector(0, 0, 0));	
	EntFireByHandle(grab, "DisableMotion", "", 0, null, null);
	
	// Maybe not the best place to put these, but GrabHome is called when the game_ui turns off.
	grab.SetTeam( 0 );
	EntFireByHandle( eye_measure, "SetMeasureTarget", "", 0.00, activator, activator );	
}

function Clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

function SetPose(ctrl, deg, lo, hi) {
	EntFireByHandle(ctrl, "SetPoseValue", ((Clamp(deg, lo, hi) - lo) / (hi - lo)).tostring(), 0, null, null);
}

function GetAimingPlayer() {

	// If there isn't a grab entity, get the first player.
	if (!grab) return Entities.FindByClassname(null, "player");

	// The grab entity's team gets set to the grabbing player's team. Find them based on that.
	for (local pl = null; pl = Entities.FindByClassname(pl, "player");)
	{
		if ( pl.GetTeam() != grab.GetTeam() ) continue;		
		return pl;
	}
	
	return null;
}

function Aim() {
	if (!gun) Resolve();
	local player = GetAimingPlayer();
	if (!gun || !player) return;

	local start = eye.GetOrigin();
	local dir   = eye.GetForwardVector();
	local hit   = start + dir * (MAX_DIST * TraceLine(start, start + dir * MAX_DIST, player));

	local to = hit - pivot.GetOrigin();
	to.Norm();

	// The barrel's neutral direction is the prop's left (studiomdl turns SMD +X into +Y).
	local up   = gun.GetUpVector();
	local fwd  = up.Cross(gun.GetForwardVector());
	local left = up.Cross(fwd);

	local x = to.Dot(fwd), y = to.Dot(left), z = to.Dot(up);
	SetPose(yaw_ctrl,   atan2(y, x) * 180.0 / PI,                     YAW_MIN,   YAW_MAX);
	SetPose(pitch_ctrl, -atan2(z, sqrt(x * x + y * y)) * 180.0 / PI,  PITCH_MIN, PITCH_MAX);
}