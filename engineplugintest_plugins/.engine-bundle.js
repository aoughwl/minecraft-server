var __aoeP = [];
(function () {
var start, stop, on_player_chat, on_player_command, on_player_join, on_player_leave, on_player_move, on_player_teleport, on_player_toggle, on_player_gamemode_change, on_player_item_held, on_player_login, on_player_interact, on_block_place, on_server_command, on_server_broadcast, on_server_tick_start, on_server_tick_end, on_server_load, on_packet_received, on_block_redstone, on_spawn_change, on_block_grow, on_chunk_send, on_task, on_job, on_command, on_player_exp_change, on_player_respawn, on_player_death, on_player_swing, on_player_swap_hands, on_inventory_open, on_entity_potion_effect, on_entity_combust, on_entity_teleport, on_piston, on_projectile_hit, on_block_change, on_portal, on_furnace_smelt, on_player_kick, on_tab_complete, on_entity_target, on_advancement, on_hopper_move, on_player_use_item, on_player_interact_entity, on_player_custom_payload, on_player_main_hand_change, on_inventory_close, on_inventory_click, on_block_break, on_player_drop_item, on_player_pickup_item, on_player_item_consume, on_player_bed_enter, on_player_bed_leave, on_sign_change, on_bucket_empty, on_bucket_fill, on_permission_check, on_player_fish, on_player_egg_throw, on_custom_click, on_player_change_world, on_entity_damage, on_entity_death, on_entity_spawn, on_entity_remove, on_explosion, on_weather_change, on_entity_heal, on_player_food_change, on_player_statistic, on_server_list_ping, on_player_pre_login, on_player_level_change, on_world_save, on_time_set;
// The SDK of a server plugin written in JavaScript. The server puts this in front of every JavaScript plugin, so a plugin just uses it:
//
//   on(JoinEvent, function (e) { e.player.tell("Welcome, " + e.player.name + "!"); });
//   on(ChatEvent, function (e) { if (e.message == "!ping") { e.player.tell("pong!"); e.cancel(); } });
//   command("hello", "Say hello", 0, function (c) { c.reply("Hello, " + c.sender.name + "!"); });
//   after(100, function () { server.broadcast("five seconds later"); });
//
// The first argument of `on` is the event type, the way Bukkit's registerEvent names the event class. See docs/EVENTS.md for the events
// and docs/PLUGINS.md for the rest. (Plain functions called on_player_chat, on_command ... still work; this is the nicer way.)

var __sdk = (function () {
  var handlers = {};          // entry name -> [function]
  var commands = [];          // { name, description, level, fn }
  var tasks = [];             // { id, repeat, fn, data }
  var enables = [], disables = [];
  var wanted = [];
  var started = false;

  function str(k) { return hostv("event_str", k); }
  function num(k) { return hostv("event_num", k); }
  function want(entry) {
    for (var i = 0; i < wanted.length; i++) if (wanted[i] == entry) return;
    wanted.push(entry);
    if (started) hostS("subscribe_event", entry);
  }

  // ---- players and the server
  function Player(name) { this.name = name; }
  Player.prototype.tell = function (text) { return hostv("player_message_to", this.name, text); };
  Player.prototype.itemCount = function (item) { return hostv("player_item_count", this.name, item); };
  Player.prototype.setFood = function (level) { return hostv("player_set_food", this.name, level) == true; };
  Player.prototype.give = function (item, count) { return hostv("player_give", this.name, item, count) == true; };
  function hexBytes(s) { var out = []; for (var i = 0; i + 1 < s.length; i += 2) out.push(parseInt(s.substr(i, 2), 16)); return out; }
  function bytesHex(b) { var h = ""; for (var i = 0; i < b.length; i++) h += ("0" + (b[i] & 255).toString(16)).slice(-2); return h; }
  Player.prototype.sendPayload = function (channel, bytes) { return hostv("player_send_payload", this.name, channel, typeof bytes === "string" ? bytesHex(Array.prototype.map.call(bytes, function (c) { return c.charCodeAt(0); })) : bytesHex(bytes)) == true; };
  Player.prototype.hasChannel = function (channel) { return hostv("player_has_channel", this.name, channel) == true; };
  Player.prototype.channels = function () { var s = hostv("player_channels", this.name); return s ? s.split("\n") : []; };
  Player.prototype.hasCapability = function (name) { return hostv("player_has_capability", this.name, name) == true; };
  Player.prototype.modState = function (modId) { return hostv("player_mod_state", this.name, modId); };
  Player.prototype.jesterVersion = function () { return hostv("player_jester_version", this.name); };
  Player.prototype.kick = function (reason) { return hostv("player_kick", this.name, reason); };
  Player.prototype.teleport = function (x, y, z) {
    if (typeof x === "object") { y = x.y; z = x.z; x = x.x; }
    return hostv("player_teleport", this.name, x, y, z);
  };
  Player.prototype.setGamemode = function (mode) { return hostv("player_set_gamemode", this.name, mode); };
  Player.prototype.pos = function () {
    return { x: hostv("player_pos", this.name, "x"), y: hostv("player_pos", this.name, "y"), z: hostv("player_pos", this.name, "z") };
  };
  Player.prototype.isOnline = function () { return hostv("player_online", this.name); };
  function P() { return new Player(str("player")); }
  function vec(prefix) { return { x: num(prefix + "x"), y: num(prefix + "y"), z: num(prefix + "z") }; }
  function xyz() { return { x: num("x"), y: num("y"), z: num("z") }; }
  function merge(a, b) { for (var k in b) a[k] = b[k]; return a; }

  function materialFrom(text) {
    var w = String(text).split(" ");
    if (w.length < 13) return { known: false };
    return { known: true, matClass: w[0], density: Number(w[1]), fill: Number(w[2]), stiffness: Number(w[3]), damping: Number(w[4]),
             tensile: Number(w[5]), compressive: Number(w[6]), dragArea: Number(w[7]), breakThreshold: Number(w[8]),
             flammability: Number(w[9]), ignitability: Number(w[10]), liquid: w[11] === "1", indestructible: w[12] === "1" };
  }

  var server = {
    log: function (text) { hostS("server_log", text); },
    broadcast: function (text) { hostS("server_broadcast", text); },
    windAt: function (x, y, z) {
      var w = String(hostv("physics_wind_at", x, y, z)).split(" ");
      return w.length >= 4 ? { x: Number(w[0]), y: Number(w[1]), z: Number(w[2]), speed: Number(w[3]) } : { x: 0, y: 0, z: 0, speed: 0 };
    },
    materialByName: function (name) { return materialFrom(hostv("physics_material_by_name", name)); },
    materialAt: function (x, y, z) { return materialFrom(hostv("physics_material_at", x, y, z)); },
    massOf: function (name, volume) { var m = materialFrom(hostv("physics_material_by_name", name)); return m.known ? m.density * (volume === undefined ? 1 : volume) : 0; },
    solveRegion: function (x, y, z, nx, ny, nz, options) {
      options = options || {};
      var text = String(hostv("physics_solve", x + " " + y + " " + z, nx + " " + ny + " " + nz,
        options.floorAnchored === false ? "0" : "1", options.wind ? "1" : "0"));
      if (text.indexOf("error:") === 0) return { ok: false, error: text.substr(7), broken: [] };
      var lines = text.split("\n"), h = lines[0].split(" ");
      var kinds = ["none", "bending", "shear", "crush", "tension", "hang", "unsupported"];
      var r = { ok: true, error: "", maxRatio: Number(h[0]), converged: h[1] === "1", rounds: Number(h[2]), granular: Number(h[4]),
                caveIns: Number(h[5]), components: Number(h[6]), broken: [] };
      for (var i = 1; i < lines.length; i++) {
        var b = lines[i].split(" ");
        if (b.length >= 5) r.broken.push({ x: Number(b[0]), y: Number(b[1]), z: Number(b[2]), ratio: Number(b[3]), kind: kinds[Number(b[4])] || "none" });
      }
      return r;
    },
    advertiseCapability: function (name) { return hostv("server_advertise_capability", name) == true; },
    onlineCount: function () { return hostv("server_player_count"); },
    player: function (name) { return new Player(name); },
    blockAt: function (x, y, z) { return hostv("world_get_block", x, y, z); },
    setBlock: function (x, y, z, name) { return hostv("world_set_block", x, y, z, name) == true; },
    entityHealth: function (id) { return hostv("entity_health", id); },
    setEntityHealth: function (id, health) { return hostv("entity_set_health", id, health) == true; },
    entityPos: function (id) { return { x: hostv("entity_pos", id, "x"), y: hostv("entity_pos", id, "y"), z: hostv("entity_pos", id, "z") }; },
    teleportEntity: function (id, x, y, z) { return hostv("entity_teleport", id, x, y, z) == true; },
    setEntityOnFire: function (id, seconds) { return hostv("entity_ignite", id, seconds) == true; },
    removeEntity: function (id) { return hostv("entity_remove", id) == true; },
    time: function () { return hostv("world_time"); },
    setTime: function (ticks) { hostv("world_set_time", ticks); }
  };

  // ---- event types: [entry, build]. `build` makes the event object from what the host knows.
  var types = {
    ChatEvent: ["on_player_chat", function () { return { player: P(), message: str("message") }; }],
    PlayerCommandEvent: ["on_player_command", function () { return { player: P(), command: str("message") }; }],
    JoinEvent: ["on_player_join", function () { return { player: P() }; }],
    LeaveEvent: ["on_player_leave", function () { return { player: P() }; }],
    LoginEvent: ["on_player_login", function () { return { player: P(), kickMessage: str("message") }; }],
    MoveEvent: ["on_player_move", function () { return { player: P(), origin: vec("from_"), target: vec("to_") }; }],
    TeleportEvent: ["on_player_teleport", function () { return { player: P(), origin: vec("from_"), target: vec("to_") }; }],
    ToggleEvent: ["on_player_toggle", function () { return { player: P(), kind: num("kind"), on: num("value") != 0 }; }],
    GamemodeChangeEvent: ["on_player_gamemode_change", function () { return { player: P(), previous: num("previous"), next: num("next") }; }],
    ItemHeldEvent: ["on_player_item_held", function () { return { player: P(), previousSlot: num("previous"), nextSlot: num("next") }; }],
    InteractEvent: ["on_player_interact", function () { return merge({ player: P(), action: num("action") }, xyz()); }],
    InventoryOpenEvent: ["on_inventory_open", function () { return { player: P(), window: num("window") }; }],
    PotionEffectEvent: ["on_entity_potion_effect", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), effect: str("effect"), duration: num("duration"), amplifier: num("amplifier") };
    }],
    CombustEvent: ["on_entity_combust", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), ticks: num("ticks") }; }],
    EntityTeleportEvent: ["on_entity_teleport", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), origin: vec("from_"), target: vec("to_") };
    }],
    PistonEvent: ["on_piston", function () {
      return { x: num("x"), y: num("y"), z: num("z"), extend: num("extend") != 0, moved: num("moved"), broken: num("broken") };
    }],
    ProjectileHitEvent: ["on_projectile_hit", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), ownerId: num("owner_id"), hitEntity: num("on_entity") != 0,
               targetId: num("target_id"), x: num("x"), y: num("y"), z: num("z") };
    }],
    BlockChangeEvent: ["on_block_change", function () {
      return { x: num("x"), y: num("y"), z: num("z"), before: str("before"), after: str("after") };
    }],
    PortalEvent: ["on_portal", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), x: num("x"), y: num("y"), z: num("z"), target: str("target") };
    }],
    FurnaceSmeltEvent: ["on_furnace_smelt", function () {
      return { x: num("x"), y: num("y"), z: num("z"), input: str("input"), output: str("output") };
    }],
    KickEvent: ["on_player_kick", function () { return { player: P(), reason: str("message") }; }],
    TabCompleteEvent: ["on_tab_complete", function () { return { player: P(), buffer: str("buffer"), suggestions: [] }; }],
    TargetEvent: ["on_entity_target", function () {
      return { mobId: num("mob_id"), mobType: str("mob_type"), targetId: num("target_id"), targetType: str("target_type") };
    }],
    AdvancementEvent: ["on_advancement", function () { return { player: P(), advancement: str("advancement") }; }],
    HopperMoveEvent: ["on_hopper_move", function () { return { x: num("x"), y: num("y"), z: num("z"), item: str("item") }; }],
    SwapHandsEvent: ["on_player_swap_hands", function () { return { player: P() }; }],
    SwingEvent: ["on_player_swing", function () { return { player: P() }; }],
    UseItemEvent: ["on_player_use_item", function () { return { player: P() }; }],
    InteractEntityEvent: ["on_player_interact_entity", function () {
      return { player: P(), entityId: num("entity_id"), action: num("action"), sneaking: num("sneaking") != 0, known: num("known") != 0 };
    }],
    BlockPlaceEvent: ["on_block_place", function () {
      return merge({ player: P(), blockName: str("placed"), against: str("clicked") }, xyz());
    }],
    BlockBreakEvent: ["on_block_break", function () {
      return merge({ player: P(), blockName: str("block"), drop: num("flag") != 0 }, xyz());
    }],
    DropItemEvent: ["on_player_drop_item", function () { return { player: P(), item: str("item"), count: num("count") }; }],
    PickupItemEvent: ["on_player_pickup_item", function () {
      return { player: P(), item: str("item"), count: num("count"), entityId: num("entity_id") };
    }],
    ItemConsumeEvent: ["on_player_item_consume", function () { return { player: P(), item: str("item") }; }],
    BedEnterEvent: ["on_player_bed_enter", function () { return merge({ player: P() }, xyz()); }],
    BedLeaveEvent: ["on_player_bed_leave", function () { return merge({ player: P() }, xyz()); }],
    SignChangeEvent: ["on_sign_change", function () {
      return merge({ player: P(), lines: [str("line0"), str("line1"), str("line2"), str("line3")] }, xyz());
    }],
    BucketEmptyEvent: ["on_bucket_empty", function () { return merge({ player: P(), bucket: str("bucket") }, xyz()); }],
    BucketFillEvent: ["on_bucket_fill", function () { return merge({ player: P(), bucket: str("bucket") }, xyz()); }],
    InventoryClickEvent: ["on_inventory_click", function () {
      return { player: P(), window: num("window"), clickType: num("click_type"), slot: num("slot"), rawSlot: num("raw_slot"),
               hotbarButton: num("hotbar_button") };
    }],
    InventoryCloseEvent: ["on_inventory_close", function () { return { player: P(), window: num("window") }; }],
    PermissionCheckEvent: ["on_permission_check", function () { return { player: P(), node: str("node"), granted: num("flag") != 0 }; }],
    ExpChangeEvent: ["on_player_exp_change", function () { return { player: P(), amount: num("amount") }; }],
    RespawnEvent: ["on_player_respawn", function () { return { player: P(), pos: xyz(), alive: num("alive") != 0 }; }],
    DeathEvent: ["on_player_death", function () { return { player: P(), message: str("message") }; }],
    FishEvent: ["on_player_fish", function () { return { player: P(), state: num("state"), caught: str("caught"), exp: num("exp") }; }],
    EggThrowEvent: ["on_player_egg_throw", function () {
      return { player: P(), hatching: num("hatching") != 0, numHatches: num("num_hatches"), hatchingType: str("hatching_type") };
    }],
    ChangeWorldEvent: ["on_player_change_world", function () {
      return { player: P(), pos: xyz(), yaw: num("yaw"), pitch: num("pitch") };
    }],
    MainHandChangeEvent: ["on_player_main_hand_change", function () { return { player: P(), hand: num("hand") }; }],
    CustomPayloadEvent: ["on_player_custom_payload", function () { return { player: P(), channel: str("channel"), length: num("length"), data: hexBytes(str("data")) }; }],
    CustomClickEvent: ["on_custom_click", function () { return { player: P(), id: str("id"), length: num("length") }; }],
    EntityDamageEvent: ["on_entity_damage", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), damageType: str("damage_type"), amount: num("amount"),
               attackerId: num("attacker_id") };
    }],
    EntityDeathEvent: ["on_entity_death", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), damageType: str("damage_type"), killerId: num("killer_id") };
    }],
    EntitySpawnEvent: ["on_entity_spawn", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), pos: xyz() }; }],
    EntityRemoveEvent: ["on_entity_remove", function () { return { entityId: num("entity_id"), entityType: str("entity_type") }; }],
    ExplosionEvent: ["on_explosion", function () { return { pos: xyz(), power: num("power") }; }],
    WeatherChangeEvent: ["on_weather_change", function () { return { raining: num("raining") != 0, thundering: num("thundering") != 0 }; }],
    BlockGrowEvent: ["on_block_grow", function () { return merge({ before: str("old_block"), after: str("new_block") }, xyz()); }],
    RedstoneEvent: ["on_block_redstone", function () {
      return merge({ oldCurrent: num("old_current"), newCurrent: num("new_current") }, xyz());
    }],
    SpawnChangeEvent: ["on_spawn_change", function () {
      return { previous: vec("previous_"), next: vec("next_"), yaw: num("yaw"), pitch: num("pitch") };
    }],
    ChunkSendEvent: ["on_chunk_send", function () { return { x: num("x"), z: num("z") }; }],
    ServerCommandEvent: ["on_server_command", function () { return { command: str("command") }; }],
    BroadcastEvent: ["on_server_broadcast", function () { return { message: str("message"), sender: str("sender") }; }],
    ServerLoadEvent: ["on_server_load", function () { return { reload: num("reload") != 0 }; }],
    TickStartEvent: ["on_server_tick_start", function () { return { tick: num("tick") }; }],
    TickEndEvent: ["on_server_tick_end", function () { return { tick: num("tick"), durationNs: num("duration_ns") }; }],
    LevelChangeEvent: ["on_player_level_change", function () { return { player: P(), previous: num("previous"), level: num("level") }; }],
    WorldSaveEvent: ["on_world_save", function () { return { saved: true }; }],
    TimeSetEvent: ["on_time_set", function () { return { previous: num("previous"), time: num("time") }; }],
    HealEvent: ["on_entity_heal", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), amount: num("amount") }; }],
    FoodLevelChangeEvent: ["on_player_food_change", function () { return { player: P(), level: num("level"), previous: num("previous") }; }],
    StatisticEvent: ["on_player_statistic", function () { return { player: P(), category: num("category"), statId: num("stat_id"), amount: num("amount") }; }],
    ServerListPingEvent: ["on_server_list_ping", function () { return { address: str("address"), motd: str("message"), online: num("online"), maxPlayers: num("max") }; }],
    PreLoginEvent: ["on_player_pre_login", function () { return { name: str("player"), address: str("address"), kickMessage: str("message") }; }],
    PacketEvent: ["on_packet_received", function () {
      return { player: P(), packetId: num("packet_id"), length: num("length") };
    }]
  };
  var byEntry = {};
  var tokens = {};
  for (var name in types) {
    tokens[name] = { name: name, entry: types[name][0] };
    byEntry[types[name][0]] = types[name][1];
  }

  function on(type, fn) {
    var entry = typeof type === "string" ? type : type.entry;
    if (!handlers[entry]) handlers[entry] = [];
    handlers[entry].push(fn);
    want(entry);
  }

  function command(name, description, level, fn) {
    commands.push({ name: name, description: description, level: level, fn: fn });
    want("on_command");
    if (started) hostv("register_command", name, description, level);
  }
  function addTask(id, repeat, fn, data) { want("on_task"); tasks.push({ id: id, repeat: repeat, fn: fn, data: data }); return id; }
  function after(ticks, fn, data) { return addTask(hostv("schedule_after", ticks), false, fn, data); }
  function every(ticks, fn, data) { return addTask(hostv("schedule_repeat", ticks), true, fn, data); }
  function cancelTask(id) {
    hostv("schedule_cancel", id);
    tasks = tasks.filter(function (t) { return t.id != id; });
  }

  // ---- jobs on the server's worker threads (docs/PLUGIN_JOBS.md). `kind` names a server kernel ("fnv1a", "primes", "sort"): plugin code itself never
  // runs on a worker. job() answers an id at once (-1 unknown kind, -2 input over 64 KiB); `fn({ id, value, failed, text })` runs later, on the
  // tick thread, with the jobs of this plugin delivered in the order they were submitted. job_abi_version is 1.
  var jobs = [];              // { id, fn }
  function job(kind, input, fn) {
    var id = hostv("job_submit", kind, String(input));
    if (id > 0) { want("on_job"); jobs.push({ id: id, fn: fn }); }
    return id;
  }
  function jobStatus(id) { return hostv("job_status", id); }        // 0 pending, 1 done, 2 failed, -1 unknown or already delivered
  function jobAbiVersion() { return hostv("job_abi_version"); }

  function commandContext() {
    var who = str("player");
    var raw = str("args");
    var args = raw == "" ? [] : raw.split(" ").filter(function (w) { return w.length > 0; });
    return {
      sender: new Player(who), isConsole: who == "", name: str("command"), rawArgs: raw, args: args,
      reply: function (text) { hostv("command_reply", text); },
      fail: function (text) { hostv("command_fail", text); },
      arg: function (i) { return i < args.length ? args[i] : ""; },
      intArg: function (i, d) { var n = parseInt(args[i], 10); return isNaN(n) ? (d === undefined ? 0 : d) : n; },
      numberArg: function (i, d) { var n = parseFloat(args[i]); return isNaN(n) ? (d === undefined ? 0 : d) : n; },
      restFrom: function (i) { return args.slice(i).join(" "); }
    };
  }

  function fire(entry) {
    if (entry == "start") {
      started = true;
      for (var i = 0; i < wanted.length; i++) hostS("subscribe_event", wanted[i]);
      for (var c = 0; c < commands.length; c++) hostv("register_command", commands[c].name, commands[c].description, commands[c].level);
      for (var e = 0; e < enables.length; e++) enables[e]();
      return;
    }
    if (entry == "stop") { for (var d = 0; d < disables.length; d++) disables[d](); return; }
    if (entry == "on_command") {
      var ctx = commandContext();
      for (var k = 0; k < commands.length; k++) if (commands[k].name == ctx.name) { commands[k].fn(ctx); return; }
      return;
    }
    if (entry == "on_task") {
      var id = num("id");
      for (var t = 0; t < tasks.length; t++) {
        if (tasks[t].id == id) {
          var task = tasks[t];
          if (!task.repeat) tasks.splice(t, 1);
          task.fn(task.data);
          return;
        }
      }
      return;
    }
    if (entry == "on_job") {
      var jid = num("id");
      for (var j = 0; j < jobs.length; j++) {
        if (jobs[j].id == jid) {
          var jb = jobs.splice(j, 1)[0];
          jb.fn({ id: jid, value: num("value"), failed: num("failed") != 0, text: str("text") });
          return;
        }
      }
      return;
    }
    var list = handlers[entry];
    if (!list || !byEntry[entry]) return;
    var ev = byEntry[entry]();
    ev.cancelled = false;
    ev.cancel = function () { this.cancelled = true; };
    var tabBefore = ev.suggestions;
    var before = { message: ev.message, kickMessage: ev.kickMessage, drop: ev.drop, granted: ev.granted, hatching: ev.hatching, amount: ev.amount,
                   motd: ev.motd, maxPlayers: ev.maxPlayers, level: ev.level, time: ev.time, duration: ev.duration, ticks: ev.ticks };
    for (var h = 0; h < list.length; h++) list[h](ev);
    if (ev.cancelled) host("event_cancel");
    if (ev.message !== before.message && typeof ev.message === "string") hostS("event_set_message", ev.message);
    if (ev.kickMessage !== before.kickMessage && typeof ev.kickMessage === "string") hostS("event_set_message", ev.kickMessage);
    if (ev.drop !== before.drop) hostv("event_set_flag", ev.drop ? 1 : 0);
    if (ev.granted !== before.granted) hostv("event_set_flag", ev.granted ? 1 : 0);
    if (ev.hatching !== before.hatching) hostv("event_set_flag", ev.hatching ? 1 : 0);
    if (ev.amount !== before.amount && typeof ev.amount === "number") hostv("event_set_value", ev.amount);
    if (ev.motd !== before.motd && typeof ev.motd === "string") hostS("event_set_message", ev.motd);
    if (ev.maxPlayers !== before.maxPlayers && typeof ev.maxPlayers === "number") hostv("event_set_value", ev.maxPlayers);
    if (ev.level !== before.level && typeof ev.level === "number") hostv("event_set_value", ev.level);
    if (ev.time !== before.time && typeof ev.time === "number") hostv("event_set_value", ev.time);
    if (ev.suggestions && ev.suggestions.length > 0) hostS("event_set_message", ev.suggestions.join("\n"));
    if (ev.duration !== before.duration && typeof ev.duration === "number") hostv("event_set_value", ev.duration);
    if (ev.ticks !== before.ticks && typeof ev.ticks === "number") hostv("event_set_value", ev.ticks);
  }

  return {
    fire: fire, on: on, command: command, after: after, every: every, cancelTask: cancelTask, job: job, jobStatus: jobStatus, jobAbiVersion: jobAbiVersion, server: server, tokens: tokens,
    onEnable: function (fn) { enables.push(fn); }, onDisable: function (fn) { disables.push(fn); }
  };
})();

