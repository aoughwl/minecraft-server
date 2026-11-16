// The plugin tools/mcbot_engine.py drives: copy to <server cwd>/plugins/live/main.js.
function on_player_join() {
  var n = hostv("event_str", "player");
  hostv("player_message_to", n, "engine welcome " + n);
}

function on_player_chat() {
  var n = hostv("event_str", "player");
  var m = hostv("event_str", "message");
  if (m == "gm1") { hostv("player_set_gamemode", n, 1); host("event_cancel"); return; }
  if (m == "tp") { hostv("player_teleport", n, 100, 80, 100); host("event_cancel"); return; }
  if (m == "pos") {
    hostv("player_message_to", n, "engine pos " + Math.floor(hostv("player_pos", n, "x")));
    host("event_cancel");
    return;
  }
  if (m == "bye") { hostv("player_kick", n, "engine kick"); host("event_cancel"); return; }
  if (m.charAt(0) == "x") { host("event_cancel"); }
}

// events mode (mcbot --play --op --engine-plugin events): the plugin reports what it saw back to the player in chat, and a
// repeating task broadcasts to everyone
var moves = 0;
function on_player_move() {
  moves++;
  if (moves == 1) hostv("player_message_to", hostv("event_str", "player"), "engine saw a move");
}

function on_block_place() {
  hostv("player_message_to", hostv("event_str", "player"), "engine saw place " + hostv("event_str", "placed"));
}

function start() { hostv("schedule_repeat", 40); }

function on_task() { hostS("server_broadcast", "engine broadcast"); }
