## Port of upstream/config/src/player_data.rs

type
  PlayerDataConfig* = object
    savePlayerData*: bool
    savePlayerCronInterval*: uint64

proc defaultPlayerDataConfig*(): PlayerDataConfig =
  PlayerDataConfig(savePlayerData: true, savePlayerCronInterval: 300'u64)
