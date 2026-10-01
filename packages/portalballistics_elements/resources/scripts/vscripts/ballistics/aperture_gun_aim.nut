// Ballistics Aperture Gun: aims the gun at the mounted player's crosshair.

// Pose ranges of aperture_gun_p2.mdl. Yaw + = left, pitch - = up.
YAW_MIN   <- -90.0;  YAW_MAX   <- 90.0;
PITCH_MIN <- -80.0;  PITCH_MAX <- 30.0;
MAX_DIST  <- 8192.0;

local me = self.GetName();
PREFIX <- me.slice(0, me.len() - "gun_script".len());

gun <- null;

DEBUG     <- true;
LOG_EVERY <- 20;
aim_calls <- 0;
function Log(msg) { if (DEBUG) printl("[aperture_gun] " + msg); }

Log("script loaded on '" + me + "', prefix '" + PREFIX + "'");

function Resolve() {
	gun        = Entities.FindByName(null, PREFIX + "gun");
	eye        <- Entities.FindByName(null, PREFIX + "gun_eye");
	pivot      <- Entities.FindByName(null, PREFIX + "gun_pivot");
	hit_target <- Entities.FindByName(null, PREFIX + "gun_hit");
	yaw_ctrl   <- Entities.FindByName(null, PREFIX + "gun_yaw");
	pitch_ctrl <- Entities.FindByName(null, PREFIX + "gun_pitch");
	grab       <- Entities.FindByName(null, PREFIX + "gun_grab");
	if (!gun) printl("[aperture_gun] can't find " + PREFIX + "gun");
	Log("Resolve: gun=" + gun + " eye=" + eye + " pivot=" + pivot + " hit=" + hit_target
		+ " yaw=" + yaw_ctrl + " pitch=" + pitch_ctrl + " grab=" + grab);
	if (gun) muzzle_id <- gun.LookupAttachment("muzzle");
	if (gun) Log("muzzle attachment id=" + muzzle_id + " (0 = not found)");
}

// The muzzle attachment has no QC "rotate": the barrel runs along its +Y.
function AnglesLeft(ang) {
	local p = ang.x * PI / 180.0, y = ang.y * PI / 180.0, r = ang.z * PI / 180.0;
	return Vector(sin(r) * sin(p) * cos(y) - cos(r) * sin(y), sin(r) * sin(p) * sin(y) + cos(r) * cos(y), sin(r) * cos(p));
}

// gun_grab is held while mounted; +use drops it, and the drop dismounts.
function Grabbed() { Log("gun_grab picked up"); }
function Dropped() { Log("gun_grab dropped"); }
function GrabHome() {
	if (!gun) Resolve();
	if (!grab) return;
	grab.SetOrigin(pivot.GetOrigin());
	grab.SetAngles(0, 0, 0);
	grab.SetVelocity(Vector(0, 0, 0));
	EntFireByHandle(grab, "DisableMotion", "", 0, null, null);
}

function Clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

function SetPose(ctrl, deg, lo, hi) {
	EntFireByHandle(ctrl, "SetPoseValue", ((Clamp(deg, lo, hi) - lo) / (hi - lo)).tostring(), 0, null, null);
}

function Aim() {
	if (!gun) Resolve();
	local player = Entities.FindByClassname(null, "player");
	local log = (aim_calls++ % LOG_EVERY) == 0;
	if (!gun || !player) {
		if (log) Log("Aim #" + aim_calls + " skipped: gun=" + gun + " player=" + player);
		return;
	}

	local start = eye.GetOrigin();
	local dir   = eye.GetForwardVector();
	local frac  = TraceLine(start, start + dir * MAX_DIST, player);
	local hit   = start + dir * (MAX_DIST * frac);
	hit_target.SetOrigin(hit);

	local to = hit - pivot.GetOrigin();
	to.Norm();

	// The barrel's neutral direction is the prop's left (studiomdl turns SMD +X into +Y).
	local up   = gun.GetUpVector();
	local fwd  = up.Cross(gun.GetForwardVector());
	local left = up.Cross(fwd);

	local x = to.Dot(fwd), y = to.Dot(left), z = to.Dot(up);
	local yaw   = atan2(y, x) * 180.0 / PI;
	local pitch = -atan2(z, sqrt(x * x + y * y)) * 180.0 / PI;

	SetPose(yaw_ctrl,   yaw,   YAW_MIN,   YAW_MAX);
	SetPose(pitch_ctrl, pitch, PITCH_MIN, PITCH_MAX);

	// Green: intended aim. Red: muzzle attachment's actual aim.
	if (DEBUG) DebugDrawLine(pivot.GetOrigin(), hit, 0, 255, 0, true, 0.06);
	local m_org = null, m_ang = null;
	if (DEBUG) {
		m_org = gun.GetAttachmentOrigin(muzzle_id);
		m_ang = gun.GetAttachmentAngles(muzzle_id);
		local m_dir  = AnglesLeft(m_ang);
		local m_frac = TraceLine(m_org, m_org + m_dir * MAX_DIST, player);
		DebugDrawLine(m_org, m_org + m_dir * (MAX_DIST * m_frac), 255, 0, 0, true, 0.06);
	}
	if (log) Log("Aim #" + aim_calls + " eye=" + start + " dir=" + dir + " frac=" + frac
		+ " hit=" + hit + " pivot=" + pivot.GetOrigin() + " yaw=" + yaw + " pitch=" + pitch
		+ " muzzle=" + m_org + " muzzle_ang=" + m_ang);
}

function Dismount() {
	Log("Dismount after " + aim_calls + " Aim calls");
	aim_calls = 0;
}