var on = __sdk.on, command = __sdk.command, after = __sdk.after, every = __sdk.every, cancelTask = __sdk.cancelTask;
var job = __sdk.job, jobStatus = __sdk.jobStatus, jobAbiVersion = __sdk.jobAbiVersion;
var onEnable = __sdk.onEnable, onDisable = __sdk.onDisable, server = __sdk.server;
var ChatEvent = __sdk.tokens.ChatEvent, PlayerCommandEvent = __sdk.tokens.PlayerCommandEvent, JoinEvent = __sdk.tokens.JoinEvent;
var LeaveEvent = __sdk.tokens.LeaveEvent, LoginEvent = __sdk.tokens.LoginEvent, MoveEvent = __sdk.tokens.MoveEvent;
var TeleportEvent = __sdk.tokens.TeleportEvent, ToggleEvent = __sdk.tokens.ToggleEvent, GamemodeChangeEvent = __sdk.tokens.GamemodeChangeEvent;
var CombustEvent = __sdk.tokens.CombustEvent, EntityTeleportEvent = __sdk.tokens.EntityTeleportEvent;
var PistonEvent = __sdk.tokens.PistonEvent;
var ProjectileHitEvent = __sdk.tokens.ProjectileHitEvent;
var BlockChangeEvent = __sdk.tokens.BlockChangeEvent;
var PortalEvent = __sdk.tokens.PortalEvent, FurnaceSmeltEvent = __sdk.tokens.FurnaceSmeltEvent;
var KickEvent = __sdk.tokens.KickEvent;
var TabCompleteEvent = __sdk.tokens.TabCompleteEvent;
var TargetEvent = __sdk.tokens.TargetEvent;
var AdvancementEvent = __sdk.tokens.AdvancementEvent;
var HopperMoveEvent = __sdk.tokens.HopperMoveEvent;
var SwapHandsEvent = __sdk.tokens.SwapHandsEvent, InventoryOpenEvent = __sdk.tokens.InventoryOpenEvent, PotionEffectEvent = __sdk.tokens.PotionEffectEvent;
var ItemHeldEvent = __sdk.tokens.ItemHeldEvent, InteractEvent = __sdk.tokens.InteractEvent, SwingEvent = __sdk.tokens.SwingEvent;
var UseItemEvent = __sdk.tokens.UseItemEvent, InteractEntityEvent = __sdk.tokens.InteractEntityEvent, BlockPlaceEvent = __sdk.tokens.BlockPlaceEvent;
var BlockBreakEvent = __sdk.tokens.BlockBreakEvent, DropItemEvent = __sdk.tokens.DropItemEvent, PickupItemEvent = __sdk.tokens.PickupItemEvent;
var ItemConsumeEvent = __sdk.tokens.ItemConsumeEvent, BedEnterEvent = __sdk.tokens.BedEnterEvent, BedLeaveEvent = __sdk.tokens.BedLeaveEvent;
var SignChangeEvent = __sdk.tokens.SignChangeEvent, BucketEmptyEvent = __sdk.tokens.BucketEmptyEvent, BucketFillEvent = __sdk.tokens.BucketFillEvent;
var InventoryClickEvent = __sdk.tokens.InventoryClickEvent, InventoryCloseEvent = __sdk.tokens.InventoryCloseEvent;
var PermissionCheckEvent = __sdk.tokens.PermissionCheckEvent, ExpChangeEvent = __sdk.tokens.ExpChangeEvent, RespawnEvent = __sdk.tokens.RespawnEvent;
var DeathEvent = __sdk.tokens.DeathEvent, FishEvent = __sdk.tokens.FishEvent, EggThrowEvent = __sdk.tokens.EggThrowEvent;
var ChangeWorldEvent = __sdk.tokens.ChangeWorldEvent, MainHandChangeEvent = __sdk.tokens.MainHandChangeEvent;
var CustomPayloadEvent = __sdk.tokens.CustomPayloadEvent, CustomClickEvent = __sdk.tokens.CustomClickEvent;
var EntityDamageEvent = __sdk.tokens.EntityDamageEvent, EntityDeathEvent = __sdk.tokens.EntityDeathEvent;
var EntitySpawnEvent = __sdk.tokens.EntitySpawnEvent, EntityRemoveEvent = __sdk.tokens.EntityRemoveEvent;
var ExplosionEvent = __sdk.tokens.ExplosionEvent, WeatherChangeEvent = __sdk.tokens.WeatherChangeEvent;
var BlockGrowEvent = __sdk.tokens.BlockGrowEvent, RedstoneEvent = __sdk.tokens.RedstoneEvent, SpawnChangeEvent = __sdk.tokens.SpawnChangeEvent;
var ChunkSendEvent = __sdk.tokens.ChunkSendEvent, ServerCommandEvent = __sdk.tokens.ServerCommandEvent, BroadcastEvent = __sdk.tokens.BroadcastEvent;
var ServerLoadEvent = __sdk.tokens.ServerLoadEvent, TickStartEvent = __sdk.tokens.TickStartEvent, TickEndEvent = __sdk.tokens.TickEndEvent;
var PacketEvent = __sdk.tokens.PacketEvent, HealEvent = __sdk.tokens.HealEvent, FoodLevelChangeEvent = __sdk.tokens.FoodLevelChangeEvent;
var LevelChangeEvent = __sdk.tokens.LevelChangeEvent, WorldSaveEvent = __sdk.tokens.WorldSaveEvent, TimeSetEvent = __sdk.tokens.TimeSetEvent;
var StatisticEvent = __sdk.tokens.StatisticEvent, ServerListPingEvent = __sdk.tokens.ServerListPingEvent, PreLoginEvent = __sdk.tokens.PreLoginEvent;

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


