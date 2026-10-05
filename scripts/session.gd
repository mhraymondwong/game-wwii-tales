extends Node
## Hotseat vs computer. Survives scene changes.

var vs_cpu: bool = false
## 1..6. 再玩一次 reloads the battle and keeps this level.
var level: int = 1
## Hotseat battle on user://custom_map.json. 試玩 sets this.
var play_custom: bool = false
