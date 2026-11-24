function start() { hostS("server_log", "filter loaded"); }
function on_player_chat() {
  var m = hostv("event_str", "message");
  if (m.indexOf("spam") >= 0) { host("event_cancel"); return; }
  hostS("event_set_message", m.toUpperCase());
}
function on_player_join() { host("event_cancel"); }
function on_player_move() { if (hostv("event_num", "to_x") > 100) host("event_cancel"); }
function on_block_grow() { if (hostv("event_str", "new_block") == "minecraft:cactus") host("event_cancel"); }
function on_spawn_change() { hostS("server_log", "spawn " + hostv("event_num", "next_x")); }
function on_server_command() { if (hostv("event_str", "command") == "stop") host("event_cancel"); }
function on_block_place() { if (hostv("event_str", "placed") == "minecraft:bedrock") host("event_cancel"); }