;var __h = {};
if (typeof start === "function") __h.start = start;
if (typeof stop === "function") __h.stop = stop;
if (typeof on_player_chat === "function") __h.on_player_chat = on_player_chat;
if (typeof on_player_command === "function") __h.on_player_command = on_player_command;
if (typeof on_player_join === "function") __h.on_player_join = on_player_join;
if (typeof on_player_leave === "function") __h.on_player_leave = on_player_leave;
if (typeof on_player_move === "function") __h.on_player_move = on_player_move;
if (typeof on_player_teleport === "function") __h.on_player_teleport = on_player_teleport;
if (typeof on_player_toggle === "function") __h.on_player_toggle = on_player_toggle;
if (typeof on_player_gamemode_change === "function") __h.on_player_gamemode_change = on_player_gamemode_change;
if (typeof on_player_item_held === "function") __h.on_player_item_held = on_player_item_held;
if (typeof on_player_login === "function") __h.on_player_login = on_player_login;
if (typeof on_player_interact === "function") __h.on_player_interact = on_player_interact;
if (typeof on_block_place === "function") __h.on_block_place = on_block_place;
if (typeof on_server_command === "function") __h.on_server_command = on_server_command;
if (typeof on_server_broadcast === "function") __h.on_server_broadcast = on_server_broadcast;
if (typeof on_server_tick_start === "function") __h.on_server_tick_start = on_server_tick_start;
if (typeof on_server_tick_end === "function") __h.on_server_tick_end = on_server_tick_end;
if (typeof on_server_load === "function") __h.on_server_load = on_server_load;
if (typeof on_packet_received === "function") __h.on_packet_received = on_packet_received;
if (typeof on_block_redstone === "function") __h.on_block_redstone = on_block_redstone;
if (typeof on_spawn_change === "function") __h.on_spawn_change = on_spawn_change;
if (typeof on_block_grow === "function") __h.on_block_grow = on_block_grow;
if (typeof on_chunk_send === "function") __h.on_chunk_send = on_chunk_send;
if (typeof on_task === "function") __h.on_task = on_task;
if (typeof on_job === "function") __h.on_job = on_job;
if (typeof on_command === "function") __h.on_command = on_command;
if (typeof on_player_exp_change === "function") __h.on_player_exp_change = on_player_exp_change;
if (typeof on_player_respawn === "function") __h.on_player_respawn = on_player_respawn;
if (typeof on_player_death === "function") __h.on_player_death = on_player_death;
if (typeof on_player_swing === "function") __h.on_player_swing = on_player_swing;
if (typeof on_player_swap_hands === "function") __h.on_player_swap_hands = on_player_swap_hands;
if (typeof on_inventory_open === "function") __h.on_inventory_open = on_inventory_open;
if (typeof on_entity_potion_effect === "function") __h.on_entity_potion_effect = on_entity_potion_effect;
if (typeof on_entity_combust === "function") __h.on_entity_combust = on_entity_combust;
if (typeof on_entity_teleport === "function") __h.on_entity_teleport = on_entity_teleport;
if (typeof on_piston === "function") __h.on_piston = on_piston;
if (typeof on_projectile_hit === "function") __h.on_projectile_hit = on_projectile_hit;
if (typeof on_block_change === "function") __h.on_block_change = on_block_change;
if (typeof on_portal === "function") __h.on_portal = on_portal;
if (typeof on_furnace_smelt === "function") __h.on_furnace_smelt = on_furnace_smelt;
if (typeof on_player_kick === "function") __h.on_player_kick = on_player_kick;
if (typeof on_tab_complete === "function") __h.on_tab_complete = on_tab_complete;
if (typeof on_entity_target === "function") __h.on_entity_target = on_entity_target;
if (typeof on_advancement === "function") __h.on_advancement = on_advancement;
if (typeof on_hopper_move === "function") __h.on_hopper_move = on_hopper_move;
if (typeof on_player_use_item === "function") __h.on_player_use_item = on_player_use_item;
if (typeof on_player_interact_entity === "function") __h.on_player_interact_entity = on_player_interact_entity;
if (typeof on_player_custom_payload === "function") __h.on_player_custom_payload = on_player_custom_payload;
if (typeof on_player_main_hand_change === "function") __h.on_player_main_hand_change = on_player_main_hand_change;
if (typeof on_inventory_close === "function") __h.on_inventory_close = on_inventory_close;
if (typeof on_inventory_click === "function") __h.on_inventory_click = on_inventory_click;
if (typeof on_block_break === "function") __h.on_block_break = on_block_break;
if (typeof on_player_drop_item === "function") __h.on_player_drop_item = on_player_drop_item;
if (typeof on_player_pickup_item === "function") __h.on_player_pickup_item = on_player_pickup_item;
if (typeof on_player_item_consume === "function") __h.on_player_item_consume = on_player_item_consume;
if (typeof on_player_bed_enter === "function") __h.on_player_bed_enter = on_player_bed_enter;
if (typeof on_player_bed_leave === "function") __h.on_player_bed_leave = on_player_bed_leave;
if (typeof on_sign_change === "function") __h.on_sign_change = on_sign_change;
if (typeof on_bucket_empty === "function") __h.on_bucket_empty = on_bucket_empty;
if (typeof on_bucket_fill === "function") __h.on_bucket_fill = on_bucket_fill;
if (typeof on_permission_check === "function") __h.on_permission_check = on_permission_check;
if (typeof on_player_fish === "function") __h.on_player_fish = on_player_fish;
if (typeof on_player_egg_throw === "function") __h.on_player_egg_throw = on_player_egg_throw;
if (typeof on_custom_click === "function") __h.on_custom_click = on_custom_click;
if (typeof on_player_change_world === "function") __h.on_player_change_world = on_player_change_world;
if (typeof on_entity_damage === "function") __h.on_entity_damage = on_entity_damage;
if (typeof on_entity_death === "function") __h.on_entity_death = on_entity_death;
if (typeof on_entity_spawn === "function") __h.on_entity_spawn = on_entity_spawn;
if (typeof on_entity_remove === "function") __h.on_entity_remove = on_entity_remove;
if (typeof on_explosion === "function") __h.on_explosion = on_explosion;
if (typeof on_weather_change === "function") __h.on_weather_change = on_weather_change;
if (typeof on_entity_heal === "function") __h.on_entity_heal = on_entity_heal;
if (typeof on_player_food_change === "function") __h.on_player_food_change = on_player_food_change;
if (typeof on_player_statistic === "function") __h.on_player_statistic = on_player_statistic;
if (typeof on_server_list_ping === "function") __h.on_server_list_ping = on_server_list_ping;
if (typeof on_player_pre_login === "function") __h.on_player_pre_login = on_player_pre_login;
if (typeof on_player_level_change === "function") __h.on_player_level_change = on_player_level_change;
if (typeof on_world_save === "function") __h.on_world_save = on_world_save;
if (typeof on_time_set === "function") __h.on_time_set = on_time_set;
__h.__sdk = __sdk;
__aoeP.push({ name: "filter", h: __h });
})();
(function () {
var start, stop, on_player_chat, on_player_command, on_player_join, on_player_leave, on_player_move, on_player_teleport, on_player_toggle, on_player_gamemode_change, on_player_item_held, on_player_login, on_player_interact, on_block_place, on_server_command, on_server_broadcast, on_server_tick_start, on_server_tick_end, on_server_load, on_packet_received, on_block_redstone, on_spawn_change, on_block_grow, on_chunk_send, on_task, on_job, on_command, on_player_exp_change, on_player_respawn, on_player_death, on_player_swing, on_player_swap_hands, on_inventory_open, on_entity_potion_effect, on_entity_combust, on_entity_teleport, on_piston, on_projectile_hit, on_block_change, on_portal, on_furnace_smelt, on_player_kick, on_tab_complete, on_entity_target, on_advancement, on_hopper_move, on_player_use_item, on_player_interact_entity, on_player_custom_payload, on_player_main_hand_change, on_inventory_close, on_inventory_click, on_block_break, on_player_drop_item, on_player_pickup_item, on_player_item_consume, on_player_bed_enter, on_player_bed_leave, on_sign_change, on_bucket_empty, on_bucket_fill, on_permission_check, on_player_fish, on_player_egg_throw, on_custom_click, on_player_change_world, on_entity_damage, on_entity_death, on_entity_spawn, on_entity_remove, on_explosion, on_weather_change, on_entity_heal, on_player_food_change, on_player_statistic, on_server_list_ping, on_player_pre_login, on_player_level_change, on_world_save, on_time_set;
// The SDK of a server plugin written in JavaScript. The server puts this in front of every JavaScript plugin, so a plugin just uses it:
//
//   on(JoinEvent, function (e) { e.player.tell("Welcome, " + e.player.name + "!"); });
//   on(ChatEvent, function (e) { if (e.message == "!ping") { e.player.tell("pong!"); e.cancel(); } });
//   command("hello", "Say hello", 0, function (c) { c.reply("Hello, " + c.sender.name + "!"); });
//   after(100, function () { server.broadcast("five seconds later"); });
//
// The first argument of `on` is the event type, the way Bukkit's registerEvent names the event class. See docs/EVENTS.md for the events
// and docs/PLUGINS.md for the rest. (Plain functions called on_player_chat, on_command ... still work; this is the nicer way.)

var __sdk = (function () {
  var handlers = {};          // entry name -> [function]
  var commands = [];          // { name, description, level, fn }
  var tasks = [];             // { id, repeat, fn, data }
  var enables = [], disables = [];
  var wanted = [];
  var started = false;

  function str(k) { return hostv("event_str", k); }
  function num(k) { return hostv("event_num", k); }
  function want(entry) {
    for (var i = 0; i < wanted.length; i++) if (wanted[i] == entry) return;
    wanted.push(entry);
    if (started) hostS("subscribe_event", entry);
  }

  // ---- players and the server
  function Player(name) { this.name = name; }
  Player.prototype.tell = function (text) { return hostv("player_message_to", this.name, text); };
  Player.prototype.itemCount = function (item) { return hostv("player_item_count", this.name, item); };
  Player.prototype.setFood = function (level) { return hostv("player_set_food", this.name, level) == true; };
  Player.prototype.give = function (item, count) { return hostv("player_give", this.name, item, count) == true; };
  function hexBytes(s) { var out = []; for (var i = 0; i + 1 < s.length; i += 2) out.push(parseInt(s.substr(i, 2), 16)); return out; }
  function bytesHex(b) { var h = ""; for (var i = 0; i < b.length; i++) h += ("0" + (b[i] & 255).toString(16)).slice(-2); return h; }
  Player.prototype.sendPayload = function (channel, bytes) { return hostv("player_send_payload", this.name, channel, typeof bytes === "string" ? bytesHex(Array.prototype.map.call(bytes, function (c) { return c.charCodeAt(0); })) : bytesHex(bytes)) == true; };
  Player.prototype.hasChannel = function (channel) { return hostv("player_has_channel", this.name, channel) == true; };
  Player.prototype.channels = function () { var s = hostv("player_channels", this.name); return s ? s.split("\n") : []; };
  Player.prototype.hasCapability = function (name) { return hostv("player_has_capability", this.name, name) == true; };
  Player.prototype.modState = function (modId) { return hostv("player_mod_state", this.name, modId); };
  Player.prototype.jesterVersion = function () { return hostv("player_jester_version", this.name); };
  Player.prototype.kick = function (reason) { return hostv("player_kick", this.name, reason); };
  Player.prototype.teleport = function (x, y, z) {
    if (typeof x === "object") { y = x.y; z = x.z; x = x.x; }
    return hostv("player_teleport", this.name, x, y, z);
  };
  Player.prototype.setGamemode = function (mode) { return hostv("player_set_gamemode", this.name, mode); };
  Player.prototype.pos = function () {
    return { x: hostv("player_pos", this.name, "x"), y: hostv("player_pos", this.name, "y"), z: hostv("player_pos", this.name, "z") };
  };
  Player.prototype.isOnline = function () { return hostv("player_online", this.name); };
  function P() { return new Player(str("player")); }
  function vec(prefix) { return { x: num(prefix + "x"), y: num(prefix + "y"), z: num(prefix + "z") }; }
  function xyz() { return { x: num("x"), y: num("y"), z: num("z") }; }
  function merge(a, b) { for (var k in b) a[k] = b[k]; return a; }

  function materialFrom(text) {
    var w = String(text).split(" ");
    if (w.length < 13) return { known: false };
    return { known: true, matClass: w[0], density: Number(w[1]), fill: Number(w[2]), stiffness: Number(w[3]), damping: Number(w[4]),
             tensile: Number(w[5]), compressive: Number(w[6]), dragArea: Number(w[7]), breakThreshold: Number(w[8]),
             flammability: Number(w[9]), ignitability: Number(w[10]), liquid: w[11] === "1", indestructible: w[12] === "1" };
  }

  var server = {
    log: function (text) { hostS("server_log", text); },
    broadcast: function (text) { hostS("server_broadcast", text); },
    windAt: function (x, y, z) {
      var w = String(hostv("physics_wind_at", x, y, z)).split(" ");
      return w.length >= 4 ? { x: Number(w[0]), y: Number(w[1]), z: Number(w[2]), speed: Number(w[3]) } : { x: 0, y: 0, z: 0, speed: 0 };
    },
    materialByName: function (name) { return materialFrom(hostv("physics_material_by_name", name)); },
    materialAt: function (x, y, z) { return materialFrom(hostv("physics_material_at", x, y, z)); },
    massOf: function (name, volume) { var m = materialFrom(hostv("physics_material_by_name", name)); return m.known ? m.density * (volume === undefined ? 1 : volume) : 0; },
    solveRegion: function (x, y, z, nx, ny, nz, options) {
      options = options || {};
      var text = String(hostv("physics_solve", x + " " + y + " " + z, nx + " " + ny + " " + nz,
        options.floorAnchored === false ? "0" : "1", options.wind ? "1" : "0"));
      if (text.indexOf("error:") === 0) return { ok: false, error: text.substr(7), broken: [] };
      var lines = text.split("\n"), h = lines[0].split(" ");
      var kinds = ["none", "bending", "shear", "crush", "tension", "hang", "unsupported"];
      var r = { ok: true, error: "", maxRatio: Number(h[0]), converged: h[1] === "1", rounds: Number(h[2]), granular: Number(h[4]),
                caveIns: Number(h[5]), components: Number(h[6]), broken: [] };
      for (var i = 1; i < lines.length; i++) {
        var b = lines[i].split(" ");
        if (b.length >= 5) r.broken.push({ x: Number(b[0]), y: Number(b[1]), z: Number(b[2]), ratio: Number(b[3]), kind: kinds[Number(b[4])] || "none" });
      }
      return r;
    },
    advertiseCapability: function (name) { return hostv("server_advertise_capability", name) == true; },
    onlineCount: function () { return hostv("server_player_count"); },
    player: function (name) { return new Player(name); },
    blockAt: function (x, y, z) { return hostv("world_get_block", x, y, z); },
    setBlock: function (x, y, z, name) { return hostv("world_set_block", x, y, z, name) == true; },
    entityHealth: function (id) { return hostv("entity_health", id); },
    setEntityHealth: function (id, health) { return hostv("entity_set_health", id, health) == true; },
    entityPos: function (id) { return { x: hostv("entity_pos", id, "x"), y: hostv("entity_pos", id, "y"), z: hostv("entity_pos", id, "z") }; },
    teleportEntity: function (id, x, y, z) { return hostv("entity_teleport", id, x, y, z) == true; },
    setEntityOnFire: function (id, seconds) { return hostv("entity_ignite", id, seconds) == true; },
    removeEntity: function (id) { return hostv("entity_remove", id) == true; },
    time: function () { return hostv("world_time"); },
    setTime: function (ticks) { hostv("world_set_time", ticks); }
  };

  // ---- event types: [entry, build]. `build` makes the event object from what the host knows.
  var types = {
    ChatEvent: ["on_player_chat", function () { return { player: P(), message: str("message") }; }],
    PlayerCommandEvent: ["on_player_command", function () { return { player: P(), command: str("message") }; }],
    JoinEvent: ["on_player_join", function () { return { player: P() }; }],
    LeaveEvent: ["on_player_leave", function () { return { player: P() }; }],
    LoginEvent: ["on_player_login", function () { return { player: P(), kickMessage: str("message") }; }],
    MoveEvent: ["on_player_move", function () { return { player: P(), origin: vec("from_"), target: vec("to_") }; }],
    TeleportEvent: ["on_player_teleport", function () { return { player: P(), origin: vec("from_"), target: vec("to_") }; }],
    ToggleEvent: ["on_player_toggle", function () { return { player: P(), kind: num("kind"), on: num("value") != 0 }; }],
    GamemodeChangeEvent: ["on_player_gamemode_change", function () { return { player: P(), previous: num("previous"), next: num("next") }; }],
    ItemHeldEvent: ["on_player_item_held", function () { return { player: P(), previousSlot: num("previous"), nextSlot: num("next") }; }],
    InteractEvent: ["on_player_interact", function () { return merge({ player: P(), action: num("action") }, xyz()); }],
    InventoryOpenEvent: ["on_inventory_open", function () { return { player: P(), window: num("window") }; }],
    PotionEffectEvent: ["on_entity_potion_effect", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), effect: str("effect"), duration: num("duration"), amplifier: num("amplifier") };
    }],
    CombustEvent: ["on_entity_combust", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), ticks: num("ticks") }; }],
    EntityTeleportEvent: ["on_entity_teleport", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), origin: vec("from_"), target: vec("to_") };
    }],
    PistonEvent: ["on_piston", function () {
      return { x: num("x"), y: num("y"), z: num("z"), extend: num("extend") != 0, moved: num("moved"), broken: num("broken") };
    }],
    ProjectileHitEvent: ["on_projectile_hit", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), ownerId: num("owner_id"), hitEntity: num("on_entity") != 0,
               targetId: num("target_id"), x: num("x"), y: num("y"), z: num("z") };
    }],
    BlockChangeEvent: ["on_block_change", function () {
      return { x: num("x"), y: num("y"), z: num("z"), before: str("before"), after: str("after") };
    }],
    PortalEvent: ["on_portal", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), x: num("x"), y: num("y"), z: num("z"), target: str("target") };
    }],
    FurnaceSmeltEvent: ["on_furnace_smelt", function () {
      return { x: num("x"), y: num("y"), z: num("z"), input: str("input"), output: str("output") };
    }],
    KickEvent: ["on_player_kick", function () { return { player: P(), reason: str("message") }; }],
    TabCompleteEvent: ["on_tab_complete", function () { return { player: P(), buffer: str("buffer"), suggestions: [] }; }],
    TargetEvent: ["on_entity_target", function () {
      return { mobId: num("mob_id"), mobType: str("mob_type"), targetId: num("target_id"), targetType: str("target_type") };
    }],
    AdvancementEvent: ["on_advancement", function () { return { player: P(), advancement: str("advancement") }; }],
    HopperMoveEvent: ["on_hopper_move", function () { return { x: num("x"), y: num("y"), z: num("z"), item: str("item") }; }],
    SwapHandsEvent: ["on_player_swap_hands", function () { return { player: P() }; }],
    SwingEvent: ["on_player_swing", function () { return { player: P() }; }],
    UseItemEvent: ["on_player_use_item", function () { return { player: P() }; }],
    InteractEntityEvent: ["on_player_interact_entity", function () {
      return { player: P(), entityId: num("entity_id"), action: num("action"), sneaking: num("sneaking") != 0, known: num("known") != 0 };
    }],
    BlockPlaceEvent: ["on_block_place", function () {
      return merge({ player: P(), blockName: str("placed"), against: str("clicked") }, xyz());
    }],
    BlockBreakEvent: ["on_block_break", function () {
      return merge({ player: P(), blockName: str("block"), drop: num("flag") != 0 }, xyz());
    }],
    DropItemEvent: ["on_player_drop_item", function () { return { player: P(), item: str("item"), count: num("count") }; }],
    PickupItemEvent: ["on_player_pickup_item", function () {
      return { player: P(), item: str("item"), count: num("count"), entityId: num("entity_id") };
    }],
    ItemConsumeEvent: ["on_player_item_consume", function () { return { player: P(), item: str("item") }; }],
    BedEnterEvent: ["on_player_bed_enter", function () { return merge({ player: P() }, xyz()); }],
    BedLeaveEvent: ["on_player_bed_leave", function () { return merge({ player: P() }, xyz()); }],
    SignChangeEvent: ["on_sign_change", function () {
      return merge({ player: P(), lines: [str("line0"), str("line1"), str("line2"), str("line3")] }, xyz());
    }],
    BucketEmptyEvent: ["on_bucket_empty", function () { return merge({ player: P(), bucket: str("bucket") }, xyz()); }],
    BucketFillEvent: ["on_bucket_fill", function () { return merge({ player: P(), bucket: str("bucket") }, xyz()); }],
    InventoryClickEvent: ["on_inventory_click", function () {
      return { player: P(), window: num("window"), clickType: num("click_type"), slot: num("slot"), rawSlot: num("raw_slot"),
               hotbarButton: num("hotbar_button") };
    }],
    InventoryCloseEvent: ["on_inventory_close", function () { return { player: P(), window: num("window") }; }],
    PermissionCheckEvent: ["on_permission_check", function () { return { player: P(), node: str("node"), granted: num("flag") != 0 }; }],
    ExpChangeEvent: ["on_player_exp_change", function () { return { player: P(), amount: num("amount") }; }],
    RespawnEvent: ["on_player_respawn", function () { return { player: P(), pos: xyz(), alive: num("alive") != 0 }; }],
    DeathEvent: ["on_player_death", function () { return { player: P(), message: str("message") }; }],
    FishEvent: ["on_player_fish", function () { return { player: P(), state: num("state"), caught: str("caught"), exp: num("exp") }; }],
    EggThrowEvent: ["on_player_egg_throw", function () {
      return { player: P(), hatching: num("hatching") != 0, numHatches: num("num_hatches"), hatchingType: str("hatching_type") };
    }],
    ChangeWorldEvent: ["on_player_change_world", function () {
      return { player: P(), pos: xyz(), yaw: num("yaw"), pitch: num("pitch") };
    }],
    MainHandChangeEvent: ["on_player_main_hand_change", function () { return { player: P(), hand: num("hand") }; }],
    CustomPayloadEvent: ["on_player_custom_payload", function () { return { player: P(), channel: str("channel"), length: num("length"), data: hexBytes(str("data")) }; }],
    CustomClickEvent: ["on_custom_click", function () { return { player: P(), id: str("id"), length: num("length") }; }],
    EntityDamageEvent: ["on_entity_damage", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), damageType: str("damage_type"), amount: num("amount"),
               attackerId: num("attacker_id") };
    }],
    EntityDeathEvent: ["on_entity_death", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), damageType: str("damage_type"), killerId: num("killer_id") };
    }],
    EntitySpawnEvent: ["on_entity_spawn", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), pos: xyz() }; }],
    EntityRemoveEvent: ["on_entity_remove", function () { return { entityId: num("entity_id"), entityType: str("entity_type") }; }],
    ExplosionEvent: ["on_explosion", function () { return { pos: xyz(), power: num("power") }; }],
    WeatherChangeEvent: ["on_weather_change", function () { return { raining: num("raining") != 0, thundering: num("thundering") != 0 }; }],
    BlockGrowEvent: ["on_block_grow", function () { return merge({ before: str("old_block"), after: str("new_block") }, xyz()); }],
    RedstoneEvent: ["on_block_redstone", function () {
      return merge({ oldCurrent: num("old_current"), newCurrent: num("new_current") }, xyz());
    }],
    SpawnChangeEvent: ["on_spawn_change", function () {
      return { previous: vec("previous_"), next: vec("next_"), yaw: num("yaw"), pitch: num("pitch") };
    }],
    ChunkSendEvent: ["on_chunk_send", function () { return { x: num("x"), z: num("z") }; }],
    ServerCommandEvent: ["on_server_command", function () { return { command: str("command") }; }],
    BroadcastEvent: ["on_server_broadcast", function () { return { message: str("message"), sender: str("sender") }; }],
    ServerLoadEvent: ["on_server_load", function () { return { reload: num("reload") != 0 }; }],
    TickStartEvent: ["on_server_tick_start", function () { return { tick: num("tick") }; }],
    TickEndEvent: ["on_server_tick_end", function () { return { tick: num("tick"), durationNs: num("duration_ns") }; }],
    LevelChangeEvent: ["on_player_level_change", function () { return { player: P(), previous: num("previous"), level: num("level") }; }],
    WorldSaveEvent: ["on_world_save", function () { return { saved: true }; }],
    TimeSetEvent: ["on_time_set", function () { return { previous: num("previous"), time: num("time") }; }],
    HealEvent: ["on_entity_heal", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), amount: num("amount") }; }],
    FoodLevelChangeEvent: ["on_player_food_change", function () { return { player: P(), level: num("level"), previous: num("previous") }; }],
    StatisticEvent: ["on_player_statistic", function () { return { player: P(), category: num("category"), statId: num("stat_id"), amount: num("amount") }; }],
    ServerListPingEvent: ["on_server_list_ping", function () { return { address: str("address"), motd: str("message"), online: num("online"), maxPlayers: num("max") }; }],
    PreLoginEvent: ["on_player_pre_login", function () { return { name: str("player"), address: str("address"), kickMessage: str("message") }; }],
    PacketEvent: ["on_packet_received", function () {
      return { player: P(), packetId: num("packet_id"), length: num("length") };
    }]
  };
  var byEntry = {};
  var tokens = {};
  for (var name in types) {
    tokens[name] = { name: name, entry: types[name][0] };
    byEntry[types[name][0]] = types[name][1];
  }

  function on(type, fn) {
    var entry = typeof type === "string" ? type : type.entry;
    if (!handlers[entry]) handlers[entry] = [];
    handlers[entry].push(fn);
    want(entry);
  }

  function command(name, description, level, fn) {
    commands.push({ name: name, description: description, level: level, fn: fn });
    want("on_command");
    if (started) hostv("register_command", name, description, level);
  }
  function addTask(id, repeat, fn, data) { want("on_task"); tasks.push({ id: id, repeat: repeat, fn: fn, data: data }); return id; }
  function after(ticks, fn, data) { return addTask(hostv("schedule_after", ticks), false, fn, data); }
  function every(ticks, fn, data) { return addTask(hostv("schedule_repeat", ticks), true, fn, data); }
  function cancelTask(id) {
    hostv("schedule_cancel", id);
    tasks = tasks.filter(function (t) { return t.id != id; });
  }

  // ---- jobs on the server's worker threads (docs/PLUGIN_JOBS.md). `kind` names a server kernel ("fnv1a", "primes", "sort"): plugin code itself never
  // runs on a worker. job() answers an id at once (-1 unknown kind, -2 input over 64 KiB); `fn({ id, value, failed, text })` runs later, on the
  // tick thread, with the jobs of this plugin delivered in the order they were submitted. job_abi_version is 1.
  var jobs = [];              // { id, fn }
  function job(kind, input, fn) {
    var id = hostv("job_submit", kind, String(input));
    if (id > 0) { want("on_job"); jobs.push({ id: id, fn: fn }); }
    return id;
  }
  function jobStatus(id) { return hostv("job_status", id); }        // 0 pending, 1 done, 2 failed, -1 unknown or already delivered
  function jobAbiVersion() { return hostv("job_abi_version"); }

  function commandContext() {
    var who = str("player");
    var raw = str("args");
    var args = raw == "" ? [] : raw.split(" ").filter(function (w) { return w.length > 0; });
    return {
      sender: new Player(who), isConsole: who == "", name: str("command"), rawArgs: raw, args: args,
      reply: function (text) { hostv("command_reply", text); },
      fail: function (text) { hostv("command_fail", text); },
      arg: function (i) { return i < args.length ? args[i] : ""; },
      intArg: function (i, d) { var n = parseInt(args[i], 10); return isNaN(n) ? (d === undefined ? 0 : d) : n; },
      numberArg: function (i, d) { var n = parseFloat(args[i]); return isNaN(n) ? (d === undefined ? 0 : d) : n; },
      restFrom: function (i) { return args.slice(i).join(" "); }
    };
  }

  function fire(entry) {
    if (entry == "start") {
      started = true;
      for (var i = 0; i < wanted.length; i++) hostS("subscribe_event", wanted[i]);
      for (var c = 0; c < commands.length; c++) hostv("register_command", commands[c].name, commands[c].description, commands[c].level);
      for (var e = 0; e < enables.length; e++) enables[e]();
      return;
    }
    if (entry == "stop") { for (var d = 0; d < disables.length; d++) disables[d](); return; }
    if (entry == "on_command") {
      var ctx = commandContext();
      for (var k = 0; k < commands.length; k++) if (commands[k].name == ctx.name) { commands[k].fn(ctx); return; }
      return;
    }
    if (entry == "on_task") {
      var id = num("id");
      for (var t = 0; t < tasks.length; t++) {
        if (tasks[t].id == id) {
          var task = tasks[t];
          if (!task.repeat) tasks.splice(t, 1);
          task.fn(task.data);
          return;
        }
      }
      return;
    }
    if (entry == "on_job") {
      var jid = num("id");
      for (var j = 0; j < jobs.length; j++) {
        if (jobs[j].id == jid) {
          var jb = jobs.splice(j, 1)[0];
          jb.fn({ id: jid, value: num("value"), failed: num("failed") != 0, text: str("text") });
          return;
        }
      }
      return;
    }
    var list = handlers[entry];
    if (!list || !byEntry[entry]) return;
    var ev = byEntry[entry]();
    ev.cancelled = false;
    ev.cancel = function () { this.cancelled = true; };
    var tabBefore = ev.suggestions;
    var before = { message: ev.message, kickMessage: ev.kickMessage, drop: ev.drop, granted: ev.granted, hatching: ev.hatching, amount: ev.amount,
                   motd: ev.motd, maxPlayers: ev.maxPlayers, level: ev.level, time: ev.time, duration: ev.duration, ticks: ev.ticks };
    for (var h = 0; h < list.length; h++) list[h](ev);
    if (ev.cancelled) host("event_cancel");
    if (ev.message !== before.message && typeof ev.message === "string") hostS("event_set_message", ev.message);
    if (ev.kickMessage !== before.kickMessage && typeof ev.kickMessage === "string") hostS("event_set_message", ev.kickMessage);
    if (ev.drop !== before.drop) hostv("event_set_flag", ev.drop ? 1 : 0);
    if (ev.granted !== before.granted) hostv("event_set_flag", ev.granted ? 1 : 0);
    if (ev.hatching !== before.hatching) hostv("event_set_flag", ev.hatching ? 1 : 0);
    if (ev.amount !== before.amount && typeof ev.amount === "number") hostv("event_set_value", ev.amount);
    if (ev.motd !== before.motd && typeof ev.motd === "string") hostS("event_set_message", ev.motd);
    if (ev.maxPlayers !== before.maxPlayers && typeof ev.maxPlayers === "number") hostv("event_set_value", ev.maxPlayers);
    if (ev.level !== before.level && typeof ev.level === "number") hostv("event_set_value", ev.level);
    if (ev.time !== before.time && typeof ev.time === "number") hostv("event_set_value", ev.time);
    if (ev.suggestions && ev.suggestions.length > 0) hostS("event_set_message", ev.suggestions.join("\n"));
    if (ev.duration !== before.duration && typeof ev.duration === "number") hostv("event_set_value", ev.duration);
    if (ev.ticks !== before.ticks && typeof ev.ticks === "number") hostv("event_set_value", ev.ticks);
  }

  return {
    fire: fire, on: on, command: command, after: after, every: every, cancelTask: cancelTask, job: job, jobStatus: jobStatus, jobAbiVersion: jobAbiVersion, server: server, tokens: tokens,
    onEnable: function (fn) { enables.push(fn); }, onDisable: function (fn) { disables.push(fn); }
  };
})();

