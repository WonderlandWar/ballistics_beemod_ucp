IncludeScript("BEE2/tdp_patterns", this)
turret_color_str <- "255 255 255"

function on_spawned() {
	local turret = Entities.FindByName(null, self.GetName().slice(0, -6) + "turret")
	if (turret != null) tdp_turret_model(turret, tdp_pattern_rank())
}
