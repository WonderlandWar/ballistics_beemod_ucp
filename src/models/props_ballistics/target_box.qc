// Created by Crowbar 0.74

$modelname "props_ballistics/target_box.mdl"

$staticprop

$bodygroup "Body"
{
	studio "target_box_reference.smd"
}

$lod 15
{
	replacemodel "target_box_reference.smd" "target_box_reference_lod1.smd"
	nofacial
}
$lod 30
{
	replacemodel "target_box_reference.smd" "target_box_reference_lod2.smd"
	nofacial
}
$lod 90
{
	replacemodel "target_box_reference.smd" "target_box_reference_lod3.smd"
	nofacial
}

$surfaceprop "Metal_Box"

$contents "solid"

$illumposition 0 0 0

$mostlyopaque

$cdmaterials "models\props_ballistics\"

$texturegroup "skinfamilies"
{
	{ "target_box"                }		// Inactive 	clean
	{ "target_box_skin001"        }		// Inactive 	companion
	{ "target_box_skin002"        }		// Active 		clean
	{ "target_box_skin003"        }		// Inactive 	rusted
	{ "target_box_skin004"        }		// Active 		companion
	{ "target_box_skin005"        }		// Active 		rusted
	{ "target_box_bounce"         }		// Inactive 	clean		bounce
	{ "target_box_speed"          }		// Inactive 	clean		speed
	{ "target_box_skin001_bounce" }		// Inactive		companion	bounce	
	{ "target_box_skin001_speed"  }		// Inactive		clean		speed
	{ "target_box_skin002_bounce" }		// Active		clean		bounce
	{ "target_box_skin002_speed"  }		// Active 		clean		speed
}

$cbox 0 0 0 0 0 0

$bbox -18.065 -18.051 -18.033 18.07 18.056 18.046

$definebone "static_prop" "" 0 0 0 0 0 0 0 0 0 0 0 0


$sequence "idle" {
	"target_box_anims\idle.smd"
	activity "ACT_IDLE" 1
	fadein 0.2
	fadeout 0.2
	fps 30
}

$collisionmodel "target_box_physics.smd"
{
	$mass 40
	$inertia 1
	$damping 0
	$rotdamping 0
	$rootbone " "

}

$keyvalues
{
	prop_data 
	{
		"base" "Metal.small"
	}
}