var on = __sdk.on, command = __sdk.command, after = __sdk.after, every = __sdk.every, cancelTask = __sdk.cancelTask;
var job = __sdk.job, jobStatus = __sdk.jobStatus, jobAbiVersion = __sdk.jobAbiVersion;
var onEnable = __sdk.onEnable, onDisable = __sdk.onDisable, server = __sdk.server;
var ChatEvent = __sdk.tokens.ChatEvent, PlayerCommandEvent = __sdk.tokens.PlayerCommandEvent, JoinEvent = __sdk.tokens.JoinEvent;
var LeaveEvent = __sdk.tokens.LeaveEvent, LoginEvent = __sdk.tokens.LoginEvent, MoveEvent = __sdk.tokens.MoveEvent;
var TeleportEvent = __sdk.tokens.TeleportEvent, ToggleEvent = __sdk.tokens.ToggleEvent, GamemodeChangeEvent = __sdk.tokens.GamemodeChangeEvent;
var CombustEvent = __sdk.tokens.CombustEvent, EntityTeleportEvent = __sdk.tokens.EntityTeleportEvent;
var PistonEvent = __sdk.tokens.PistonEvent;
var ProjectileHitEvent = __sdk.tokens.ProjectileHitEvent;
var BlockChangeEvent = __sdk.tokens.BlockChangeEvent;
var PortalEvent = __sdk.tokens.PortalEvent, FurnaceSmeltEvent = __sdk.tokens.FurnaceSmeltEvent;
var KickEvent = __sdk.tokens.KickEvent;
var TabCompleteEvent = __sdk.tokens.TabCompleteEvent;
var TargetEvent = __sdk.tokens.TargetEvent;
var AdvancementEvent = __sdk.tokens.AdvancementEvent;
var HopperMoveEvent = __sdk.tokens.HopperMoveEvent;
var SwapHandsEvent = __sdk.tokens.SwapHandsEvent, InventoryOpenEvent = __sdk.tokens.InventoryOpenEvent, PotionEffectEvent = __sdk.tokens.PotionEffectEvent;
var ItemHeldEvent = __sdk.tokens.ItemHeldEvent, InteractEvent = __sdk.tokens.InteractEvent, SwingEvent = __sdk.tokens.SwingEvent;
var UseItemEvent = __sdk.tokens.UseItemEvent, InteractEntityEvent = __sdk.tokens.InteractEntityEvent, BlockPlaceEvent = __sdk.tokens.BlockPlaceEvent;
var BlockBreakEvent = __sdk.tokens.BlockBreakEvent, DropItemEvent = __sdk.tokens.DropItemEvent, PickupItemEvent = __sdk.tokens.PickupItemEvent;
var ItemConsumeEvent = __sdk.tokens.ItemConsumeEvent, BedEnterEvent = __sdk.tokens.BedEnterEvent, BedLeaveEvent = __sdk.tokens.BedLeaveEvent;
var SignChangeEvent = __sdk.tokens.SignChangeEvent, BucketEmptyEvent = __sdk.tokens.BucketEmptyEvent, BucketFillEvent = __sdk.tokens.BucketFillEvent;
var InventoryClickEvent = __sdk.tokens.InventoryClickEvent, InventoryCloseEvent = __sdk.tokens.InventoryCloseEvent;
var PermissionCheckEvent = __sdk.tokens.PermissionCheckEvent, ExpChangeEvent = __sdk.tokens.ExpChangeEvent, RespawnEvent = __sdk.tokens.RespawnEvent;
var DeathEvent = __sdk.tokens.DeathEvent, FishEvent = __sdk.tokens.FishEvent, EggThrowEvent = __sdk.tokens.EggThrowEvent;
var ChangeWorldEvent = __sdk.tokens.ChangeWorldEvent, MainHandChangeEvent = __sdk.tokens.MainHandChangeEvent;
var CustomPayloadEvent = __sdk.tokens.CustomPayloadEvent, CustomClickEvent = __sdk.tokens.CustomClickEvent;
var EntityDamageEvent = __sdk.tokens.EntityDamageEvent, EntityDeathEvent = __sdk.tokens.EntityDeathEvent;
var EntitySpawnEvent = __sdk.tokens.EntitySpawnEvent, EntityRemoveEvent = __sdk.tokens.EntityRemoveEvent;
var ExplosionEvent = __sdk.tokens.ExplosionEvent, WeatherChangeEvent = __sdk.tokens.WeatherChangeEvent;
var BlockGrowEvent = __sdk.tokens.BlockGrowEvent, RedstoneEvent = __sdk.tokens.RedstoneEvent, SpawnChangeEvent = __sdk.tokens.SpawnChangeEvent;
var ChunkSendEvent = __sdk.tokens.ChunkSendEvent, ServerCommandEvent = __sdk.tokens.ServerCommandEvent, BroadcastEvent = __sdk.tokens.BroadcastEvent;
var ServerLoadEvent = __sdk.tokens.ServerLoadEvent, TickStartEvent = __sdk.tokens.TickStartEvent, TickEndEvent = __sdk.tokens.TickEndEvent;
var PacketEvent = __sdk.tokens.PacketEvent, HealEvent = __sdk.tokens.HealEvent, FoodLevelChangeEvent = __sdk.tokens.FoodLevelChangeEvent;
var LevelChangeEvent = __sdk.tokens.LevelChangeEvent, WorldSaveEvent = __sdk.tokens.WorldSaveEvent, TimeSetEvent = __sdk.tokens.TimeSetEvent;
var StatisticEvent = __sdk.tokens.StatisticEvent, ServerListPingEvent = __sdk.tokens.ServerListPingEvent, PreLoginEvent = __sdk.tokens.PreLoginEvent;


const unused = 1;
function start() { hostS("server_log", "module loaded"); }
function on_player_command() { hostS("server_log", "module saw " + hostv("event_str", "message")); }


;var __h = {};
if (typeof start === "function") __h.start = start;
if (typeof stop === "function") __h.stop = stop;
if (typeof on_player_chat === "function") __h.on_player_chat = on_player_chat;
if (typeof on_player_command === "function") __h.on_player_command = on_player_command;
if (typeof on_player_join === "function") __h.on_player_join = on_player_join;
if (typeof on_player_leave === "function") __h.on_player_leave = on_player_leave;
if (typeof on_player_move === "function") __h.on_player_move = on_player_move;
if (typeof on_player_teleport === "function") __h.on_player_teleport = on_player_teleport;
if (typeof on_player_toggle === "function") __h.on_player_toggle = on_player_toggle;
if (typeof on_player_gamemode_change === "function") __h.on_player_gamemode_change = on_player_gamemode_change;
if (typeof on_player_item_held === "function") __h.on_player_item_held = on_player_item_held;
if (typeof on_player_login === "function") __h.on_player_login = on_player_login;
if (typeof on_player_interact === "function") __h.on_player_interact = on_player_interact;
if (typeof on_block_place === "function") __h.on_block_place = on_block_place;
if (typeof on_server_command === "function") __h.on_server_command = on_server_command;
if (typeof on_server_broadcast === "function") __h.on_server_broadcast = on_server_broadcast;
if (typeof on_server_tick_start === "function") __h.on_server_tick_start = on_server_tick_start;
if (typeof on_server_tick_end === "function") __h.on_server_tick_end = on_server_tick_end;
if (typeof on_server_load === "function") __h.on_server_load = on_server_load;
if (typeof on_packet_received === "function") __h.on_packet_received = on_packet_received;
if (typeof on_block_redstone === "function") __h.on_block_redstone = on_block_redstone;
if (typeof on_spawn_change === "function") __h.on_spawn_change = on_spawn_change;
if (typeof on_block_grow === "function") __h.on_block_grow = on_block_grow;
if (typeof on_chunk_send === "function") __h.on_chunk_send = on_chunk_send;
if (typeof on_task === "function") __h.on_task = on_task;
if (typeof on_job === "function") __h.on_job = on_job;
if (typeof on_command === "function") __h.on_command = on_command;
if (typeof on_player_exp_change === "function") __h.on_player_exp_change = on_player_exp_change;
if (typeof on_player_respawn === "function") __h.on_player_respawn = on_player_respawn;
if (typeof on_player_death === "function") __h.on_player_death = on_player_death;
if (typeof on_player_swing === "function") __h.on_player_swing = on_player_swing;
if (typeof on_player_swap_hands === "function") __h.on_player_swap_hands = on_player_swap_hands;
if (typeof on_inventory_open === "function") __h.on_inventory_open = on_inventory_open;
if (typeof on_entity_potion_effect === "function") __h.on_entity_potion_effect = on_entity_potion_effect;
if (typeof on_entity_combust === "function") __h.on_entity_combust = on_entity_combust;
if (typeof on_entity_teleport === "function") __h.on_entity_teleport = on_entity_teleport;
if (typeof on_piston === "function") __h.on_piston = on_piston;
if (typeof on_projectile_hit === "function") __h.on_projectile_hit = on_projectile_hit;
if (typeof on_block_change === "function") __h.on_block_change = on_block_change;
if (typeof on_portal === "function") __h.on_portal = on_portal;
if (typeof on_furnace_smelt === "function") __h.on_furnace_smelt = on_furnace_smelt;
if (typeof on_player_kick === "function") __h.on_player_kick = on_player_kick;
if (typeof on_tab_complete === "function") __h.on_tab_complete = on_tab_complete;
if (typeof on_entity_target === "function") __h.on_entity_target = on_entity_target;
if (typeof on_advancement === "function") __h.on_advancement = on_advancement;
if (typeof on_hopper_move === "function") __h.on_hopper_move = on_hopper_move;
if (typeof on_player_use_item === "function") __h.on_player_use_item = on_player_use_item;
if (typeof on_player_interact_entity === "function") __h.on_player_interact_entity = on_player_interact_entity;
if (typeof on_player_custom_payload === "function") __h.on_player_custom_payload = on_player_custom_payload;
if (typeof on_player_main_hand_change === "function") __h.on_player_main_hand_change = on_player_main_hand_change;
if (typeof on_inventory_close === "function") __h.on_inventory_close = on_inventory_close;
if (typeof on_inventory_click === "function") __h.on_inventory_click = on_inventory_click;
if (typeof on_block_break === "function") __h.on_block_break = on_block_break;
if (typeof on_player_drop_item === "function") __h.on_player_drop_item = on_player_drop_item;
if (typeof on_player_pickup_item === "function") __h.on_player_pickup_item = on_player_pickup_item;
if (typeof on_player_item_consume === "function") __h.on_player_item_consume = on_player_item_consume;
if (typeof on_player_bed_enter === "function") __h.on_player_bed_enter = on_player_bed_enter;
if (typeof on_player_bed_leave === "function") __h.on_player_bed_leave = on_player_bed_leave;
if (typeof on_sign_change === "function") __h.on_sign_change = on_sign_change;
if (typeof on_bucket_empty === "function") __h.on_bucket_empty = on_bucket_empty;
if (typeof on_bucket_fill === "function") __h.on_bucket_fill = on_bucket_fill;
if (typeof on_permission_check === "function") __h.on_permission_check = on_permission_check;
if (typeof on_player_fish === "function") __h.on_player_fish = on_player_fish;
if (typeof on_player_egg_throw === "function") __h.on_player_egg_throw = on_player_egg_throw;
if (typeof on_custom_click === "function") __h.on_custom_click = on_custom_click;
if (typeof on_player_change_world === "function") __h.on_player_change_world = on_player_change_world;
if (typeof on_entity_damage === "function") __h.on_entity_damage = on_entity_damage;
if (typeof on_entity_death === "function") __h.on_entity_death = on_entity_death;
if (typeof on_entity_spawn === "function") __h.on_entity_spawn = on_entity_spawn;
if (typeof on_entity_remove === "function") __h.on_entity_remove = on_entity_remove;
if (typeof on_explosion === "function") __h.on_explosion = on_explosion;
if (typeof on_weather_change === "function") __h.on_weather_change = on_weather_change;
if (typeof on_entity_heal === "function") __h.on_entity_heal = on_entity_heal;
if (typeof on_player_food_change === "function") __h.on_player_food_change = on_player_food_change;
if (typeof on_player_statistic === "function") __h.on_player_statistic = on_player_statistic;
if (typeof on_server_list_ping === "function") __h.on_server_list_ping = on_server_list_ping;
if (typeof on_player_pre_login === "function") __h.on_player_pre_login = on_player_pre_login;
if (typeof on_player_level_change === "function") __h.on_player_level_change = on_player_level_change;
if (typeof on_world_save === "function") __h.on_world_save = on_world_save;
if (typeof on_time_set === "function") __h.on_time_set = on_time_set;
__h.__sdk = __sdk;
__aoeP.push({ name: "modstyle", h: __h });
})();
(function () {
var start, stop, on_player_chat, on_player_command, on_player_join, on_player_leave, on_player_move, on_player_teleport, on_player_toggle, on_player_gamemode_change, on_player_item_held, on_player_login, on_player_interact, on_block_place, on_server_command, on_server_broadcast, on_server_tick_start, on_server_tick_end, on_server_load, on_packet_received, on_block_redstone, on_spawn_change, on_block_grow, on_chunk_send, on_task, on_job, on_command, on_player_exp_change, on_player_respawn, on_player_death, on_player_swing, on_player_swap_hands, on_inventory_open, on_entity_potion_effect, on_entity_combust, on_entity_teleport, on_piston, on_projectile_hit, on_block_change, on_portal, on_furnace_smelt, on_player_kick, on_tab_complete, on_entity_target, on_advancement, on_hopper_move, on_player_use_item, on_player_interact_entity, on_player_custom_payload, on_player_main_hand_change, on_inventory_close, on_inventory_click, on_block_break, on_player_drop_item, on_player_pickup_item, on_player_item_consume, on_player_bed_enter, on_player_bed_leave, on_sign_change, on_bucket_empty, on_bucket_fill, on_permission_check, on_player_fish, on_player_egg_throw, on_custom_click, on_player_change_world, on_entity_damage, on_entity_death, on_entity_spawn, on_entity_remove, on_explosion, on_weather_change, on_entity_heal, on_player_food_change, on_player_statistic, on_server_list_ping, on_player_pre_login, on_player_level_change, on_world_save, on_time_set;
// The SDK of a server plugin written in JavaScript. The server puts this in front of every JavaScript plugin, so a plugin just uses it:
//
//   on(JoinEvent, function (e) { e.player.tell("Welcome, " + e.player.name + "!"); });
//   on(ChatEvent, function (e) { if (e.message == "!ping") { e.player.tell("pong!"); e.cancel(); } });
//   command("hello", "Say hello", 0, function (c) { c.reply("Hello, " + c.sender.name + "!"); });
//   after(100, function () { server.broadcast("five seconds later"); });
//
// The first argument of `on` is the event type, the way Bukkit's registerEvent names the event class. See docs/EVENTS.md for the events
// and docs/PLUGINS.md for the rest. (Plain functions called on_player_chat, on_command ... still work; this is the nicer way.)

var __sdk = (function () {
  var handlers = {};          // entry name -> [function]
  var commands = [];          // { name, description, level, fn }
  var tasks = [];             // { id, repeat, fn, data }
  var enables = [], disables = [];
  var wanted = [];
  var started = false;

  function str(k) { return hostv("event_str", k); }
  function num(k) { return hostv("event_num", k); }
  function want(entry) {
    for (var i = 0; i < wanted.length; i++) if (wanted[i] == entry) return;
    wanted.push(entry);
    if (started) hostS("subscribe_event", entry);
  }

  // ---- players and the server
  function Player(name) { this.name = name; }
  Player.prototype.tell = function (text) { return hostv("player_message_to", this.name, text); };
  Player.prototype.itemCount = function (item) { return hostv("player_item_count", this.name, item); };
  Player.prototype.setFood = function (level) { return hostv("player_set_food", this.name, level) == true; };
  Player.prototype.give = function (item, count) { return hostv("player_give", this.name, item, count) == true; };
  function hexBytes(s) { var out = []; for (var i = 0; i + 1 < s.length; i += 2) out.push(parseInt(s.substr(i, 2), 16)); return out; }
  function bytesHex(b) { var h = ""; for (var i = 0; i < b.length; i++) h += ("0" + (b[i] & 255).toString(16)).slice(-2); return h; }
  Player.prototype.sendPayload = function (channel, bytes) { return hostv("player_send_payload", this.name, channel, typeof bytes === "string" ? bytesHex(Array.prototype.map.call(bytes, function (c) { return c.charCodeAt(0); })) : bytesHex(bytes)) == true; };
  Player.prototype.hasChannel = function (channel) { return hostv("player_has_channel", this.name, channel) == true; };
  Player.prototype.channels = function () { var s = hostv("player_channels", this.name); return s ? s.split("\n") : []; };
  Player.prototype.hasCapability = function (name) { return hostv("player_has_capability", this.name, name) == true; };
  Player.prototype.modState = function (modId) { return hostv("player_mod_state", this.name, modId); };
  Player.prototype.jesterVersion = function () { return hostv("player_jester_version", this.name); };
  Player.prototype.kick = function (reason) { return hostv("player_kick", this.name, reason); };
  Player.prototype.teleport = function (x, y, z) {
    if (typeof x === "object") { y = x.y; z = x.z; x = x.x; }
    return hostv("player_teleport", this.name, x, y, z);
  };
  Player.prototype.setGamemode = function (mode) { return hostv("player_set_gamemode", this.name, mode); };
  Player.prototype.pos = function () {
    return { x: hostv("player_pos", this.name, "x"), y: hostv("player_pos", this.name, "y"), z: hostv("player_pos", this.name, "z") };
  };
  Player.prototype.isOnline = function () { return hostv("player_online", this.name); };
  function P() { return new Player(str("player")); }
  function vec(prefix) { return { x: num(prefix + "x"), y: num(prefix + "y"), z: num(prefix + "z") }; }
  function xyz() { return { x: num("x"), y: num("y"), z: num("z") }; }
  function merge(a, b) { for (var k in b) a[k] = b[k]; return a; }

  function materialFrom(text) {
    var w = String(text).split(" ");
    if (w.length < 13) return { known: false };
    return { known: true, matClass: w[0], density: Number(w[1]), fill: Number(w[2]), stiffness: Number(w[3]), damping: Number(w[4]),
             tensile: Number(w[5]), compressive: Number(w[6]), dragArea: Number(w[7]), breakThreshold: Number(w[8]),
             flammability: Number(w[9]), ignitability: Number(w[10]), liquid: w[11] === "1", indestructible: w[12] === "1" };
  }

  var server = {
    log: function (text) { hostS("server_log", text); },
    broadcast: function (text) { hostS("server_broadcast", text); },
    windAt: function (x, y, z) {
      var w = String(hostv("physics_wind_at", x, y, z)).split(" ");
      return w.length >= 4 ? { x: Number(w[0]), y: Number(w[1]), z: Number(w[2]), speed: Number(w[3]) } : { x: 0, y: 0, z: 0, speed: 0 };
    },
    materialByName: function (name) { return materialFrom(hostv("physics_material_by_name", name)); },
    materialAt: function (x, y, z) { return materialFrom(hostv("physics_material_at", x, y, z)); },
    massOf: function (name, volume) { var m = materialFrom(hostv("physics_material_by_name", name)); return m.known ? m.density * (volume === undefined ? 1 : volume) : 0; },
    solveRegion: function (x, y, z, nx, ny, nz, options) {
      options = options || {};
      var text = String(hostv("physics_solve", x + " " + y + " " + z, nx + " " + ny + " " + nz,
        options.floorAnchored === false ? "0" : "1", options.wind ? "1" : "0"));
      if (text.indexOf("error:") === 0) return { ok: false, error: text.substr(7), broken: [] };
      var lines = text.split("\n"), h = lines[0].split(" ");
      var kinds = ["none", "bending", "shear", "crush", "tension", "hang", "unsupported"];
      var r = { ok: true, error: "", maxRatio: Number(h[0]), converged: h[1] === "1", rounds: Number(h[2]), granular: Number(h[4]),
                caveIns: Number(h[5]), components: Number(h[6]), broken: [] };
      for (var i = 1; i < lines.length; i++) {
        var b = lines[i].split(" ");
        if (b.length >= 5) r.broken.push({ x: Number(b[0]), y: Number(b[1]), z: Number(b[2]), ratio: Number(b[3]), kind: kinds[Number(b[4])] || "none" });
      }
      return r;
    },
    advertiseCapability: function (name) { return hostv("server_advertise_capability", name) == true; },
    onlineCount: function () { return hostv("server_player_count"); },
    player: function (name) { return new Player(name); },
    blockAt: function (x, y, z) { return hostv("world_get_block", x, y, z); },
    setBlock: function (x, y, z, name) { return hostv("world_set_block", x, y, z, name) == true; },
    entityHealth: function (id) { return hostv("entity_health", id); },
    setEntityHealth: function (id, health) { return hostv("entity_set_health", id, health) == true; },
    entityPos: function (id) { return { x: hostv("entity_pos", id, "x"), y: hostv("entity_pos", id, "y"), z: hostv("entity_pos", id, "z") }; },
    teleportEntity: function (id, x, y, z) { return hostv("entity_teleport", id, x, y, z) == true; },
    setEntityOnFire: function (id, seconds) { return hostv("entity_ignite", id, seconds) == true; },
    removeEntity: function (id) { return hostv("entity_remove", id) == true; },
    time: function () { return hostv("world_time"); },
    setTime: function (ticks) { hostv("world_set_time", ticks); }
  };

  // ---- event types: [entry, build]. `build` makes the event object from what the host knows.
  var types = {
    ChatEvent: ["on_player_chat", function () { return { player: P(), message: str("message") }; }],
    PlayerCommandEvent: ["on_player_command", function () { return { player: P(), command: str("message") }; }],
    JoinEvent: ["on_player_join", function () { return { player: P() }; }],
    LeaveEvent: ["on_player_leave", function () { return { player: P() }; }],
    LoginEvent: ["on_player_login", function () { return { player: P(), kickMessage: str("message") }; }],
    MoveEvent: ["on_player_move", function () { return { player: P(), origin: vec("from_"), target: vec("to_") }; }],
    TeleportEvent: ["on_player_teleport", function () { return { player: P(), origin: vec("from_"), target: vec("to_") }; }],
    ToggleEvent: ["on_player_toggle", function () { return { player: P(), kind: num("kind"), on: num("value") != 0 }; }],
    GamemodeChangeEvent: ["on_player_gamemode_change", function () { return { player: P(), previous: num("previous"), next: num("next") }; }],
    ItemHeldEvent: ["on_player_item_held", function () { return { player: P(), previousSlot: num("previous"), nextSlot: num("next") }; }],
    InteractEvent: ["on_player_interact", function () { return merge({ player: P(), action: num("action") }, xyz()); }],
    InventoryOpenEvent: ["on_inventory_open", function () { return { player: P(), window: num("window") }; }],
    PotionEffectEvent: ["on_entity_potion_effect", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), effect: str("effect"), duration: num("duration"), amplifier: num("amplifier") };
    }],
    CombustEvent: ["on_entity_combust", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), ticks: num("ticks") }; }],
    EntityTeleportEvent: ["on_entity_teleport", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), origin: vec("from_"), target: vec("to_") };
    }],
    PistonEvent: ["on_piston", function () {
      return { x: num("x"), y: num("y"), z: num("z"), extend: num("extend") != 0, moved: num("moved"), broken: num("broken") };
    }],
    ProjectileHitEvent: ["on_projectile_hit", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), ownerId: num("owner_id"), hitEntity: num("on_entity") != 0,
               targetId: num("target_id"), x: num("x"), y: num("y"), z: num("z") };
    }],
    BlockChangeEvent: ["on_block_change", function () {
      return { x: num("x"), y: num("y"), z: num("z"), before: str("before"), after: str("after") };
    }],
    PortalEvent: ["on_portal", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), x: num("x"), y: num("y"), z: num("z"), target: str("target") };
    }],
    FurnaceSmeltEvent: ["on_furnace_smelt", function () {
      return { x: num("x"), y: num("y"), z: num("z"), input: str("input"), output: str("output") };
    }],
    KickEvent: ["on_player_kick", function () { return { player: P(), reason: str("message") }; }],
    TabCompleteEvent: ["on_tab_complete", function () { return { player: P(), buffer: str("buffer"), suggestions: [] }; }],
    TargetEvent: ["on_entity_target", function () {
      return { mobId: num("mob_id"), mobType: str("mob_type"), targetId: num("target_id"), targetType: str("target_type") };
    }],
    AdvancementEvent: ["on_advancement", function () { return { player: P(), advancement: str("advancement") }; }],
    HopperMoveEvent: ["on_hopper_move", function () { return { x: num("x"), y: num("y"), z: num("z"), item: str("item") }; }],
    SwapHandsEvent: ["on_player_swap_hands", function () { return { player: P() }; }],
    SwingEvent: ["on_player_swing", function () { return { player: P() }; }],
    UseItemEvent: ["on_player_use_item", function () { return { player: P() }; }],
    InteractEntityEvent: ["on_player_interact_entity", function () {
      return { player: P(), entityId: num("entity_id"), action: num("action"), sneaking: num("sneaking") != 0, known: num("known") != 0 };
    }],
    BlockPlaceEvent: ["on_block_place", function () {
      return merge({ player: P(), blockName: str("placed"), against: str("clicked") }, xyz());
    }],
    BlockBreakEvent: ["on_block_break", function () {
      return merge({ player: P(), blockName: str("block"), drop: num("flag") != 0 }, xyz());
    }],
    DropItemEvent: ["on_player_drop_item", function () { return { player: P(), item: str("item"), count: num("count") }; }],
    PickupItemEvent: ["on_player_pickup_item", function () {
      return { player: P(), item: str("item"), count: num("count"), entityId: num("entity_id") };
    }],
    ItemConsumeEvent: ["on_player_item_consume", function () { return { player: P(), item: str("item") }; }],
    BedEnterEvent: ["on_player_bed_enter", function () { return merge({ player: P() }, xyz()); }],
    BedLeaveEvent: ["on_player_bed_leave", function () { return merge({ player: P() }, xyz()); }],
    SignChangeEvent: ["on_sign_change", function () {
      return merge({ player: P(), lines: [str("line0"), str("line1"), str("line2"), str("line3")] }, xyz());
    }],
    BucketEmptyEvent: ["on_bucket_empty", function () { return merge({ player: P(), bucket: str("bucket") }, xyz()); }],
    BucketFillEvent: ["on_bucket_fill", function () { return merge({ player: P(), bucket: str("bucket") }, xyz()); }],
    InventoryClickEvent: ["on_inventory_click", function () {
      return { player: P(), window: num("window"), clickType: num("click_type"), slot: num("slot"), rawSlot: num("raw_slot"),
               hotbarButton: num("hotbar_button") };
    }],
    InventoryCloseEvent: ["on_inventory_close", function () { return { player: P(), window: num("window") }; }],
    PermissionCheckEvent: ["on_permission_check", function () { return { player: P(), node: str("node"), granted: num("flag") != 0 }; }],
    ExpChangeEvent: ["on_player_exp_change", function () { return { player: P(), amount: num("amount") }; }],
    RespawnEvent: ["on_player_respawn", function () { return { player: P(), pos: xyz(), alive: num("alive") != 0 }; }],
    DeathEvent: ["on_player_death", function () { return { player: P(), message: str("message") }; }],
    FishEvent: ["on_player_fish", function () { return { player: P(), state: num("state"), caught: str("caught"), exp: num("exp") }; }],
    EggThrowEvent: ["on_player_egg_throw", function () {
      return { player: P(), hatching: num("hatching") != 0, numHatches: num("num_hatches"), hatchingType: str("hatching_type") };
    }],
    ChangeWorldEvent: ["on_player_change_world", function () {
      return { player: P(), pos: xyz(), yaw: num("yaw"), pitch: num("pitch") };
    }],
    MainHandChangeEvent: ["on_player_main_hand_change", function () { return { player: P(), hand: num("hand") }; }],
    CustomPayloadEvent: ["on_player_custom_payload", function () { return { player: P(), channel: str("channel"), length: num("length"), data: hexBytes(str("data")) }; }],
    CustomClickEvent: ["on_custom_click", function () { return { player: P(), id: str("id"), length: num("length") }; }],
    EntityDamageEvent: ["on_entity_damage", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), damageType: str("damage_type"), amount: num("amount"),
               attackerId: num("attacker_id") };
    }],
    EntityDeathEvent: ["on_entity_death", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), damageType: str("damage_type"), killerId: num("killer_id") };
    }],
    EntitySpawnEvent: ["on_entity_spawn", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), pos: xyz() }; }],
    EntityRemoveEvent: ["on_entity_remove", function () { return { entityId: num("entity_id"), entityType: str("entity_type") }; }],
    ExplosionEvent: ["on_explosion", function () { return { pos: xyz(), power: num("power") }; }],
    WeatherChangeEvent: ["on_weather_change", function () { return { raining: num("raining") != 0, thundering: num("thundering") != 0 }; }],
    BlockGrowEvent: ["on_block_grow", function () { return merge({ before: str("old_block"), after: str("new_block") }, xyz()); }],
    RedstoneEvent: ["on_block_redstone", function () {
      return merge({ oldCurrent: num("old_current"), newCurrent: num("new_current") }, xyz());
    }],
    SpawnChangeEvent: ["on_spawn_change", function () {
      return { previous: vec("previous_"), next: vec("next_"), yaw: num("yaw"), pitch: num("pitch") };
    }],
    ChunkSendEvent: ["on_chunk_send", function () { return { x: num("x"), z: num("z") }; }],
    ServerCommandEvent: ["on_server_command", function () { return { command: str("command") }; }],
    BroadcastEvent: ["on_server_broadcast", function () { return { message: str("message"), sender: str("sender") }; }],
    ServerLoadEvent: ["on_server_load", function () { return { reload: num("reload") != 0 }; }],
    TickStartEvent: ["on_server_tick_start", function () { return { tick: num("tick") }; }],
    TickEndEvent: ["on_server_tick_end", function () { return { tick: num("tick"), durationNs: num("duration_ns") }; }],
    LevelChangeEvent: ["on_player_level_change", function () { return { player: P(), previous: num("previous"), level: num("level") }; }],
    WorldSaveEvent: ["on_world_save", function () { return { saved: true }; }],
    TimeSetEvent: ["on_time_set", function () { return { previous: num("previous"), time: num("time") }; }],
    HealEvent: ["on_entity_heal", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), amount: num("amount") }; }],
    FoodLevelChangeEvent: ["on_player_food_change", function () { return { player: P(), level: num("level"), previous: num("previous") }; }],
    StatisticEvent: ["on_player_statistic", function () { return { player: P(), category: num("category"), statId: num("stat_id"), amount: num("amount") }; }],
    ServerListPingEvent: ["on_server_list_ping", function () { return { address: str("address"), motd: str("message"), online: num("online"), maxPlayers: num("max") }; }],
    PreLoginEvent: ["on_player_pre_login", function () { return { name: str("player"), address: str("address"), kickMessage: str("message") }; }],
    PacketEvent: ["on_packet_received", function () {
      return { player: P(), packetId: num("packet_id"), length: num("length") };
    }]
  };
  var byEntry = {};
  var tokens = {};
  for (var name in types) {
    tokens[name] = { name: name, entry: types[name][0] };
    byEntry[types[name][0]] = types[name][1];
  }

  function on(type, fn) {
    var entry = typeof type === "string" ? type : type.entry;
    if (!handlers[entry]) handlers[entry] = [];
    handlers[entry].push(fn);
    want(entry);
  }

  function command(name, description, level, fn) {
    commands.push({ name: name, description: description, level: level, fn: fn });
    want("on_command");
    if (started) hostv("register_command", name, description, level);
  }
  function addTask(id, repeat, fn, data) { want("on_task"); tasks.push({ id: id, repeat: repeat, fn: fn, data: data }); return id; }
  function after(ticks, fn, data) { return addTask(hostv("schedule_after", ticks), false, fn, data); }
  function every(ticks, fn, data) { return addTask(hostv("schedule_repeat", ticks), true, fn, data); }
  function cancelTask(id) {
    hostv("schedule_cancel", id);
    tasks = tasks.filter(function (t) { return t.id != id; });
  }

  // ---- jobs on the server's worker threads (docs/PLUGIN_JOBS.md). `kind` names a server kernel ("fnv1a", "primes", "sort"): plugin code itself never
  // runs on a worker. job() answers an id at once (-1 unknown kind, -2 input over 64 KiB); `fn({ id, value, failed, text })` runs later, on the
  // tick thread, with the jobs of this plugin delivered in the order they were submitted. job_abi_version is 1.
  var jobs = [];              // { id, fn }
  function job(kind, input, fn) {
    var id = hostv("job_submit", kind, String(input));
    if (id > 0) { want("on_job"); jobs.push({ id: id, fn: fn }); }
    return id;
  }
  function jobStatus(id) { return hostv("job_status", id); }        // 0 pending, 1 done, 2 failed, -1 unknown or already delivered
  function jobAbiVersion() { return hostv("job_abi_version"); }

  function commandContext() {
    var who = str("player");
    var raw = str("args");
    var args = raw == "" ? [] : raw.split(" ").filter(function (w) { return w.length > 0; });
    return {
      sender: new Player(who), isConsole: who == "", name: str("command"), rawArgs: raw, args: args,
      reply: function (text) { hostv("command_reply", text); },
      fail: function (text) { hostv("command_fail", text); },
      arg: function (i) { return i < args.length ? args[i] : ""; },
      intArg: function (i, d) { var n = parseInt(args[i], 10); return isNaN(n) ? (d === undefined ? 0 : d) : n; },
      numberArg: function (i, d) { var n = parseFloat(args[i]); return isNaN(n) ? (d === undefined ? 0 : d) : n; },
      restFrom: function (i) { return args.slice(i).join(" "); }
    };
  }

  function fire(entry) {
    if (entry == "start") {
      started = true;
      for (var i = 0; i < wanted.length; i++) hostS("subscribe_event", wanted[i]);
      for (var c = 0; c < commands.length; c++) hostv("register_command", commands[c].name, commands[c].description, commands[c].level);
      for (var e = 0; e < enables.length; e++) enables[e]();
      return;
    }
    if (entry == "stop") { for (var d = 0; d < disables.length; d++) disables[d](); return; }
    if (entry == "on_command") {
      var ctx = commandContext();
      for (var k = 0; k < commands.length; k++) if (commands[k].name == ctx.name) { commands[k].fn(ctx); return; }
      return;
    }
    if (entry == "on_task") {
      var id = num("id");
      for (var t = 0; t < tasks.length; t++) {
        if (tasks[t].id == id) {
          var task = tasks[t];
          if (!task.repeat) tasks.splice(t, 1);
          task.fn(task.data);
          return;
        }
      }
      return;
    }
    if (entry == "on_job") {
      var jid = num("id");
      for (var j = 0; j < jobs.length; j++) {
        if (jobs[j].id == jid) {
          var jb = jobs.splice(j, 1)[0];
          jb.fn({ id: jid, value: num("value"), failed: num("failed") != 0, text: str("text") });
          return;
        }
      }
      return;
    }
    var list = handlers[entry];
    if (!list || !byEntry[entry]) return;
    var ev = byEntry[entry]();
    ev.cancelled = false;
    ev.cancel = function () { this.cancelled = true; };
    var tabBefore = ev.suggestions;
    var before = { message: ev.message, kickMessage: ev.kickMessage, drop: ev.drop, granted: ev.granted, hatching: ev.hatching, amount: ev.amount,
                   motd: ev.motd, maxPlayers: ev.maxPlayers, level: ev.level, time: ev.time, duration: ev.duration, ticks: ev.ticks };
    for (var h = 0; h < list.length; h++) list[h](ev);
    if (ev.cancelled) host("event_cancel");
    if (ev.message !== before.message && typeof ev.message === "string") hostS("event_set_message", ev.message);
    if (ev.kickMessage !== before.kickMessage && typeof ev.kickMessage === "string") hostS("event_set_message", ev.kickMessage);
    if (ev.drop !== before.drop) hostv("event_set_flag", ev.drop ? 1 : 0);
    if (ev.granted !== before.granted) hostv("event_set_flag", ev.granted ? 1 : 0);
    if (ev.hatching !== before.hatching) hostv("event_set_flag", ev.hatching ? 1 : 0);
    if (ev.amount !== before.amount && typeof ev.amount === "number") hostv("event_set_value", ev.amount);
    if (ev.motd !== before.motd && typeof ev.motd === "string") hostS("event_set_message", ev.motd);
    if (ev.maxPlayers !== before.maxPlayers && typeof ev.maxPlayers === "number") hostv("event_set_value", ev.maxPlayers);
    if (ev.level !== before.level && typeof ev.level === "number") hostv("event_set_value", ev.level);
    if (ev.time !== before.time && typeof ev.time === "number") hostv("event_set_value", ev.time);
    if (ev.suggestions && ev.suggestions.length > 0) hostS("event_set_message", ev.suggestions.join("\n"));
    if (ev.duration !== before.duration && typeof ev.duration === "number") hostv("event_set_value", ev.duration);
    if (ev.ticks !== before.ticks && typeof ev.ticks === "number") hostv("event_set_value", ev.ticks);
  }

  return {
    fire: fire, on: on, command: command, after: after, every: every, cancelTask: cancelTask, job: job, jobStatus: jobStatus, jobAbiVersion: jobAbiVersion, server: server, tokens: tokens,
    onEnable: function (fn) { enables.push(fn); }, onDisable: function (fn) { disables.push(fn); }
  };
})();

