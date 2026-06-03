## Initialises Discord Rich Presence for the Game of Life application.
##
## Requires the DiscordRPC addon to be installed and enabled.
## Place this node anywhere in the scene tree; it configures the
## presence once on startup and needs no per-frame processing.
extends Node2D


## Sets the Discord application ID, waits a short frame for the addon to
## initialise, then applies presence details and refreshes.
func _ready() -> void:
	DiscordRPC.app_id = 1469123365712433163
	await get_tree().create_timer(0.2).timeout
	DiscordRPC.details = "by PoodleGames"
	DiscordRPC.state = "Watching life evolve"
	DiscordRPC.start_timestamp = int(Time.get_unix_time_from_system())
	DiscordRPC.refresh()
