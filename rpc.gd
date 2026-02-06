extends Node2D

func _ready():
	DiscordRPC.app_id = 1469123365712433163

	await get_tree().create_timer(0.2).timeout

	print("Discord working: ", DiscordRPC.get_is_discord_working())

	DiscordRPC.details = "by PoodleGames"
	DiscordRPC.state = "Watching life evolve"
	DiscordRPC.start_timestamp = int(Time.get_unix_time_from_system())

	DiscordRPC.refresh()