var on = __sdk.on, command = __sdk.command, after = __sdk.after, every = __sdk.every, cancelTask = __sdk.cancelTask;
var job = __sdk.job, jobStatus = __sdk.jobStatus, jobAbiVersion = __sdk.jobAbiVersion;
var onEnable = __sdk.onEnable, onDisable = __sdk.onDisable, server = __sdk.server;
var ChatEvent = __sdk.tokens.ChatEvent, PlayerCommandEvent = __sdk.tokens.PlayerCommandEvent, JoinEvent = __sdk.tokens.JoinEvent;
var LeaveEvent = __sdk.tokens.LeaveEvent, LoginEvent = __sdk.tokens.LoginEvent, MoveEvent = __sdk.tokens.MoveEvent;
var TeleportEvent = __sdk.tokens.TeleportEvent, ToggleEvent = __sdk.tokens.ToggleEvent, GamemodeChangeEvent = __sdk.tokens.GamemodeChangeEvent;
var CombustEvent = __sdk.tokens.CombustEvent, EntityTeleportEvent = __sdk.tokens.EntityTeleportEvent;
var PistonEvent = __sdk.tokens.PistonEvent;
var ProjectileHitEvent = __sdk.tokens.ProjectileHitEvent;
var BlockChangeEvent = __sdk.tokens.BlockChangeEvent;
var PortalEvent = __sdk.tokens.PortalEvent, FurnaceSmeltEvent = __sdk.tokens.FurnaceSmeltEvent;
var KickEvent = __sdk.tokens.KickEvent;
var TabCompleteEvent = __sdk.tokens.TabCompleteEvent;
var TargetEvent = __sdk.tokens.TargetEvent;
var AdvancementEvent = __sdk.tokens.AdvancementEvent;
var HopperMoveEvent = __sdk.tokens.HopperMoveEvent;
var SwapHandsEvent = __sdk.tokens.SwapHandsEvent, InventoryOpenEvent = __sdk.tokens.InventoryOpenEvent, PotionEffectEvent = __sdk.tokens.PotionEffectEvent;
var ItemHeldEvent = __sdk.tokens.ItemHeldEvent, InteractEvent = __sdk.tokens.InteractEvent, SwingEvent = __sdk.tokens.SwingEvent;
var UseItemEvent = __sdk.tokens.UseItemEvent, InteractEntityEvent = __sdk.tokens.InteractEntityEvent, BlockPlaceEvent = __sdk.tokens.BlockPlaceEvent;
var BlockBreakEvent = __sdk.tokens.BlockBreakEvent, DropItemEvent = __sdk.tokens.DropItemEvent, PickupItemEvent = __sdk.tokens.PickupItemEvent;
var ItemConsumeEvent = __sdk.tokens.ItemConsumeEvent, BedEnterEvent = __sdk.tokens.BedEnterEvent, BedLeaveEvent = __sdk.tokens.BedLeaveEvent;
var SignChangeEvent = __sdk.tokens.SignChangeEvent, BucketEmptyEvent = __sdk.tokens.BucketEmptyEvent, BucketFillEvent = __sdk.tokens.BucketFillEvent;
var InventoryClickEvent = __sdk.tokens.InventoryClickEvent, InventoryCloseEvent = __sdk.tokens.InventoryCloseEvent;
var PermissionCheckEvent = __sdk.tokens.PermissionCheckEvent, ExpChangeEvent = __sdk.tokens.ExpChangeEvent, RespawnEvent = __sdk.tokens.RespawnEvent;
var DeathEvent = __sdk.tokens.DeathEvent, FishEvent = __sdk.tokens.FishEvent, EggThrowEvent = __sdk.tokens.EggThrowEvent;
var ChangeWorldEvent = __sdk.tokens.ChangeWorldEvent, MainHandChangeEvent = __sdk.tokens.MainHandChangeEvent;
var CustomPayloadEvent = __sdk.tokens.CustomPayloadEvent, CustomClickEvent = __sdk.tokens.CustomClickEvent;
var EntityDamageEvent = __sdk.tokens.EntityDamageEvent, EntityDeathEvent = __sdk.tokens.EntityDeathEvent;
var EntitySpawnEvent = __sdk.tokens.EntitySpawnEvent, EntityRemoveEvent = __sdk.tokens.EntityRemoveEvent;
var ExplosionEvent = __sdk.tokens.ExplosionEvent, WeatherChangeEvent = __sdk.tokens.WeatherChangeEvent;
var BlockGrowEvent = __sdk.tokens.BlockGrowEvent, RedstoneEvent = __sdk.tokens.RedstoneEvent, SpawnChangeEvent = __sdk.tokens.SpawnChangeEvent;
var ChunkSendEvent = __sdk.tokens.ChunkSendEvent, ServerCommandEvent = __sdk.tokens.ServerCommandEvent, BroadcastEvent = __sdk.tokens.BroadcastEvent;
var ServerLoadEvent = __sdk.tokens.ServerLoadEvent, TickStartEvent = __sdk.tokens.TickStartEvent, TickEndEvent = __sdk.tokens.TickEndEvent;
var PacketEvent = __sdk.tokens.PacketEvent, HealEvent = __sdk.tokens.HealEvent, FoodLevelChangeEvent = __sdk.tokens.FoodLevelChangeEvent;
var LevelChangeEvent = __sdk.tokens.LevelChangeEvent, WorldSaveEvent = __sdk.tokens.WorldSaveEvent, TimeSetEvent = __sdk.tokens.TimeSetEvent;
var StatisticEvent = __sdk.tokens.StatisticEvent, ServerListPingEvent = __sdk.tokens.ServerListPingEvent, PreLoginEvent = __sdk.tokens.PreLoginEvent;

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


