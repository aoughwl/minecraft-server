function on_player_chat() {
  hostS("event_set_message", hostv("event_str", "player") + ": " + hostv("event_str", "message"));
}
function on_player_command() { hostS("server_log", "command " + hostv("event_str", "message")); }
