// Ballistics Aperture Gun: aims the gun at the mounted player's crosshair.

// Pose ranges of aperture_gun_p2.mdl. Yaw + = left, pitch - = up.
YAW_MIN   <- -90.0;  YAW_MAX   <- 90.0;
PITCH_MIN <- -80.0;  PITCH_MAX <- 30.0;
MAX_DIST  <- 8192.0;

local me = self.GetName();
PREFIX <- me.slice(0, me.len() - "gun_script".len());

gun <- null;

function Resolve() {
	gun        = Entities.FindByName(null, PREFIX + "gun");
	eye        <- Entities.FindByName(null, PREFIX + "gun_eye");
	pivot      <- Entities.FindByName(null, PREFIX + "gun_pivot");
	hit_target <- Entities.FindByName(null, PREFIX + "gun_hit");
	yaw_ctrl   <- Entities.FindByName(null, PREFIX + "gun_yaw");
	pitch_ctrl <- Entities.FindByName(null, PREFIX + "gun_pitch");
	grab       <- Entities.FindByName(null, PREFIX + "gun_grab");
}

// gun_grab is held while mounted; +use drops it, and the drop dismounts.
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
	if (!gun || !player) return;

	local start = eye.GetOrigin();
	local dir   = eye.GetForwardVector();
	local hit   = start + dir * (MAX_DIST * TraceLine(start, start + dir * MAX_DIST, player));
	hit_target.SetOrigin(hit);

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
