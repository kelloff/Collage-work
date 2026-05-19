# res://scripts/audio_manager.gd (Autoload: audio_manager)
extends Node

const MASTER_BUS := "Master"
const MUSIC_BUS := "Music"
const MIN_DB := -40.0
const MAX_DB := 0.0

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "audio"

var music_player: AudioStreamPlayer
var master_volume_db: float = 0.0
var music_volume_db: float = -6.0
var muted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	music_player = AudioStreamPlayer.new()
	music_player.bus = MUSIC_BUS
	music_player.autoplay = false
	music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music_player)

	if AudioServer.get_bus_index(MUSIC_BUS) == -1:
		push_warning("AudioManager: Bus '%s' not found. Create it in Audio panel." % MUSIC_BUS)

	_load_settings()
	_apply_all_volumes()

# ---------------- SETTINGS ----------------
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return

	if cfg.has_section_key(SECTION, "master_volume_db"):
		master_volume_db = float(cfg.get_value(SECTION, "master_volume_db"))
	if cfg.has_section_key(SECTION, "music_volume_db"):
		music_volume_db = float(cfg.get_value(SECTION, "music_volume_db"))

	muted = bool(cfg.get_value(SECTION, "music_muted", muted))
	master_volume_db = clampf(master_volume_db, MIN_DB, MAX_DB)
	music_volume_db = clampf(music_volume_db, MIN_DB, MAX_DB)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, "master_volume_db", master_volume_db)
	cfg.set_value(SECTION, "music_volume_db", music_volume_db)
	cfg.set_value(SECTION, "music_muted", muted)
	cfg.save(SETTINGS_PATH)


func _apply_all_volumes() -> void:
	var master_idx := AudioServer.get_bus_index(MASTER_BUS)
	if master_idx != -1:
		AudioServer.set_bus_mute(master_idx, muted)
		if not muted:
			AudioServer.set_bus_volume_db(master_idx, master_volume_db)

	var music_idx := AudioServer.get_bus_index(MUSIC_BUS)
	if music_idx != -1:
		if muted:
			AudioServer.set_bus_mute(music_idx, true)
		else:
			AudioServer.set_bus_mute(music_idx, false)
			AudioServer.set_bus_volume_db(music_idx, music_volume_db)

# ---------------- MUSIC ----------------
func play_music(stream: AudioStream, loop: bool = true, restart_if_same: bool = false) -> void:
	if stream == null:
		push_warning("AudioManager: play_music got null stream")
		return

	if music_player.stream == stream:
		if restart_if_same:
			music_player.stop()
			music_player.play()
		return

	music_player.stop()
	music_player.stream = stream
	_apply_loop(stream, loop)
	music_player.play()


func stop_music() -> void:
	if music_player:
		music_player.stop()


func is_playing() -> bool:
	return music_player != null and music_player.playing


func _apply_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED

# ---------------- VOLUME ----------------
func set_master_volume_db(db: float) -> void:
	master_volume_db = clampf(db, MIN_DB, MAX_DB)
	_apply_all_volumes()
	_save_settings()


func get_master_volume_db() -> float:
	var idx := AudioServer.get_bus_index(MASTER_BUS)
	if idx == -1:
		return master_volume_db
	return AudioServer.get_bus_volume_db(idx)


func set_music_volume_db(db: float) -> void:
	music_volume_db = clampf(db, MIN_DB, MAX_DB)
	_apply_all_volumes()
	_save_settings()


func get_music_volume_db() -> float:
	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if idx == -1:
		return music_volume_db
	return AudioServer.get_bus_volume_db(idx)


## Совместимость со старым API (только музыка).
func set_volume_db(db: float) -> void:
	set_music_volume_db(db)


func get_volume_db() -> float:
	return get_music_volume_db()


func set_muted(value: bool) -> void:
	muted = value
	_apply_all_volumes()
	_save_settings()


func toggle_mute() -> void:
	set_muted(not muted)
