# res://scripts/audio_manager.gd (Autoload: audio_manager)
extends Node

const MUSIC_BUS := "Music"
const MIN_DB := -40.0
const MAX_DB := 0.0

var music_player: AudioStreamPlayer
var volume_db: float = -6.0
var muted: bool = false

func _ready() -> void:
	# ВАЖНО: чтобы музыка играла даже когда игра на паузе (журнал/пауза)
	process_mode = Node.PROCESS_MODE_ALWAYS

	# создаём плеер
	music_player = AudioStreamPlayer.new()
	music_player.bus = MUSIC_BUS
	music_player.autoplay = false
	music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music_player)

	# на всякий: если вдруг bus не найден — упадёт громкость в Master
	if AudioServer.get_bus_index(MUSIC_BUS) == -1:
		push_warning("AudioManager: Bus '%s' not found. Create it in Audio panel." % MUSIC_BUS)

	set_volume_db(volume_db)

# ---------------- MUSIC ----------------
func play_music(stream: AudioStream, loop: bool = true, restart_if_same: bool = false) -> void:
	if stream == null:
		push_warning("AudioManager: play_music got null stream")
		return

	# если тот же трек уже стоит
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

# Godot 4: loop задаётся на самом stream (у ogg/wav)
func _apply_loop(stream: AudioStream, loop: bool) -> void:
	# У AudioStreamOggVorbis есть loop
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	# У AudioStreamWAV тоже есть loop_mode
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED

# ---------------- VOLUME ----------------
func set_volume_db(db: float) -> void:
	volume_db = clamp(db, MIN_DB, MAX_DB)

	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if idx == -1:
		return

	if muted:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, volume_db)

func get_volume_db() -> float:
	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if idx == -1:
		return volume_db
	return AudioServer.get_bus_volume_db(idx)

func set_muted(value: bool) -> void:
	muted = value
	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, muted)

func toggle_mute() -> void:
	set_muted(not muted)
