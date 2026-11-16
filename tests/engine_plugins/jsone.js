// A tiny JavaScript plugin for the plugin manager's test, written with the SDK: registers /jsone, cancels chat that starts with z, and logs.
var runs = 0;

command("jsone", "A JavaScript command", 0, function (c) {
  runs++;
  server.log("jsone cmd " + c.name + ":" + c.rawArgs + " run " + runs);
});

on(ChatEvent, function (e) {
  if (e.message.charAt(0) == "z") e.cancel();
});

onEnable(function () { server.log("jsone started"); });
onDisable(function () { server.log("jsone stopped"); });
