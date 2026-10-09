class_name FluidPresets
## Fluid kinds for "fluid" map objects (lakes, puddles, lava…): default values for everything a map can set,
## plus the look that only the preset decides (glow, waves, surface shine, ambient particles, track look).

const NAMES: Array[String] = ["water", "lava", "mud", "acid"]

## Per preset. Map-settable: color, opacity, damage (per 100 ms), slow (top speed × while touching), drag (1/s,
## body in fluid), buoyancy (1 = a fully sunk car floats), grip (× while touching), coat (s of wet tyre tracks).
## Look only: glow (emission), crust (0..1 dark crust with glowing veins), waves (m), roughness,
## particles ("" / "bubbles" / "embers"), track_alpha.
const PRESETS := {
	"water": {"color": Color("#3E8FD6"), "opacity": 0.72, "damage": 0.0, "slow": 0.7, "drag": 0.8, "buoyancy": 0.55,
		"grip": 0.8, "coat": 3.0, "glow": 0.0, "waves": 0.06, "roughness": 0.08, "particles": "", "track_alpha": 0.45},
	"lava": {"color": Color("#FF5A1F"), "opacity": 1.0, "damage": 3.0, "slow": 0.5, "drag": 1.6, "buoyancy": 1.15,
		"grip": 0.6, "coat": 2.5, "glow": 2.4, "crust": 0.85, "waves": 0.03, "roughness": 0.6, "particles": "embers", "track_alpha": 0.9},
	"mud": {"color": Color("#6B4A2B"), "opacity": 1.0, "damage": 0.0, "slow": 0.35, "drag": 2.5, "buoyancy": 0.3,
		"grip": 0.5, "coat": 6.0, "glow": 0.0, "waves": 0.01, "roughness": 0.45, "particles": "bubbles", "track_alpha": 0.9},
	"acid": {"color": Color("#8CE03A"), "opacity": 0.85, "damage": 1.0, "slow": 0.8, "drag": 1.0, "buoyancy": 0.5,
		"grip": 0.7, "coat": 3.0, "glow": 0.6, "waves": 0.04, "roughness": 0.15, "particles": "bubbles", "track_alpha": 0.7},
}

static func get_preset(name: String) -> Dictionary:
	return PRESETS.get(name, PRESETS["water"])