;var __h = {};
if (typeof start === "function") __h.start = start;
if (typeof stop === "function") __h.stop = stop;
if (typeof on_player_chat === "function") __h.on_player_chat = on_player_chat;
if (typeof on_player_command === "function") __h.on_player_command = on_player_command;
if (typeof on_player_join === "function") __h.on_player_join = on_player_join;
if (typeof on_player_leave === "function") __h.on_player_leave = on_player_leave;
if (typeof on_player_move === "function") __h.on_player_move = on_player_move;
if (typeof on_player_teleport === "function") __h.on_player_teleport = on_player_teleport;
if (typeof on_player_toggle === "function") __h.on_player_toggle = on_player_toggle;
if (typeof on_player_gamemode_change === "function") __h.on_player_gamemode_change = on_player_gamemode_change;
if (typeof on_player_item_held === "function") __h.on_player_item_held = on_player_item_held;
if (typeof on_player_login === "function") __h.on_player_login = on_player_login;
if (typeof on_player_interact === "function") __h.on_player_interact = on_player_interact;
if (typeof on_block_place === "function") __h.on_block_place = on_block_place;
if (typeof on_server_command === "function") __h.on_server_command = on_server_command;
if (typeof on_server_broadcast === "function") __h.on_server_broadcast = on_server_broadcast;
if (typeof on_server_tick_start === "function") __h.on_server_tick_start = on_server_tick_start;
if (typeof on_server_tick_end === "function") __h.on_server_tick_end = on_server_tick_end;
if (typeof on_server_load === "function") __h.on_server_load = on_server_load;
if (typeof on_packet_received === "function") __h.on_packet_received = on_packet_received;
if (typeof on_block_redstone === "function") __h.on_block_redstone = on_block_redstone;
if (typeof on_spawn_change === "function") __h.on_spawn_change = on_spawn_change;
if (typeof on_block_grow === "function") __h.on_block_grow = on_block_grow;
if (typeof on_chunk_send === "function") __h.on_chunk_send = on_chunk_send;
if (typeof on_task === "function") __h.on_task = on_task;
if (typeof on_job === "function") __h.on_job = on_job;
if (typeof on_command === "function") __h.on_command = on_command;
if (typeof on_player_exp_change === "function") __h.on_player_exp_change = on_player_exp_change;
if (typeof on_player_respawn === "function") __h.on_player_respawn = on_player_respawn;
if (typeof on_player_death === "function") __h.on_player_death = on_player_death;
if (typeof on_player_swing === "function") __h.on_player_swing = on_player_swing;
if (typeof on_player_swap_hands === "function") __h.on_player_swap_hands = on_player_swap_hands;
if (typeof on_inventory_open === "function") __h.on_inventory_open = on_inventory_open;
if (typeof on_entity_potion_effect === "function") __h.on_entity_potion_effect = on_entity_potion_effect;
if (typeof on_entity_combust === "function") __h.on_entity_combust = on_entity_combust;
if (typeof on_entity_teleport === "function") __h.on_entity_teleport = on_entity_teleport;
if (typeof on_piston === "function") __h.on_piston = on_piston;
if (typeof on_projectile_hit === "function") __h.on_projectile_hit = on_projectile_hit;
if (typeof on_block_change === "function") __h.on_block_change = on_block_change;
if (typeof on_portal === "function") __h.on_portal = on_portal;
if (typeof on_furnace_smelt === "function") __h.on_furnace_smelt = on_furnace_smelt;
if (typeof on_player_kick === "function") __h.on_player_kick = on_player_kick;
if (typeof on_tab_complete === "function") __h.on_tab_complete = on_tab_complete;
if (typeof on_entity_target === "function") __h.on_entity_target = on_entity_target;
if (typeof on_advancement === "function") __h.on_advancement = on_advancement;
if (typeof on_hopper_move === "function") __h.on_hopper_move = on_hopper_move;
if (typeof on_player_use_item === "function") __h.on_player_use_item = on_player_use_item;
if (typeof on_player_interact_entity === "function") __h.on_player_interact_entity = on_player_interact_entity;
if (typeof on_player_custom_payload === "function") __h.on_player_custom_payload = on_player_custom_payload;
if (typeof on_player_main_hand_change === "function") __h.on_player_main_hand_change = on_player_main_hand_change;
if (typeof on_inventory_close === "function") __h.on_inventory_close = on_inventory_close;
if (typeof on_inventory_click === "function") __h.on_inventory_click = on_inventory_click;
if (typeof on_block_break === "function") __h.on_block_break = on_block_break;
if (typeof on_player_drop_item === "function") __h.on_player_drop_item = on_player_drop_item;
if (typeof on_player_pickup_item === "function") __h.on_player_pickup_item = on_player_pickup_item;
if (typeof on_player_item_consume === "function") __h.on_player_item_consume = on_player_item_consume;
if (typeof on_player_bed_enter === "function") __h.on_player_bed_enter = on_player_bed_enter;
if (typeof on_player_bed_leave === "function") __h.on_player_bed_leave = on_player_bed_leave;
if (typeof on_sign_change === "function") __h.on_sign_change = on_sign_change;
if (typeof on_bucket_empty === "function") __h.on_bucket_empty = on_bucket_empty;
if (typeof on_bucket_fill === "function") __h.on_bucket_fill = on_bucket_fill;
if (typeof on_permission_check === "function") __h.on_permission_check = on_permission_check;
if (typeof on_player_fish === "function") __h.on_player_fish = on_player_fish;
if (typeof on_player_egg_throw === "function") __h.on_player_egg_throw = on_player_egg_throw;
if (typeof on_custom_click === "function") __h.on_custom_click = on_custom_click;
if (typeof on_player_change_world === "function") __h.on_player_change_world = on_player_change_world;
if (typeof on_entity_damage === "function") __h.on_entity_damage = on_entity_damage;
if (typeof on_entity_death === "function") __h.on_entity_death = on_entity_death;
if (typeof on_entity_spawn === "function") __h.on_entity_spawn = on_entity_spawn;
if (typeof on_entity_remove === "function") __h.on_entity_remove = on_entity_remove;
if (typeof on_explosion === "function") __h.on_explosion = on_explosion;
if (typeof on_weather_change === "function") __h.on_weather_change = on_weather_change;
if (typeof on_entity_heal === "function") __h.on_entity_heal = on_entity_heal;
if (typeof on_player_food_change === "function") __h.on_player_food_change = on_player_food_change;
if (typeof on_player_statistic === "function") __h.on_player_statistic = on_player_statistic;
if (typeof on_server_list_ping === "function") __h.on_server_list_ping = on_server_list_ping;
if (typeof on_player_pre_login === "function") __h.on_player_pre_login = on_player_pre_login;
if (typeof on_player_level_change === "function") __h.on_player_level_change = on_player_level_change;
if (typeof on_world_save === "function") __h.on_world_save = on_world_save;
if (typeof on_time_set === "function") __h.on_time_set = on_time_set;
__h.__sdk = __sdk;
__aoeP.push({ name: "sched", h: __h });
})();
(function () {
var start, stop, on_player_chat, on_player_command, on_player_join, on_player_leave, on_player_move, on_player_teleport, on_player_toggle, on_player_gamemode_change, on_player_item_held, on_player_login, on_player_interact, on_block_place, on_server_command, on_server_broadcast, on_server_tick_start, on_server_tick_end, on_server_load, on_packet_received, on_block_redstone, on_spawn_change, on_block_grow, on_chunk_send, on_task, on_job, on_command, on_player_exp_change, on_player_respawn, on_player_death, on_player_swing, on_player_swap_hands, on_inventory_open, on_entity_potion_effect, on_entity_combust, on_entity_teleport, on_piston, on_projectile_hit, on_block_change, on_portal, on_furnace_smelt, on_player_kick, on_tab_complete, on_entity_target, on_advancement, on_hopper_move, on_player_use_item, on_player_interact_entity, on_player_custom_payload, on_player_main_hand_change, on_inventory_close, on_inventory_click, on_block_break, on_player_drop_item, on_player_pickup_item, on_player_item_consume, on_player_bed_enter, on_player_bed_leave, on_sign_change, on_bucket_empty, on_bucket_fill, on_permission_check, on_player_fish, on_player_egg_throw, on_custom_click, on_player_change_world, on_entity_damage, on_entity_death, on_entity_spawn, on_entity_remove, on_explosion, on_weather_change, on_entity_heal, on_player_food_change, on_player_statistic, on_server_list_ping, on_player_pre_login, on_player_level_change, on_world_save, on_time_set;
// The SDK of a server plugin written in JavaScript. The server puts this in front of every JavaScript plugin, so a plugin just uses it:
//
//   on(JoinEvent, function (e) { e.player.tell("Welcome, " + e.player.name + "!"); });
//   on(ChatEvent, function (e) { if (e.message == "!ping") { e.player.tell("pong!"); e.cancel(); } });
//   command("hello", "Say hello", 0, function (c) { c.reply("Hello, " + c.sender.name + "!"); });
//   after(100, function () { server.broadcast("five seconds later"); });
//
// The first argument of `on` is the event type, the way Bukkit's registerEvent names the event class. See docs/EVENTS.md for the events
// and docs/PLUGINS.md for the rest. (Plain functions called on_player_chat, on_command ... still work; this is the nicer way.)

var __sdk = (function () {
  var handlers = {};          // entry name -> [function]
  var commands = [];          // { name, description, level, fn }
  var tasks = [];             // { id, repeat, fn, data }
  var enables = [], disables = [];
  var wanted = [];
  var started = false;

  function str(k) { return hostv("event_str", k); }
  function num(k) { return hostv("event_num", k); }
  function want(entry) {
    for (var i = 0; i < wanted.length; i++) if (wanted[i] == entry) return;
    wanted.push(entry);
    if (started) hostS("subscribe_event", entry);
  }

  // ---- players and the server
  function Player(name) { this.name = name; }
  Player.prototype.tell = function (text) { return hostv("player_message_to", this.name, text); };
  Player.prototype.itemCount = function (item) { return hostv("player_item_count", this.name, item); };
  Player.prototype.setFood = function (level) { return hostv("player_set_food", this.name, level) == true; };
  Player.prototype.give = function (item, count) { return hostv("player_give", this.name, item, count) == true; };
  function hexBytes(s) { var out = []; for (var i = 0; i + 1 < s.length; i += 2) out.push(parseInt(s.substr(i, 2), 16)); return out; }
  function bytesHex(b) { var h = ""; for (var i = 0; i < b.length; i++) h += ("0" + (b[i] & 255).toString(16)).slice(-2); return h; }
  Player.prototype.sendPayload = function (channel, bytes) { return hostv("player_send_payload", this.name, channel, typeof bytes === "string" ? bytesHex(Array.prototype.map.call(bytes, function (c) { return c.charCodeAt(0); })) : bytesHex(bytes)) == true; };
  Player.prototype.hasChannel = function (channel) { return hostv("player_has_channel", this.name, channel) == true; };
  Player.prototype.channels = function () { var s = hostv("player_channels", this.name); return s ? s.split("\n") : []; };
  Player.prototype.hasCapability = function (name) { return hostv("player_has_capability", this.name, name) == true; };
  Player.prototype.modState = function (modId) { return hostv("player_mod_state", this.name, modId); };
  Player.prototype.jesterVersion = function () { return hostv("player_jester_version", this.name); };
  Player.prototype.kick = function (reason) { return hostv("player_kick", this.name, reason); };
  Player.prototype.teleport = function (x, y, z) {
    if (typeof x === "object") { y = x.y; z = x.z; x = x.x; }
    return hostv("player_teleport", this.name, x, y, z);
  };
  Player.prototype.setGamemode = function (mode) { return hostv("player_set_gamemode", this.name, mode); };
  Player.prototype.pos = function () {
    return { x: hostv("player_pos", this.name, "x"), y: hostv("player_pos", this.name, "y"), z: hostv("player_pos", this.name, "z") };
  };
  Player.prototype.isOnline = function () { return hostv("player_online", this.name); };
  function P() { return new Player(str("player")); }
  function vec(prefix) { return { x: num(prefix + "x"), y: num(prefix + "y"), z: num(prefix + "z") }; }
  function xyz() { return { x: num("x"), y: num("y"), z: num("z") }; }
  function merge(a, b) { for (var k in b) a[k] = b[k]; return a; }

  function materialFrom(text) {
    var w = String(text).split(" ");
    if (w.length < 13) return { known: false };
    return { known: true, matClass: w[0], density: Number(w[1]), fill: Number(w[2]), stiffness: Number(w[3]), damping: Number(w[4]),
             tensile: Number(w[5]), compressive: Number(w[6]), dragArea: Number(w[7]), breakThreshold: Number(w[8]),
             flammability: Number(w[9]), ignitability: Number(w[10]), liquid: w[11] === "1", indestructible: w[12] === "1" };
  }

  var server = {
    log: function (text) { hostS("server_log", text); },
    broadcast: function (text) { hostS("server_broadcast", text); },
    windAt: function (x, y, z) {
      var w = String(hostv("physics_wind_at", x, y, z)).split(" ");
      return w.length >= 4 ? { x: Number(w[0]), y: Number(w[1]), z: Number(w[2]), speed: Number(w[3]) } : { x: 0, y: 0, z: 0, speed: 0 };
    },
    materialByName: function (name) { return materialFrom(hostv("physics_material_by_name", name)); },
    materialAt: function (x, y, z) { return materialFrom(hostv("physics_material_at", x, y, z)); },
    massOf: function (name, volume) { var m = materialFrom(hostv("physics_material_by_name", name)); return m.known ? m.density * (volume === undefined ? 1 : volume) : 0; },
    solveRegion: function (x, y, z, nx, ny, nz, options) {
      options = options || {};
      var text = String(hostv("physics_solve", x + " " + y + " " + z, nx + " " + ny + " " + nz,
        options.floorAnchored === false ? "0" : "1", options.wind ? "1" : "0"));
      if (text.indexOf("error:") === 0) return { ok: false, error: text.substr(7), broken: [] };
      var lines = text.split("\n"), h = lines[0].split(" ");
      var kinds = ["none", "bending", "shear", "crush", "tension", "hang", "unsupported"];
      var r = { ok: true, error: "", maxRatio: Number(h[0]), converged: h[1] === "1", rounds: Number(h[2]), granular: Number(h[4]),
                caveIns: Number(h[5]), components: Number(h[6]), broken: [] };
      for (var i = 1; i < lines.length; i++) {
        var b = lines[i].split(" ");
        if (b.length >= 5) r.broken.push({ x: Number(b[0]), y: Number(b[1]), z: Number(b[2]), ratio: Number(b[3]), kind: kinds[Number(b[4])] || "none" });
      }
      return r;
    },
    advertiseCapability: function (name) { return hostv("server_advertise_capability", name) == true; },
    onlineCount: function () { return hostv("server_player_count"); },
    player: function (name) { return new Player(name); },
    blockAt: function (x, y, z) { return hostv("world_get_block", x, y, z); },
    setBlock: function (x, y, z, name) { return hostv("world_set_block", x, y, z, name) == true; },
    entityHealth: function (id) { return hostv("entity_health", id); },
    setEntityHealth: function (id, health) { return hostv("entity_set_health", id, health) == true; },
    entityPos: function (id) { return { x: hostv("entity_pos", id, "x"), y: hostv("entity_pos", id, "y"), z: hostv("entity_pos", id, "z") }; },
    teleportEntity: function (id, x, y, z) { return hostv("entity_teleport", id, x, y, z) == true; },
    setEntityOnFire: function (id, seconds) { return hostv("entity_ignite", id, seconds) == true; },
    removeEntity: function (id) { return hostv("entity_remove", id) == true; },
    time: function () { return hostv("world_time"); },
    setTime: function (ticks) { hostv("world_set_time", ticks); }
  };

  // ---- event types: [entry, build]. `build` makes the event object from what the host knows.
  var types = {
    ChatEvent: ["on_player_chat", function () { return { player: P(), message: str("message") }; }],
    PlayerCommandEvent: ["on_player_command", function () { return { player: P(), command: str("message") }; }],
    JoinEvent: ["on_player_join", function () { return { player: P() }; }],
    LeaveEvent: ["on_player_leave", function () { return { player: P() }; }],
    LoginEvent: ["on_player_login", function () { return { player: P(), kickMessage: str("message") }; }],
    MoveEvent: ["on_player_move", function () { return { player: P(), origin: vec("from_"), target: vec("to_") }; }],
    TeleportEvent: ["on_player_teleport", function () { return { player: P(), origin: vec("from_"), target: vec("to_") }; }],
    ToggleEvent: ["on_player_toggle", function () { return { player: P(), kind: num("kind"), on: num("value") != 0 }; }],
    GamemodeChangeEvent: ["on_player_gamemode_change", function () { return { player: P(), previous: num("previous"), next: num("next") }; }],
    ItemHeldEvent: ["on_player_item_held", function () { return { player: P(), previousSlot: num("previous"), nextSlot: num("next") }; }],
    InteractEvent: ["on_player_interact", function () { return merge({ player: P(), action: num("action") }, xyz()); }],
    InventoryOpenEvent: ["on_inventory_open", function () { return { player: P(), window: num("window") }; }],
    PotionEffectEvent: ["on_entity_potion_effect", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), effect: str("effect"), duration: num("duration"), amplifier: num("amplifier") };
    }],
    CombustEvent: ["on_entity_combust", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), ticks: num("ticks") }; }],
    EntityTeleportEvent: ["on_entity_teleport", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), origin: vec("from_"), target: vec("to_") };
    }],
    PistonEvent: ["on_piston", function () {
      return { x: num("x"), y: num("y"), z: num("z"), extend: num("extend") != 0, moved: num("moved"), broken: num("broken") };
    }],
    ProjectileHitEvent: ["on_projectile_hit", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), ownerId: num("owner_id"), hitEntity: num("on_entity") != 0,
               targetId: num("target_id"), x: num("x"), y: num("y"), z: num("z") };
    }],
    BlockChangeEvent: ["on_block_change", function () {
      return { x: num("x"), y: num("y"), z: num("z"), before: str("before"), after: str("after") };
    }],
    PortalEvent: ["on_portal", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), x: num("x"), y: num("y"), z: num("z"), target: str("target") };
    }],
    FurnaceSmeltEvent: ["on_furnace_smelt", function () {
      return { x: num("x"), y: num("y"), z: num("z"), input: str("input"), output: str("output") };
    }],
    KickEvent: ["on_player_kick", function () { return { player: P(), reason: str("message") }; }],
    TabCompleteEvent: ["on_tab_complete", function () { return { player: P(), buffer: str("buffer"), suggestions: [] }; }],
    TargetEvent: ["on_entity_target", function () {
      return { mobId: num("mob_id"), mobType: str("mob_type"), targetId: num("target_id"), targetType: str("target_type") };
    }],
    AdvancementEvent: ["on_advancement", function () { return { player: P(), advancement: str("advancement") }; }],
    HopperMoveEvent: ["on_hopper_move", function () { return { x: num("x"), y: num("y"), z: num("z"), item: str("item") }; }],
    SwapHandsEvent: ["on_player_swap_hands", function () { return { player: P() }; }],
    SwingEvent: ["on_player_swing", function () { return { player: P() }; }],
    UseItemEvent: ["on_player_use_item", function () { return { player: P() }; }],
    InteractEntityEvent: ["on_player_interact_entity", function () {
      return { player: P(), entityId: num("entity_id"), action: num("action"), sneaking: num("sneaking") != 0, known: num("known") != 0 };
    }],
    BlockPlaceEvent: ["on_block_place", function () {
      return merge({ player: P(), blockName: str("placed"), against: str("clicked") }, xyz());
    }],
    BlockBreakEvent: ["on_block_break", function () {
      return merge({ player: P(), blockName: str("block"), drop: num("flag") != 0 }, xyz());
    }],
    DropItemEvent: ["on_player_drop_item", function () { return { player: P(), item: str("item"), count: num("count") }; }],
    PickupItemEvent: ["on_player_pickup_item", function () {
      return { player: P(), item: str("item"), count: num("count"), entityId: num("entity_id") };
    }],
    ItemConsumeEvent: ["on_player_item_consume", function () { return { player: P(), item: str("item") }; }],
    BedEnterEvent: ["on_player_bed_enter", function () { return merge({ player: P() }, xyz()); }],
    BedLeaveEvent: ["on_player_bed_leave", function () { return merge({ player: P() }, xyz()); }],
    SignChangeEvent: ["on_sign_change", function () {
      return merge({ player: P(), lines: [str("line0"), str("line1"), str("line2"), str("line3")] }, xyz());
    }],
    BucketEmptyEvent: ["on_bucket_empty", function () { return merge({ player: P(), bucket: str("bucket") }, xyz()); }],
    BucketFillEvent: ["on_bucket_fill", function () { return merge({ player: P(), bucket: str("bucket") }, xyz()); }],
    InventoryClickEvent: ["on_inventory_click", function () {
      return { player: P(), window: num("window"), clickType: num("click_type"), slot: num("slot"), rawSlot: num("raw_slot"),
               hotbarButton: num("hotbar_button") };
    }],
    InventoryCloseEvent: ["on_inventory_close", function () { return { player: P(), window: num("window") }; }],
    PermissionCheckEvent: ["on_permission_check", function () { return { player: P(), node: str("node"), granted: num("flag") != 0 }; }],
    ExpChangeEvent: ["on_player_exp_change", function () { return { player: P(), amount: num("amount") }; }],
    RespawnEvent: ["on_player_respawn", function () { return { player: P(), pos: xyz(), alive: num("alive") != 0 }; }],
    DeathEvent: ["on_player_death", function () { return { player: P(), message: str("message") }; }],
    FishEvent: ["on_player_fish", function () { return { player: P(), state: num("state"), caught: str("caught"), exp: num("exp") }; }],
    EggThrowEvent: ["on_player_egg_throw", function () {
      return { player: P(), hatching: num("hatching") != 0, numHatches: num("num_hatches"), hatchingType: str("hatching_type") };
    }],
    ChangeWorldEvent: ["on_player_change_world", function () {
      return { player: P(), pos: xyz(), yaw: num("yaw"), pitch: num("pitch") };
    }],
    MainHandChangeEvent: ["on_player_main_hand_change", function () { return { player: P(), hand: num("hand") }; }],
    CustomPayloadEvent: ["on_player_custom_payload", function () { return { player: P(), channel: str("channel"), length: num("length"), data: hexBytes(str("data")) }; }],
    CustomClickEvent: ["on_custom_click", function () { return { player: P(), id: str("id"), length: num("length") }; }],
    EntityDamageEvent: ["on_entity_damage", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), damageType: str("damage_type"), amount: num("amount"),
               attackerId: num("attacker_id") };
    }],
    EntityDeathEvent: ["on_entity_death", function () {
      return { entityId: num("entity_id"), entityType: str("entity_type"), damageType: str("damage_type"), killerId: num("killer_id") };
    }],
    EntitySpawnEvent: ["on_entity_spawn", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), pos: xyz() }; }],
    EntityRemoveEvent: ["on_entity_remove", function () { return { entityId: num("entity_id"), entityType: str("entity_type") }; }],
    ExplosionEvent: ["on_explosion", function () { return { pos: xyz(), power: num("power") }; }],
    WeatherChangeEvent: ["on_weather_change", function () { return { raining: num("raining") != 0, thundering: num("thundering") != 0 }; }],
    BlockGrowEvent: ["on_block_grow", function () { return merge({ before: str("old_block"), after: str("new_block") }, xyz()); }],
    RedstoneEvent: ["on_block_redstone", function () {
      return merge({ oldCurrent: num("old_current"), newCurrent: num("new_current") }, xyz());
    }],
    SpawnChangeEvent: ["on_spawn_change", function () {
      return { previous: vec("previous_"), next: vec("next_"), yaw: num("yaw"), pitch: num("pitch") };
    }],
    ChunkSendEvent: ["on_chunk_send", function () { return { x: num("x"), z: num("z") }; }],
    ServerCommandEvent: ["on_server_command", function () { return { command: str("command") }; }],
    BroadcastEvent: ["on_server_broadcast", function () { return { message: str("message"), sender: str("sender") }; }],
    ServerLoadEvent: ["on_server_load", function () { return { reload: num("reload") != 0 }; }],
    TickStartEvent: ["on_server_tick_start", function () { return { tick: num("tick") }; }],
    TickEndEvent: ["on_server_tick_end", function () { return { tick: num("tick"), durationNs: num("duration_ns") }; }],
    LevelChangeEvent: ["on_player_level_change", function () { return { player: P(), previous: num("previous"), level: num("level") }; }],
    WorldSaveEvent: ["on_world_save", function () { return { saved: true }; }],
    TimeSetEvent: ["on_time_set", function () { return { previous: num("previous"), time: num("time") }; }],
    HealEvent: ["on_entity_heal", function () { return { entityId: num("entity_id"), entityType: str("entity_type"), amount: num("amount") }; }],
    FoodLevelChangeEvent: ["on_player_food_change", function () { return { player: P(), level: num("level"), previous: num("previous") }; }],
    StatisticEvent: ["on_player_statistic", function () { return { player: P(), category: num("category"), statId: num("stat_id"), amount: num("amount") }; }],
    ServerListPingEvent: ["on_server_list_ping", function () { return { address: str("address"), motd: str("message"), online: num("online"), maxPlayers: num("max") }; }],
    PreLoginEvent: ["on_player_pre_login", function () { return { name: str("player"), address: str("address"), kickMessage: str("message") }; }],
    PacketEvent: ["on_packet_received", function () {
      return { player: P(), packetId: num("packet_id"), length: num("length") };
    }]
  };
  var byEntry = {};
  var tokens = {};
  for (var name in types) {
    tokens[name] = { name: name, entry: types[name][0] };
    byEntry[types[name][0]] = types[name][1];
  }

  function on(type, fn) {
    var entry = typeof type === "string" ? type : type.entry;
    if (!handlers[entry]) handlers[entry] = [];
    handlers[entry].push(fn);
    want(entry);
  }

  function command(name, description, level, fn) {
    commands.push({ name: name, description: description, level: level, fn: fn });
    want("on_command");
    if (started) hostv("register_command", name, description, level);
  }
  function addTask(id, repeat, fn, data) { want("on_task"); tasks.push({ id: id, repeat: repeat, fn: fn, data: data }); return id; }
  function after(ticks, fn, data) { return addTask(hostv("schedule_after", ticks), false, fn, data); }
  function every(ticks, fn, data) { return addTask(hostv("schedule_repeat", ticks), true, fn, data); }
  function cancelTask(id) {
    hostv("schedule_cancel", id);
    tasks = tasks.filter(function (t) { return t.id != id; });
  }

  // ---- jobs on the server's worker threads (docs/PLUGIN_JOBS.md). `kind` names a server kernel ("fnv1a", "primes", "sort"): plugin code itself never
  // runs on a worker. job() answers an id at once (-1 unknown kind, -2 input over 64 KiB); `fn({ id, value, failed, text })` runs later, on the
  // tick thread, with the jobs of this plugin delivered in the order they were submitted. job_abi_version is 1.
  var jobs = [];              // { id, fn }
  function job(kind, input, fn) {
    var id = hostv("job_submit", kind, String(input));
    if (id > 0) { want("on_job"); jobs.push({ id: id, fn: fn }); }
    return id;
  }
  function jobStatus(id) { return hostv("job_status", id); }        // 0 pending, 1 done, 2 failed, -1 unknown or already delivered
  function jobAbiVersion() { return hostv("job_abi_version"); }

  function commandContext() {
    var who = str("player");
    var raw = str("args");
    var args = raw == "" ? [] : raw.split(" ").filter(function (w) { return w.length > 0; });
    return {
      sender: new Player(who), isConsole: who == "", name: str("command"), rawArgs: raw, args: args,
      reply: function (text) { hostv("command_reply", text); },
      fail: function (text) { hostv("command_fail", text); },
      arg: function (i) { return i < args.length ? args[i] : ""; },
      intArg: function (i, d) { var n = parseInt(args[i], 10); return isNaN(n) ? (d === undefined ? 0 : d) : n; },
      numberArg: function (i, d) { var n = parseFloat(args[i]); return isNaN(n) ? (d === undefined ? 0 : d) : n; },
      restFrom: function (i) { return args.slice(i).join(" "); }
    };
  }

  function fire(entry) {
    if (entry == "start") {
      started = true;
      for (var i = 0; i < wanted.length; i++) hostS("subscribe_event", wanted[i]);
      for (var c = 0; c < commands.length; c++) hostv("register_command", commands[c].name, commands[c].description, commands[c].level);
      for (var e = 0; e < enables.length; e++) enables[e]();
      return;
    }
    if (entry == "stop") { for (var d = 0; d < disables.length; d++) disables[d](); return; }
    if (entry == "on_command") {
      var ctx = commandContext();
      for (var k = 0; k < commands.length; k++) if (commands[k].name == ctx.name) { commands[k].fn(ctx); return; }
      return;
    }
    if (entry == "on_task") {
      var id = num("id");
      for (var t = 0; t < tasks.length; t++) {
        if (tasks[t].id == id) {
          var task = tasks[t];
          if (!task.repeat) tasks.splice(t, 1);
          task.fn(task.data);
          return;
        }
      }
      return;
    }
    if (entry == "on_job") {
      var jid = num("id");
      for (var j = 0; j < jobs.length; j++) {
        if (jobs[j].id == jid) {
          var jb = jobs.splice(j, 1)[0];
          jb.fn({ id: jid, value: num("value"), failed: num("failed") != 0, text: str("text") });
          return;
        }
      }
      return;
    }
    var list = handlers[entry];
    if (!list || !byEntry[entry]) return;
    var ev = byEntry[entry]();
    ev.cancelled = false;
    ev.cancel = function () { this.cancelled = true; };
    var tabBefore = ev.suggestions;
    var before = { message: ev.message, kickMessage: ev.kickMessage, drop: ev.drop, granted: ev.granted, hatching: ev.hatching, amount: ev.amount,
                   motd: ev.motd, maxPlayers: ev.maxPlayers, level: ev.level, time: ev.time, duration: ev.duration, ticks: ev.ticks };
    for (var h = 0; h < list.length; h++) list[h](ev);
    if (ev.cancelled) host("event_cancel");
    if (ev.message !== before.message && typeof ev.message === "string") hostS("event_set_message", ev.message);
    if (ev.kickMessage !== before.kickMessage && typeof ev.kickMessage === "string") hostS("event_set_message", ev.kickMessage);
    if (ev.drop !== before.drop) hostv("event_set_flag", ev.drop ? 1 : 0);
    if (ev.granted !== before.granted) hostv("event_set_flag", ev.granted ? 1 : 0);
    if (ev.hatching !== before.hatching) hostv("event_set_flag", ev.hatching ? 1 : 0);
    if (ev.amount !== before.amount && typeof ev.amount === "number") hostv("event_set_value", ev.amount);
    if (ev.motd !== before.motd && typeof ev.motd === "string") hostS("event_set_message", ev.motd);
    if (ev.maxPlayers !== before.maxPlayers && typeof ev.maxPlayers === "number") hostv("event_set_value", ev.maxPlayers);
    if (ev.level !== before.level && typeof ev.level === "number") hostv("event_set_value", ev.level);
    if (ev.time !== before.time && typeof ev.time === "number") hostv("event_set_value", ev.time);
    if (ev.suggestions && ev.suggestions.length > 0) hostS("event_set_message", ev.suggestions.join("\n"));
    if (ev.duration !== before.duration && typeof ev.duration === "number") hostv("event_set_value", ev.duration);
    if (ev.ticks !== before.ticks && typeof ev.ticks === "number") hostv("event_set_value", ev.ticks);
  }

  return {
    fire: fire, on: on, command: command, after: after, every: every, cancelTask: cancelTask, job: job, jobStatus: jobStatus, jobAbiVersion: jobAbiVersion, server: server, tokens: tokens,
    onEnable: function (fn) { enables.push(fn); }, onDisable: function (fn) { disables.push(fn); }
  };
})();

