class_name AudioDirector
extends Node
## App-wide audio, owned by the Game autoload (Game.audio): mixer buses, background music (tracks rotate when
## one ends, across menus and matches), interface sounds and positional one-shots.

const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const BUS_ENGINE := &"Engine"
const MUSIC_DB := -10.0
const SFX_DB := 0.0
const ENGINE_DB := -4.0
const UNIT_SIZE := 30.0              # 3D sounds stay loud at camera distance (the camera is ~50 m away)

var bank: SoundBank = SoundBank.new()
## False with the Dummy driver (headless runs): nothing is played, which also avoids playbacks the dummy driver
## never releases at exit.
var enabled: bool = true

var _music: AudioStreamPlayer
var _tracks: Array[AudioStream] = []
var _track_index: int = 0

func _ready() -> void:
	enabled = AudioServer.get_driver_name() != "Dummy"
	_ensure_bus(BUS_MUSIC, MUSIC_DB)
	_ensure_bus(BUS_SFX, SFX_DB)
	_ensure_bus(BUS_ENGINE, ENGINE_DB)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = BUS_MUSIC
	_music.finished.connect(_play_next_track)
	add_child(_music)
	if enabled:
		_tracks = bank.music_tracks()
		_play_next_track()

## Non-positional sound (menus, countdown).
func play_ui(kind: StringName, volume_db: float = 0.0) -> void:
	if not enabled:
		return
	var stream := bank.next(kind)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = BUS_SFX
	p.volume_db = volume_db
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()

## Positional one-shot at a world position; frees itself when done.
func play_at(kind: StringName, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled:
		return
	var stream := bank.next(kind)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = BUS_SFX
	p.unit_size = UNIT_SIZE
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	add_child(p)
	p.global_position = pos
	p.play()

func _play_next_track() -> void:
	if _tracks.is_empty():
		return
	_music.stream = _tracks[_track_index % _tracks.size()]
	_track_index += 1
	_music.play()

func _ensure_bus(bus_name: StringName, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus_name), volume_db)
