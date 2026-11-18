// jobs-js: running server kernels on worker threads from a plugin (docs/PLUGIN_JOBS.md).
//
// Install: copy this folder to <server>/plugins/jobs-js/ (the file must be called main.js).
// /jobdemo <n>   counts the primes up to n on a worker and tells you later (on the tick thread); the server keeps ticking meanwhile.
// /jobdemo sort 5 3 9    sorts the numbers on a worker.
// Plugin code never runs on a worker: `job(kind, input, fn)` names a server kernel ("fnv1a", "primes", "sort"). `fn` runs on the tick thread,
// where touching the world, players and hooks is allowed, and your jobs arrive in the order you submitted them.

command("jobdemo", "Run a job on a worker thread: /jobdemo <n> or /jobdemo sort <numbers>", 0, function (c) {
  var who = c.sender;
  if (c.arg(0) == "sort") {
    var id = job("sort", c.restFrom(1), function (r) { who.tell("sorted: " + r.text); });
    if (id < 0) c.fail("job rejected (" + id + ")"); else c.reply("sorting as job " + id);
    return;
  }
  var n = c.arg(0) == "" ? "100000" : c.arg(0);
  var id2 = job("primes", n, function (r) {
    if (r.failed) who.tell("job failed");
    else who.tell("primes up to " + n + ": " + r.value);
  });
  if (id2 < 0) c.fail("job rejected (" + id2 + ")"); else c.reply("counting as job " + id2);
});
