class_name MusicDirector
extends Node

# 两套原创配乐共用 Music 总线，沿用旧曲风的设置键。
const AudioCfgM = preload("res://scripts/audio.gd")

const TRACK_TITLES := {
	"sakura": {
		"home": "樱华·午后的窗台",
		"draft": "静静落樱",
		"battle": "樱荫对弈",
		"tense": "晚风未眠",
	},
	"classic": {
		"home": "月下琴房",
		"draft": "窗边夜读",
		"battle": "夜色棋局",
		"tense": "暮云渐沉",
	},
}
const RESULT_FILES := {"result_win": "result_win", "result_lose": "result_lose", "result_draw": "result_lose"}
const RESULT_TITLES := {"result_win": "晴空回信", "result_lose": "收局·余温", "result_draw": "收局·暮色"}
const FADE_SEC := 1.35
const RESULT_FADE_SEC := 0.68
const QUIET_GAIN := 0.0001
const TENSE_MIN_MS := 9000

var current_scene := ""
var _players: Array[AudioStreamPlayer] = []
var _active_idx := 0
var _transition: Tween
var _release_timer: SceneTreeTimer
var _tense_since_ms := 0


static func style_key() -> String:
	return "classic" if String(AudioCfgM.get_v("bgm_style")) == "classic" else "sakura"


static func style_label() -> String:
	return "🌸 樱华轻音" if style_key() == "sakura" else "🌙 月下琴房"


static func track_title(scene: String = "home") -> String:
	if RESULT_TITLES.has(scene):
		return String(RESULT_TITLES[scene])
	var titles: Dictionary = TRACK_TITLES[style_key()]
	return String(titles.get(scene, titles["home"]))


func cycle_style() -> String:
	AudioCfgM.set_v("bgm_style", "classic" if style_key() == "sakura" else "sakura")
	if not RESULT_FILES.has(current_scene):
		var scene := current_scene if current_scene != "" else "home"
		current_scene = ""
		play_scene(scene)
	return style_label()


func _ready() -> void:
	AudioCfgM.ensure()
	add_to_group("music_director")
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		add_child(player)
		_players.append(player)


func _exit_tree() -> void:
	_stop_all()
	for player in _players:
		if is_instance_valid(player):
			player.stream = null


func play_scene(scene: String) -> void:
	if scene != "off" and not RESULT_FILES.has(scene) and not TRACK_TITLES["sakura"].has(scene):
		return
	# 刚进入残局时保持片刻，避免一次护甲或治疗反复触发主题切换。
	if scene == "battle" and current_scene == "tense":
		var remaining := TENSE_MIN_MS - (Time.get_ticks_msec() - _tense_since_ms)
		if remaining > 0:
			if _release_timer == null:
				_release_timer = get_tree().create_timer(remaining / 1000.0, true, false, true)
				_release_timer.timeout.connect(_resume_battle, CONNECT_ONE_SHOT)
			return
	_cancel_release()
	if scene == current_scene:
		return
	current_scene = scene
	if scene == "off":
		_stop_all()
		return
	if scene == "tense":
		_tense_since_ms = Time.get_ticks_msec()
	if DisplayServer.get_name() == "headless":
		return

	var stream := _stream_for(scene)
	if stream == null:
		_stop_all()
		return
	_crossfade(stream, RESULT_FADE_SEC if RESULT_FILES.has(scene) else FADE_SEC)


func _resume_battle() -> void:
	_release_timer = null
	if is_inside_tree():
		play_scene("battle")


func _cancel_release() -> void:
	if _release_timer != null and _release_timer.timeout.is_connected(_resume_battle):
		_release_timer.timeout.disconnect(_resume_battle)
	_release_timer = null


func _stop_all() -> void:
	_cancel_release()
	if _transition != null and _transition.is_valid():
		_transition.kill()
	for player in _players:
		if is_instance_valid(player):
			player.stop()


func _set_gain(gain: float, player: AudioStreamPlayer) -> void:
	player.volume_db = linear_to_db(maxf(gain, QUIET_GAIN))


func _crossfade(stream: AudioStreamOggVorbis, duration: float) -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()

	# 连续切换场景时保留更响的那一路作为淡出起点。
	var old := _players[_active_idx]
	var next := _players[1 - _active_idx]
	if next.playing and (not old.playing or next.volume_db > old.volume_db):
		var previous := old
		old = next
		next = previous
	else:
		_active_idx = 1 - _active_idx
	next.stop()
	next.stream = stream
	_set_gain(QUIET_GAIN, next)
	next.play()

	_transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_method(_set_gain.bind(next), QUIET_GAIN, 1.0, duration)
	if old.playing:
		_transition.tween_method(_set_gain.bind(old), db_to_linear(old.volume_db), QUIET_GAIN, duration)
		_transition.chain().tween_callback(old.stop)


func _stream_for(scene: String) -> AudioStreamOggVorbis:
	var prefix := "sakura" if style_key() == "sakura" else "moon"
	var stem := String(RESULT_FILES.get(scene, "%s_%s" % [prefix, scene]))
	var path := "res://assets/bgm/%s.ogg" % stem
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStreamOggVorbis
	if stream != null:
		stream.loop = not RESULT_FILES.has(scene)
	return stream
