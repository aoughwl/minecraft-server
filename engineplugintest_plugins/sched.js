var repeats = 0;
function start() {
  hostv("schedule_after", 3);
  hostv("schedule_repeat", 2);
  hostS("server_log", "online " + hostv("player_online", "Nobody"));
}
function on_task() {
  var id = hostv("event_num", "id");
  hostS("server_log", "task ran " + id);
  if (id == 2) { repeats++; if (repeats == 2) host("schedule_cancel", 2); }
}
