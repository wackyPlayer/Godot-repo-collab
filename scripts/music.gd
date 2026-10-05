extends Node
## Autoloaded as "Music": keeps the soundtrack playing across scene changes and
## crossfades when a different track is requested.
##   "keep"   - Glitcher, "Dyalla": the prologue and floors 2-4.
##   "finale" - "Final Boss" by Evening Telecast: floor 5 and the ending.

const TRACKS := {
	"keep": preload("res://assets/music/dyalla.mp3"),
	"finale": preload("res://assets/music/evening_telecast.mp3"),
}
const VOLUME_DB := -10.0
const SILENT_DB := -60.0

var players: Array[AudioStreamPlayer] = []
var active := 0
var current := ""
var fading: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in range(2):
		var player := AudioStreamPlayer.new()
		player.volume_db = SILENT_DB
		add_child(player)
		players.append(player)
	for stream: AudioStreamMP3 in TRACKS.values():
		stream.loop = true

func play(track: String, fade := 1.5) -> void:
	if track == current:
		return
	current = track
	# Headless runs (tests, exports) have no sound device to play to.
	if AudioServer.get_driver_name() == "Dummy":
		return
	var outgoing := players[active]
	active = 1 - active
	var incoming := players[active]
	incoming.stream = TRACKS[track]
	incoming.volume_db = SILENT_DB
	incoming.play()
	# A fade still running would stop the player this one just started.
	if fading:
		fading.kill()
	fading = create_tween().set_parallel()
	fading.tween_property(incoming, "volume_db", VOLUME_DB, fade)
	fading.tween_property(outgoing, "volume_db", SILENT_DB, fade)
	fading.chain().tween_callback(outgoing.stop)

func _exit_tree() -> void:
	# Release the playbacks before the engine shuts down.
	for player in players:
		player.stop()
		player.stream = null