var on = __sdk.on, command = __sdk.command, after = __sdk.after, every = __sdk.every, cancelTask = __sdk.cancelTask;
var job = __sdk.job, jobStatus = __sdk.jobStatus, jobAbiVersion = __sdk.jobAbiVersion;
var onEnable = __sdk.onEnable, onDisable = __sdk.onDisable, server = __sdk.server;
var ChatEvent = __sdk.tokens.ChatEvent, PlayerCommandEvent = __sdk.tokens.PlayerCommandEvent, JoinEvent = __sdk.tokens.JoinEvent;
var LeaveEvent = __sdk.tokens.LeaveEvent, LoginEvent = __sdk.tokens.LoginEvent, MoveEvent = __sdk.tokens.MoveEvent;
var TeleportEvent = __sdk.tokens.TeleportEvent, ToggleEvent = __sdk.tokens.ToggleEvent, GamemodeChangeEvent = __sdk.tokens.GamemodeChangeEvent;
var CombustEvent = __sdk.tokens.CombustEvent, EntityTeleportEvent = __sdk.tokens.EntityTeleportEvent;
var PistonEvent = __sdk.tokens.PistonEvent;
var ProjectileHitEvent = __sdk.tokens.ProjectileHitEvent;
var BlockChangeEvent = __sdk.tokens.BlockChangeEvent;
var PortalEvent = __sdk.tokens.PortalEvent, FurnaceSmeltEvent = __sdk.tokens.FurnaceSmeltEvent;
var KickEvent = __sdk.tokens.KickEvent;
var TabCompleteEvent = __sdk.tokens.TabCompleteEvent;
var TargetEvent = __sdk.tokens.TargetEvent;
var AdvancementEvent = __sdk.tokens.AdvancementEvent;
var HopperMoveEvent = __sdk.tokens.HopperMoveEvent;
var SwapHandsEvent = __sdk.tokens.SwapHandsEvent, InventoryOpenEvent = __sdk.tokens.InventoryOpenEvent, PotionEffectEvent = __sdk.tokens.PotionEffectEvent;
var ItemHeldEvent = __sdk.tokens.ItemHeldEvent, InteractEvent = __sdk.tokens.InteractEvent, SwingEvent = __sdk.tokens.SwingEvent;
var UseItemEvent = __sdk.tokens.UseItemEvent, InteractEntityEvent = __sdk.tokens.InteractEntityEvent, BlockPlaceEvent = __sdk.tokens.BlockPlaceEvent;
var BlockBreakEvent = __sdk.tokens.BlockBreakEvent, DropItemEvent = __sdk.tokens.DropItemEvent, PickupItemEvent = __sdk.tokens.PickupItemEvent;
var ItemConsumeEvent = __sdk.tokens.ItemConsumeEvent, BedEnterEvent = __sdk.tokens.BedEnterEvent, BedLeaveEvent = __sdk.tokens.BedLeaveEvent;
var SignChangeEvent = __sdk.tokens.SignChangeEvent, BucketEmptyEvent = __sdk.tokens.BucketEmptyEvent, BucketFillEvent = __sdk.tokens.BucketFillEvent;
var InventoryClickEvent = __sdk.tokens.InventoryClickEvent, InventoryCloseEvent = __sdk.tokens.InventoryCloseEvent;
var PermissionCheckEvent = __sdk.tokens.PermissionCheckEvent, ExpChangeEvent = __sdk.tokens.ExpChangeEvent, RespawnEvent = __sdk.tokens.RespawnEvent;
var DeathEvent = __sdk.tokens.DeathEvent, FishEvent = __sdk.tokens.FishEvent, EggThrowEvent = __sdk.tokens.EggThrowEvent;
var ChangeWorldEvent = __sdk.tokens.ChangeWorldEvent, MainHandChangeEvent = __sdk.tokens.MainHandChangeEvent;
var CustomPayloadEvent = __sdk.tokens.CustomPayloadEvent, CustomClickEvent = __sdk.tokens.CustomClickEvent;
var EntityDamageEvent = __sdk.tokens.EntityDamageEvent, EntityDeathEvent = __sdk.tokens.EntityDeathEvent;
var EntitySpawnEvent = __sdk.tokens.EntitySpawnEvent, EntityRemoveEvent = __sdk.tokens.EntityRemoveEvent;
var ExplosionEvent = __sdk.tokens.ExplosionEvent, WeatherChangeEvent = __sdk.tokens.WeatherChangeEvent;
var BlockGrowEvent = __sdk.tokens.BlockGrowEvent, RedstoneEvent = __sdk.tokens.RedstoneEvent, SpawnChangeEvent = __sdk.tokens.SpawnChangeEvent;
var ChunkSendEvent = __sdk.tokens.ChunkSendEvent, ServerCommandEvent = __sdk.tokens.ServerCommandEvent, BroadcastEvent = __sdk.tokens.BroadcastEvent;
var ServerLoadEvent = __sdk.tokens.ServerLoadEvent, TickStartEvent = __sdk.tokens.TickStartEvent, TickEndEvent = __sdk.tokens.TickEndEvent;
var PacketEvent = __sdk.tokens.PacketEvent, HealEvent = __sdk.tokens.HealEvent, FoodLevelChangeEvent = __sdk.tokens.FoodLevelChangeEvent;
var LevelChangeEvent = __sdk.tokens.LevelChangeEvent, WorldSaveEvent = __sdk.tokens.WorldSaveEvent, TimeSetEvent = __sdk.tokens.TimeSetEvent;
var StatisticEvent = __sdk.tokens.StatisticEvent, ServerListPingEvent = __sdk.tokens.ServerListPingEvent, PreLoginEvent = __sdk.tokens.PreLoginEvent;

function on_player_chat() {
  hostS("event_set_message", hostv("event_str", "player") + ": " + hostv("event_str", "message"));
}
function on_player_command() { hostS("server_log", "command " + hostv("event_str", "message")); }


