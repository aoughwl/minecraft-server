// hello-world-js2: a second JavaScript plugin. With each plugin in its own worker (AOE_PLUGIN_WORKERS=1) it keeps its own state and
// survives when another JavaScript plugin is unloaded or reloaded; used by tools/run_plugin_showcase.sh to show that.

var counted = 0;

command("jscount", "Count up (state of this plugin only)", 0, function (c) {
  counted += 1;
  c.reply("jscount is " + counted);
});
