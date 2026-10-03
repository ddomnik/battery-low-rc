extends Node
## Net autoload: transport lives here only.
## POC: the default OfflineMultiplayerPeer → we are the server, peer id 1.
## Later: host_lan(port), join_lan(address, port) using ENetMultiplayerPeer; LAN discovery via UDP broadcast.

func is_authority() -> bool:
	return multiplayer.is_server()

func local_peer_id() -> int:
	return multiplayer.get_unique_id()
