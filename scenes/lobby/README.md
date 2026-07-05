# scenes/lobby/ — multiplayer entry screens

| Scene | Role |
|---|---|
| `LanLobby.tscn` | Host/join on the local network (ENet); embeds DeckSelect |
| `OnlinePlay.tscn` | Online hub: choose private room vs public lobby |
| `OnlineLobby.tscn` | Private room (code-based) via relay/dedicated server; embeds DeckSelect |
| `PublicLobby.tscn` | Public room list + queue (with lobby-bot fallback); embeds DeckSelect |

## Screen flow

```
MainMenu ─┬─ LAN Multiplayer ──→ LanLobby ──────────────┐
          └─ Online Multiplayer → OnlinePlay ─┬→ OnlineLobby ──┼→ GameBoard
                                              └→ PublicLobby ──┘
(Back: LanLobby→MainMenu, OnlineLobby/PublicLobby→OnlinePlay→MainMenu;
 post-game "play again" returns to PublicLobby)
```

All connection state lives in the `NetworkManager` autoload
(`scripts/net/README.md`) — these scenes are thin UI over its signals
(`game_starting`, `server_seated`, `server_lobby_update`,
`connection_failed`, `version_mismatch`, …). The match itself starts when
NetworkManager loads `scenes/board/GameBoard.tscn`.
