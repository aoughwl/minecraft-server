// hello-world-js: the same plugin system, in JavaScript. A small plugin next to the aowlmony one (examples/hello-world) to show that
// both languages run on the engine side by side.
//
// Install: copy this folder to <server>/plugins/hello-world-js/ (the file must be called main.js).
// The server puts the SDK (plugin_sdk/pluginsdk.js) in front of your code: `on(EventType, handler)` listens to an event, `command(...)`
// adds /name, `after` and `every` schedule work, `server` talks to the server, and the event objects are typed (docs/EVENTS.md).

var jsPings = 0;

// a chat feature next to the aowlmony plugin's: "!js" answers with a short note
on(ChatEvent, function (e) {
  if (e.message == "!js") {
    e.player.tell("This answer is written in JavaScript.");
    e.cancel();                      // the server will not broadcast it
  }
});

// events with no player work the same way
on(WeatherChangeEvent, function (e) {
  server.broadcast(e.raining ? "It started raining (JavaScript noticed)." : "The rain stopped (JavaScript noticed).");
});

command("jsping", "Answers from the JavaScript plugin", 0, function (c) {
  jsPings++;
  c.reply("pong from JavaScript (" + jsPings + " so far)");
});

command("jsinfo", "What the JavaScript plugin knows about you", 0, function (c) {
  if (c.isConsole) { c.fail("Only a player can ask."); return; }
  var p = c.sender.pos();
  c.reply(c.sender.name + ": you are at x=" + Math.floor(p.x) + " z=" + Math.floor(p.z) + ", and " + server.onlineCount() +
          " player(s) are online.");
});

onEnable(function () { server.log("hello-world-js: starting"); });
onDisable(function () { server.log("hello-world-js: stopping"); });
