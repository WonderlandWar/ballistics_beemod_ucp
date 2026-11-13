PATTERN_SETS <- [
	[
		"models/npcs/turret/turret_colorable.mdl",
		"models/npcs/turret/turret_colorable2.mdl",
		"models/npcs/turret/turret_colorable3.mdl"
	],
	[
		"models/npcs/turret/turret_p1_colorable.mdl",
		"models/npcs/turret/turret_p1_colorable2.mdl"
	]
]
DEFAULT_TURRETS <- [
	"models/npcs/turret/turret_default_fast.mdl",
	"models/npcs/turret/turret_p1_default_fast.mdl"
]
WHITE <- "255 255 255"

function tdp_number(name) {
	local dash = name.find("-")
	local i = dash
	while (i > 0 && name[i - 1] >= '0' && name[i - 1] <= '9') i--
	return name.slice(i, dash).tointeger()
}

function tdp_is_member(name) {
	return (name.find("tdrpp") == 0 || name.find("tdturr") == 0) && name.len() > 7 && name.slice(-7) == "-script"
}

function tdp_pattern_rank() {
	local my_name = self.GetName()
	local mine = tdp_number(my_name)
	local rank = 0
	for (local ent = Entities.FindByClassname(null, "logic_script"); ent != null; ent = Entities.FindByClassname(ent, "logic_script")) {
		local name = ent.GetName()
		if (!tdp_is_member(name)) continue
		local n = tdp_number(name)
		if (n < mine || (n == mine && name < my_name)) {
			local scope = ent.GetScriptScope()
			if (scope != null && scope.turret_color_str != WHITE) rank++
		}
	}
	return rank
}

function tdp_turret_model(turret, rank) {
	foreach (i, set in PATTERN_SETS) {
		if (turret.GetModelName() == set[0]) {
			local model = turret_color_str == WHITE ? DEFAULT_TURRETS[i] : set[rank % set.len()]
			if (model != set[0]) turret.SetModel(model)
			return
		}
	}
}