;var __h = {};
if (typeof start === "function") __h.start = start;
if (typeof stop === "function") __h.stop = stop;
if (typeof on_player_chat === "function") __h.on_player_chat = on_player_chat;
if (typeof on_player_command === "function") __h.on_player_command = on_player_command;
if (typeof on_player_join === "function") __h.on_player_join = on_player_join;
if (typeof on_player_leave === "function") __h.on_player_leave = on_player_leave;
if (typeof on_player_move === "function") __h.on_player_move = on_player_move;
if (typeof on_player_teleport === "function") __h.on_player_teleport = on_player_teleport;
if (typeof on_player_toggle === "function") __h.on_player_toggle = on_player_toggle;
if (typeof on_player_gamemode_change === "function") __h.on_player_gamemode_change = on_player_gamemode_change;
if (typeof on_player_item_held === "function") __h.on_player_item_held = on_player_item_held;
if (typeof on_player_login === "function") __h.on_player_login = on_player_login;
if (typeof on_player_interact === "function") __h.on_player_interact = on_player_interact;
if (typeof on_block_place === "function") __h.on_block_place = on_block_place;
if (typeof on_server_command === "function") __h.on_server_command = on_server_command;
if (typeof on_server_broadcast === "function") __h.on_server_broadcast = on_server_broadcast;
if (typeof on_server_tick_start === "function") __h.on_server_tick_start = on_server_tick_start;
if (typeof on_server_tick_end === "function") __h.on_server_tick_end = on_server_tick_end;
if (typeof on_server_load === "function") __h.on_server_load = on_server_load;
if (typeof on_packet_received === "function") __h.on_packet_received = on_packet_received;
if (typeof on_block_redstone === "function") __h.on_block_redstone = on_block_redstone;
if (typeof on_spawn_change === "function") __h.on_spawn_change = on_spawn_change;
if (typeof on_block_grow === "function") __h.on_block_grow = on_block_grow;
if (typeof on_chunk_send === "function") __h.on_chunk_send = on_chunk_send;
if (typeof on_task === "function") __h.on_task = on_task;
if (typeof on_job === "function") __h.on_job = on_job;
if (typeof on_command === "function") __h.on_command = on_command;
if (typeof on_player_exp_change === "function") __h.on_player_exp_change = on_player_exp_change;
if (typeof on_player_respawn === "function") __h.on_player_respawn = on_player_respawn;
if (typeof on_player_death === "function") __h.on_player_death = on_player_death;
if (typeof on_player_swing === "function") __h.on_player_swing = on_player_swing;
if (typeof on_player_swap_hands === "function") __h.on_player_swap_hands = on_player_swap_hands;
if (typeof on_inventory_open === "function") __h.on_inventory_open = on_inventory_open;
if (typeof on_entity_potion_effect === "function") __h.on_entity_potion_effect = on_entity_potion_effect;
if (typeof on_entity_combust === "function") __h.on_entity_combust = on_entity_combust;
if (typeof on_entity_teleport === "function") __h.on_entity_teleport = on_entity_teleport;
if (typeof on_piston === "function") __h.on_piston = on_piston;
if (typeof on_projectile_hit === "function") __h.on_projectile_hit = on_projectile_hit;
if (typeof on_block_change === "function") __h.on_block_change = on_block_change;
if (typeof on_portal === "function") __h.on_portal = on_portal;
if (typeof on_furnace_smelt === "function") __h.on_furnace_smelt = on_furnace_smelt;
if (typeof on_player_kick === "function") __h.on_player_kick = on_player_kick;
if (typeof on_tab_complete === "function") __h.on_tab_complete = on_tab_complete;
if (typeof on_entity_target === "function") __h.on_entity_target = on_entity_target;
if (typeof on_advancement === "function") __h.on_advancement = on_advancement;
if (typeof on_hopper_move === "function") __h.on_hopper_move = on_hopper_move;
if (typeof on_player_use_item === "function") __h.on_player_use_item = on_player_use_item;
if (typeof on_player_interact_entity === "function") __h.on_player_interact_entity = on_player_interact_entity;
if (typeof on_player_custom_payload === "function") __h.on_player_custom_payload = on_player_custom_payload;
if (typeof on_player_main_hand_change === "function") __h.on_player_main_hand_change = on_player_main_hand_change;
if (typeof on_inventory_close === "function") __h.on_inventory_close = on_inventory_close;
if (typeof on_inventory_click === "function") __h.on_inventory_click = on_inventory_click;
if (typeof on_block_break === "function") __h.on_block_break = on_block_break;
if (typeof on_player_drop_item === "function") __h.on_player_drop_item = on_player_drop_item;
if (typeof on_player_pickup_item === "function") __h.on_player_pickup_item = on_player_pickup_item;
if (typeof on_player_item_consume === "function") __h.on_player_item_consume = on_player_item_consume;
if (typeof on_player_bed_enter === "function") __h.on_player_bed_enter = on_player_bed_enter;
if (typeof on_player_bed_leave === "function") __h.on_player_bed_leave = on_player_bed_leave;
if (typeof on_sign_change === "function") __h.on_sign_change = on_sign_change;
if (typeof on_bucket_empty === "function") __h.on_bucket_empty = on_bucket_empty;
if (typeof on_bucket_fill === "function") __h.on_bucket_fill = on_bucket_fill;
if (typeof on_permission_check === "function") __h.on_permission_check = on_permission_check;
if (typeof on_player_fish === "function") __h.on_player_fish = on_player_fish;
if (typeof on_player_egg_throw === "function") __h.on_player_egg_throw = on_player_egg_throw;
if (typeof on_custom_click === "function") __h.on_custom_click = on_custom_click;
if (typeof on_player_change_world === "function") __h.on_player_change_world = on_player_change_world;
if (typeof on_entity_damage === "function") __h.on_entity_damage = on_entity_damage;
if (typeof on_entity_death === "function") __h.on_entity_death = on_entity_death;
if (typeof on_entity_spawn === "function") __h.on_entity_spawn = on_entity_spawn;
if (typeof on_entity_remove === "function") __h.on_entity_remove = on_entity_remove;
if (typeof on_explosion === "function") __h.on_explosion = on_explosion;
if (typeof on_weather_change === "function") __h.on_weather_change = on_weather_change;
if (typeof on_entity_heal === "function") __h.on_entity_heal = on_entity_heal;
if (typeof on_player_food_change === "function") __h.on_player_food_change = on_player_food_change;
if (typeof on_player_statistic === "function") __h.on_player_statistic = on_player_statistic;
if (typeof on_server_list_ping === "function") __h.on_server_list_ping = on_server_list_ping;
if (typeof on_player_pre_login === "function") __h.on_player_pre_login = on_player_pre_login;
if (typeof on_player_level_change === "function") __h.on_player_level_change = on_player_level_change;
if (typeof on_world_save === "function") __h.on_world_save = on_world_save;
if (typeof on_time_set === "function") __h.on_time_set = on_time_set;
__h.__sdk = __sdk;
__aoeP.push({ name: "tagger", h: __h });
})();
function start() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.start) { try { p.h.start(); } catch (x) { hostS("server_log", p.name + ": start threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("start"); } catch (x) { hostS("server_log", p.name + ": start threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function stop() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.stop) { try { p.h.stop(); } catch (x) { hostS("server_log", p.name + ": stop threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("stop"); } catch (x) { hostS("server_log", p.name + ": stop threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_chat() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_chat) { try { p.h.on_player_chat(); } catch (x) { hostS("server_log", p.name + ": on_player_chat threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_chat"); } catch (x) { hostS("server_log", p.name + ": on_player_chat threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_command() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_command) { try { p.h.on_player_command(); } catch (x) { hostS("server_log", p.name + ": on_player_command threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_command"); } catch (x) { hostS("server_log", p.name + ": on_player_command threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_join() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_join) { try { p.h.on_player_join(); } catch (x) { hostS("server_log", p.name + ": on_player_join threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_join"); } catch (x) { hostS("server_log", p.name + ": on_player_join threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_leave() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_leave) { try { p.h.on_player_leave(); } catch (x) { hostS("server_log", p.name + ": on_player_leave threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_leave"); } catch (x) { hostS("server_log", p.name + ": on_player_leave threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_move() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_move) { try { p.h.on_player_move(); } catch (x) { hostS("server_log", p.name + ": on_player_move threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_move"); } catch (x) { hostS("server_log", p.name + ": on_player_move threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_teleport() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_teleport) { try { p.h.on_player_teleport(); } catch (x) { hostS("server_log", p.name + ": on_player_teleport threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_teleport"); } catch (x) { hostS("server_log", p.name + ": on_player_teleport threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_toggle() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_toggle) { try { p.h.on_player_toggle(); } catch (x) { hostS("server_log", p.name + ": on_player_toggle threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_toggle"); } catch (x) { hostS("server_log", p.name + ": on_player_toggle threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_gamemode_change() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_gamemode_change) { try { p.h.on_player_gamemode_change(); } catch (x) { hostS("server_log", p.name + ": on_player_gamemode_change threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_gamemode_change"); } catch (x) { hostS("server_log", p.name + ": on_player_gamemode_change threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_item_held() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_item_held) { try { p.h.on_player_item_held(); } catch (x) { hostS("server_log", p.name + ": on_player_item_held threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_item_held"); } catch (x) { hostS("server_log", p.name + ": on_player_item_held threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_login() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_login) { try { p.h.on_player_login(); } catch (x) { hostS("server_log", p.name + ": on_player_login threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_login"); } catch (x) { hostS("server_log", p.name + ": on_player_login threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_interact() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_interact) { try { p.h.on_player_interact(); } catch (x) { hostS("server_log", p.name + ": on_player_interact threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_interact"); } catch (x) { hostS("server_log", p.name + ": on_player_interact threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_block_place() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_block_place) { try { p.h.on_block_place(); } catch (x) { hostS("server_log", p.name + ": on_block_place threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_block_place"); } catch (x) { hostS("server_log", p.name + ": on_block_place threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_server_command() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_server_command) { try { p.h.on_server_command(); } catch (x) { hostS("server_log", p.name + ": on_server_command threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_server_command"); } catch (x) { hostS("server_log", p.name + ": on_server_command threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_server_broadcast() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_server_broadcast) { try { p.h.on_server_broadcast(); } catch (x) { hostS("server_log", p.name + ": on_server_broadcast threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_server_broadcast"); } catch (x) { hostS("server_log", p.name + ": on_server_broadcast threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_server_tick_start() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_server_tick_start) { try { p.h.on_server_tick_start(); } catch (x) { hostS("server_log", p.name + ": on_server_tick_start threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_server_tick_start"); } catch (x) { hostS("server_log", p.name + ": on_server_tick_start threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_server_tick_end() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_server_tick_end) { try { p.h.on_server_tick_end(); } catch (x) { hostS("server_log", p.name + ": on_server_tick_end threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_server_tick_end"); } catch (x) { hostS("server_log", p.name + ": on_server_tick_end threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_server_load() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_server_load) { try { p.h.on_server_load(); } catch (x) { hostS("server_log", p.name + ": on_server_load threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_server_load"); } catch (x) { hostS("server_log", p.name + ": on_server_load threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_packet_received() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_packet_received) { try { p.h.on_packet_received(); } catch (x) { hostS("server_log", p.name + ": on_packet_received threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_packet_received"); } catch (x) { hostS("server_log", p.name + ": on_packet_received threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_block_redstone() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_block_redstone) { try { p.h.on_block_redstone(); } catch (x) { hostS("server_log", p.name + ": on_block_redstone threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_block_redstone"); } catch (x) { hostS("server_log", p.name + ": on_block_redstone threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_spawn_change() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_spawn_change) { try { p.h.on_spawn_change(); } catch (x) { hostS("server_log", p.name + ": on_spawn_change threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_spawn_change"); } catch (x) { hostS("server_log", p.name + ": on_spawn_change threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_block_grow() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_block_grow) { try { p.h.on_block_grow(); } catch (x) { hostS("server_log", p.name + ": on_block_grow threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_block_grow"); } catch (x) { hostS("server_log", p.name + ": on_block_grow threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_chunk_send() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_chunk_send) { try { p.h.on_chunk_send(); } catch (x) { hostS("server_log", p.name + ": on_chunk_send threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_chunk_send"); } catch (x) { hostS("server_log", p.name + ": on_chunk_send threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_task() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    if (hostv("event_str", "owner") != "" && hostv("event_str", "owner") != p.name) continue;
    hostS("plugin_scope", p.name);
    if (p.h.on_task) { try { p.h.on_task(); } catch (x) { hostS("server_log", p.name + ": on_task threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_task"); } catch (x) { hostS("server_log", p.name + ": on_task threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_job() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_job) { try { p.h.on_job(); } catch (x) { hostS("server_log", p.name + ": on_job threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_job"); } catch (x) { hostS("server_log", p.name + ": on_job threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_command() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    if (hostv("event_str", "owner") != "" && hostv("event_str", "owner") != p.name) continue;
    hostS("plugin_scope", p.name);
    if (p.h.on_command) { try { p.h.on_command(); } catch (x) { hostS("server_log", p.name + ": on_command threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_command"); } catch (x) { hostS("server_log", p.name + ": on_command threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_exp_change() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_exp_change) { try { p.h.on_player_exp_change(); } catch (x) { hostS("server_log", p.name + ": on_player_exp_change threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_exp_change"); } catch (x) { hostS("server_log", p.name + ": on_player_exp_change threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_respawn() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_respawn) { try { p.h.on_player_respawn(); } catch (x) { hostS("server_log", p.name + ": on_player_respawn threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_respawn"); } catch (x) { hostS("server_log", p.name + ": on_player_respawn threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_death() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_death) { try { p.h.on_player_death(); } catch (x) { hostS("server_log", p.name + ": on_player_death threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_death"); } catch (x) { hostS("server_log", p.name + ": on_player_death threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_swing() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_swing) { try { p.h.on_player_swing(); } catch (x) { hostS("server_log", p.name + ": on_player_swing threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_swing"); } catch (x) { hostS("server_log", p.name + ": on_player_swing threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_swap_hands() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_swap_hands) { try { p.h.on_player_swap_hands(); } catch (x) { hostS("server_log", p.name + ": on_player_swap_hands threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_swap_hands"); } catch (x) { hostS("server_log", p.name + ": on_player_swap_hands threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_inventory_open() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_inventory_open) { try { p.h.on_inventory_open(); } catch (x) { hostS("server_log", p.name + ": on_inventory_open threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_inventory_open"); } catch (x) { hostS("server_log", p.name + ": on_inventory_open threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_entity_potion_effect() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_entity_potion_effect) { try { p.h.on_entity_potion_effect(); } catch (x) { hostS("server_log", p.name + ": on_entity_potion_effect threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_entity_potion_effect"); } catch (x) { hostS("server_log", p.name + ": on_entity_potion_effect threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_entity_combust() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_entity_combust) { try { p.h.on_entity_combust(); } catch (x) { hostS("server_log", p.name + ": on_entity_combust threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_entity_combust"); } catch (x) { hostS("server_log", p.name + ": on_entity_combust threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_entity_teleport() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_entity_teleport) { try { p.h.on_entity_teleport(); } catch (x) { hostS("server_log", p.name + ": on_entity_teleport threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_entity_teleport"); } catch (x) { hostS("server_log", p.name + ": on_entity_teleport threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_piston() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_piston) { try { p.h.on_piston(); } catch (x) { hostS("server_log", p.name + ": on_piston threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_piston"); } catch (x) { hostS("server_log", p.name + ": on_piston threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_projectile_hit() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_projectile_hit) { try { p.h.on_projectile_hit(); } catch (x) { hostS("server_log", p.name + ": on_projectile_hit threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_projectile_hit"); } catch (x) { hostS("server_log", p.name + ": on_projectile_hit threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_block_change() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_block_change) { try { p.h.on_block_change(); } catch (x) { hostS("server_log", p.name + ": on_block_change threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_block_change"); } catch (x) { hostS("server_log", p.name + ": on_block_change threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_portal() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_portal) { try { p.h.on_portal(); } catch (x) { hostS("server_log", p.name + ": on_portal threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_portal"); } catch (x) { hostS("server_log", p.name + ": on_portal threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_furnace_smelt() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_furnace_smelt) { try { p.h.on_furnace_smelt(); } catch (x) { hostS("server_log", p.name + ": on_furnace_smelt threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_furnace_smelt"); } catch (x) { hostS("server_log", p.name + ": on_furnace_smelt threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_kick() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_kick) { try { p.h.on_player_kick(); } catch (x) { hostS("server_log", p.name + ": on_player_kick threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_kick"); } catch (x) { hostS("server_log", p.name + ": on_player_kick threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_tab_complete() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_tab_complete) { try { p.h.on_tab_complete(); } catch (x) { hostS("server_log", p.name + ": on_tab_complete threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_tab_complete"); } catch (x) { hostS("server_log", p.name + ": on_tab_complete threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_entity_target() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_entity_target) { try { p.h.on_entity_target(); } catch (x) { hostS("server_log", p.name + ": on_entity_target threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_entity_target"); } catch (x) { hostS("server_log", p.name + ": on_entity_target threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_advancement() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_advancement) { try { p.h.on_advancement(); } catch (x) { hostS("server_log", p.name + ": on_advancement threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_advancement"); } catch (x) { hostS("server_log", p.name + ": on_advancement threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_hopper_move() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_hopper_move) { try { p.h.on_hopper_move(); } catch (x) { hostS("server_log", p.name + ": on_hopper_move threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_hopper_move"); } catch (x) { hostS("server_log", p.name + ": on_hopper_move threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_use_item() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_use_item) { try { p.h.on_player_use_item(); } catch (x) { hostS("server_log", p.name + ": on_player_use_item threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_use_item"); } catch (x) { hostS("server_log", p.name + ": on_player_use_item threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_interact_entity() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_interact_entity) { try { p.h.on_player_interact_entity(); } catch (x) { hostS("server_log", p.name + ": on_player_interact_entity threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_interact_entity"); } catch (x) { hostS("server_log", p.name + ": on_player_interact_entity threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_custom_payload() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_custom_payload) { try { p.h.on_player_custom_payload(); } catch (x) { hostS("server_log", p.name + ": on_player_custom_payload threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_custom_payload"); } catch (x) { hostS("server_log", p.name + ": on_player_custom_payload threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_main_hand_change() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_main_hand_change) { try { p.h.on_player_main_hand_change(); } catch (x) { hostS("server_log", p.name + ": on_player_main_hand_change threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_main_hand_change"); } catch (x) { hostS("server_log", p.name + ": on_player_main_hand_change threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_inventory_close() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_inventory_close) { try { p.h.on_inventory_close(); } catch (x) { hostS("server_log", p.name + ": on_inventory_close threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_inventory_close"); } catch (x) { hostS("server_log", p.name + ": on_inventory_close threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_inventory_click() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_inventory_click) { try { p.h.on_inventory_click(); } catch (x) { hostS("server_log", p.name + ": on_inventory_click threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_inventory_click"); } catch (x) { hostS("server_log", p.name + ": on_inventory_click threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_block_break() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_block_break) { try { p.h.on_block_break(); } catch (x) { hostS("server_log", p.name + ": on_block_break threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_block_break"); } catch (x) { hostS("server_log", p.name + ": on_block_break threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_drop_item() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_drop_item) { try { p.h.on_player_drop_item(); } catch (x) { hostS("server_log", p.name + ": on_player_drop_item threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_drop_item"); } catch (x) { hostS("server_log", p.name + ": on_player_drop_item threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_pickup_item() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_pickup_item) { try { p.h.on_player_pickup_item(); } catch (x) { hostS("server_log", p.name + ": on_player_pickup_item threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_pickup_item"); } catch (x) { hostS("server_log", p.name + ": on_player_pickup_item threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_item_consume() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_item_consume) { try { p.h.on_player_item_consume(); } catch (x) { hostS("server_log", p.name + ": on_player_item_consume threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_item_consume"); } catch (x) { hostS("server_log", p.name + ": on_player_item_consume threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_bed_enter() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_bed_enter) { try { p.h.on_player_bed_enter(); } catch (x) { hostS("server_log", p.name + ": on_player_bed_enter threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_bed_enter"); } catch (x) { hostS("server_log", p.name + ": on_player_bed_enter threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_bed_leave() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_bed_leave) { try { p.h.on_player_bed_leave(); } catch (x) { hostS("server_log", p.name + ": on_player_bed_leave threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_bed_leave"); } catch (x) { hostS("server_log", p.name + ": on_player_bed_leave threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_sign_change() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_sign_change) { try { p.h.on_sign_change(); } catch (x) { hostS("server_log", p.name + ": on_sign_change threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_sign_change"); } catch (x) { hostS("server_log", p.name + ": on_sign_change threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_bucket_empty() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_bucket_empty) { try { p.h.on_bucket_empty(); } catch (x) { hostS("server_log", p.name + ": on_bucket_empty threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_bucket_empty"); } catch (x) { hostS("server_log", p.name + ": on_bucket_empty threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_bucket_fill() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_bucket_fill) { try { p.h.on_bucket_fill(); } catch (x) { hostS("server_log", p.name + ": on_bucket_fill threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_bucket_fill"); } catch (x) { hostS("server_log", p.name + ": on_bucket_fill threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_permission_check() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_permission_check) { try { p.h.on_permission_check(); } catch (x) { hostS("server_log", p.name + ": on_permission_check threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_permission_check"); } catch (x) { hostS("server_log", p.name + ": on_permission_check threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_fish() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_fish) { try { p.h.on_player_fish(); } catch (x) { hostS("server_log", p.name + ": on_player_fish threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_fish"); } catch (x) { hostS("server_log", p.name + ": on_player_fish threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_egg_throw() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_egg_throw) { try { p.h.on_player_egg_throw(); } catch (x) { hostS("server_log", p.name + ": on_player_egg_throw threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_egg_throw"); } catch (x) { hostS("server_log", p.name + ": on_player_egg_throw threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_custom_click() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_custom_click) { try { p.h.on_custom_click(); } catch (x) { hostS("server_log", p.name + ": on_custom_click threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_custom_click"); } catch (x) { hostS("server_log", p.name + ": on_custom_click threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_change_world() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_change_world) { try { p.h.on_player_change_world(); } catch (x) { hostS("server_log", p.name + ": on_player_change_world threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_change_world"); } catch (x) { hostS("server_log", p.name + ": on_player_change_world threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_entity_damage() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_entity_damage) { try { p.h.on_entity_damage(); } catch (x) { hostS("server_log", p.name + ": on_entity_damage threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_entity_damage"); } catch (x) { hostS("server_log", p.name + ": on_entity_damage threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_entity_death() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_entity_death) { try { p.h.on_entity_death(); } catch (x) { hostS("server_log", p.name + ": on_entity_death threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_entity_death"); } catch (x) { hostS("server_log", p.name + ": on_entity_death threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_entity_spawn() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_entity_spawn) { try { p.h.on_entity_spawn(); } catch (x) { hostS("server_log", p.name + ": on_entity_spawn threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_entity_spawn"); } catch (x) { hostS("server_log", p.name + ": on_entity_spawn threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_entity_remove() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_entity_remove) { try { p.h.on_entity_remove(); } catch (x) { hostS("server_log", p.name + ": on_entity_remove threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_entity_remove"); } catch (x) { hostS("server_log", p.name + ": on_entity_remove threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_explosion() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_explosion) { try { p.h.on_explosion(); } catch (x) { hostS("server_log", p.name + ": on_explosion threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_explosion"); } catch (x) { hostS("server_log", p.name + ": on_explosion threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_weather_change() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_weather_change) { try { p.h.on_weather_change(); } catch (x) { hostS("server_log", p.name + ": on_weather_change threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_weather_change"); } catch (x) { hostS("server_log", p.name + ": on_weather_change threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_entity_heal() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_entity_heal) { try { p.h.on_entity_heal(); } catch (x) { hostS("server_log", p.name + ": on_entity_heal threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_entity_heal"); } catch (x) { hostS("server_log", p.name + ": on_entity_heal threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_food_change() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_food_change) { try { p.h.on_player_food_change(); } catch (x) { hostS("server_log", p.name + ": on_player_food_change threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_food_change"); } catch (x) { hostS("server_log", p.name + ": on_player_food_change threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_statistic() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_statistic) { try { p.h.on_player_statistic(); } catch (x) { hostS("server_log", p.name + ": on_player_statistic threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_statistic"); } catch (x) { hostS("server_log", p.name + ": on_player_statistic threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_server_list_ping() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_server_list_ping) { try { p.h.on_server_list_ping(); } catch (x) { hostS("server_log", p.name + ": on_server_list_ping threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_server_list_ping"); } catch (x) { hostS("server_log", p.name + ": on_server_list_ping threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_pre_login() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_pre_login) { try { p.h.on_player_pre_login(); } catch (x) { hostS("server_log", p.name + ": on_player_pre_login threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_pre_login"); } catch (x) { hostS("server_log", p.name + ": on_player_pre_login threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_player_level_change() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_player_level_change) { try { p.h.on_player_level_change(); } catch (x) { hostS("server_log", p.name + ": on_player_level_change threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_player_level_change"); } catch (x) { hostS("server_log", p.name + ": on_player_level_change threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_world_save() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_world_save) { try { p.h.on_world_save(); } catch (x) { hostS("server_log", p.name + ": on_world_save threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_world_save"); } catch (x) { hostS("server_log", p.name + ": on_world_save threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
function on_time_set() {
  for (var i = 0; i < __aoeP.length; i++) {
    var p = __aoeP[i];
    hostS("plugin_scope", p.name);
    if (p.h.on_time_set) { try { p.h.on_time_set(); } catch (x) { hostS("server_log", p.name + ": on_time_set threw: " + String(x)); } }
    if (p.h.__sdk) { try { p.h.__sdk.fire("on_time_set"); } catch (x) { hostS("server_log", p.name + ": on_time_set threw: " + String(x)); } }
  }
  hostS("plugin_scope", "");
}
