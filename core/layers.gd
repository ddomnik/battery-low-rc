class_name Layers
## Physics and render layer bits (§5.1). Names match project settings → layer_names.

const WORLD := 1        # layer 1: static geometry
const CARS := 2         # layer 2: car bodies
const PICKUPS := 4      # layer 3: item boxes (Area3D)
const PROJECTILES := 8  # layer 4: reserved (projectiles use manual sweeps)
const TRIGGERS := 16    # layer 5: charging pads (Area3D)
const RENDER_WORLD := 1 # render layer 1
const RENDER_CARS := 2  # render layer 2
