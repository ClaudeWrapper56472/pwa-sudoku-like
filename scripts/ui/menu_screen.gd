class_name MenuScreen
extends Control
## Title screen. One button: it carries on from a suspended level if there is one,
## and otherwise starts the level the player is up to.

## One button, two meanings. The menu does not decide which -- it just reports the
## press and lets the router work out whether there is a game to resume.
signal play_requested()

@onready var _play_button: Button = %PlayButton
@onready var _stats_label: RichTextLabel = %StatsLabel
@onready var _mascot: CatMascot = %Mascot



func _ready() -> void:
	_play_button.pressed.connect(func() -> void: play_requested.emit())
	SaveManager.stats_changed.connect(refresh)
	SaveManager.session_available.connect(func(_available: bool) -> void: refresh())
	refresh()


func refresh() -> void:
	if SaveManager.has_session():
		var session := SaveManager.session()
		var seconds := int(float(session.get("elapsed", 0.0)))
		_play_button.text = "Continue level %d  ·  %d:%02d" % [
			int(session.get("level", 1)), seconds / 60, seconds % 60,
		]
	else:
		_play_button.text = "Play level %d" % SaveManager.current_level()
	_stats_label.text = _stats_text()


func _stats_text() -> String:
	var lines := PackedStringArray()
	var streak: Dictionary = SaveManager.stats().get("streak", {})
	var level := SaveManager.current_level()
	lines.append("[b]Progress[/b]")
	lines.append("On level %d  ·  %s %d×%d" % [
		level, CatGrid.tier_name(LevelLadder.tier_for(level)),
		LevelLadder.size_for(level), LevelLadder.size_for(level),
	])
	lines.append("%d level%s finished" % [
		SaveManager.levels_completed(), "" if SaveManager.levels_completed() == 1 else "s",
	])
	var run := int(streak.get("current", 0))
	var best_run := int(streak.get("best", 0))
	if run > 0:
		lines.append("%d in a row (best %d)" % [run, best_run])
	elif best_run > 0:
		lines.append("Best run %d in a row" % best_run)
	var next_size := LevelLadder.next_step_up(level)
	if next_size > 0:
		lines.append("Bigger board at level %d" % next_size)
	# RichTextLabel has no alignment property; centring is bbcode.
	return "[center]%s[/center]" % "\n".join(lines)

