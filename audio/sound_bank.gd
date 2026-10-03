class_name SoundBank
extends RefCounted
## Finds sound files by name under res://assets/sounds and hands out their variations in rotation
## (name1, name2, name3, name1, …). Purely cosmetic, so it keeps its own counters (no Match.rng).
## One instance lives in Game.audio, so the loaded streams are released when the game closes.

const SOUND_DIR := "res://assets/sounds/"
const MUSIC_DIR := "res://assets/music/"

## Sound kind → file stem. Every file named <stem><number>.wav is one variation; an exact name picks one file.
const FILES := {
	&"pickup": "bright_magical_item",
	&"perfect_landing": "reward",
	&"bump": "cartoon_crash",
	&"wall": "cartoon_slam",
	&"explosion": "cartoon_small_explosion",
	&"splash": "balloon_splash",
	&"launch": "small_rocket_launch",
	&"countdown": "countdown_beep",
	&"go": "horn",
	&"ui_click": "button",
	&"engine": "motor2",        # one engine sound for every car (14 s, loops)
	&"engine_air": "motor4",    # higher, free-revving motor while airborne
	&"boost": "turbo",
	&"drift": "tire_squeak",
}

var _variants: Dictionary = {}   # kind → Array[AudioStream]
var _next: Dictionary = {}       # kind → index of the next variation
var _loops: Dictionary = {}      # kind → looping copy of the first variation

## The next variation of a sound kind, in rotation. Null if no file matches.
func next(kind: StringName) -> AudioStream:
	var list := _variants_of(kind)
	if list.is_empty():
		return null
	var i: int = _next.get(kind, 0)
	_next[kind] = (i + 1) % list.size()
	return list[i]

## A looping copy of the kind's first variation (engine, boost).
func looping(kind: StringName) -> AudioStream:
	if _loops.has(kind):
		return _loops[kind]
	var list := _variants_of(kind)
	var stream: AudioStream = null
	if not list.is_empty():
		var wav := list[0] as AudioStreamWAV
		if wav != null:
			wav = wav.duplicate() as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
			stream = wav
		else:
			stream = list[0]
	_loops[kind] = stream
	return stream

func music_tracks() -> Array[AudioStream]:
	var tracks: Array[AudioStream] = []
	for path in _audio_files(MUSIC_DIR):
		tracks.append(load(path) as AudioStream)
	return tracks

func _variants_of(kind: StringName) -> Array[AudioStream]:
	if _variants.has(kind):
		return _variants[kind]
	var list: Array[AudioStream] = []
	var wanted: String = FILES.get(kind, "")
	if wanted != "":
		for path in _audio_files(SOUND_DIR):
			var base := path.get_file().get_basename()
			if base == wanted or (base.begins_with(wanted) and base.substr(wanted.length()).is_valid_int()):
				list.append(load(path) as AudioStream)
	if list.is_empty() and wanted != "":
		push_warning("SoundBank: no sound files for '%s' (%s*)" % [kind, wanted])
	_variants[kind] = list
	return list

## Sorted audio file paths in a folder (works in exported builds, where files carry an .import suffix).
static func _audio_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		var f := file.trim_suffix(".import").trim_suffix(".remap")
		if f.get_extension() in ["wav", "ogg", "mp3"] and not out.has(dir + f):
			out.append(dir + f)
	out.sort()
	return out
