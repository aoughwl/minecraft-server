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
  Player.prototype.give = function (item, count) { return hostv("player_give", this.name, item, count) == true; };
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

  var server = {
    log: function (text) { hostS("server_log", text); },
    broadcast: function (text) { hostS("server_broadcast", text); },
    onlineCount: function () { return hostv("server_player_count"); },
    player: function (name) { return new Player(name); },
    blockAt: function (x, y, z) { return hostv("world_get_block", x, y, z); },
    setBlock: function (x, y, z, name) { return hostv("world_set_block", x, y, z, name) == true; },
    entityHealth: function (id) { return hostv("entity_health", id); },
    setEntityHealth: function (id, health) { return hostv("entity_set_health", id, health) == true; },
    entityPos: function (id) { return { x: hostv("entity_pos", id, "x"), y: hostv("entity_pos", id, "y"), z: hostv("entity_pos", id, "z") }; },
    teleportEntity: function (id, x, y, z) { return hostv("entity_teleport", id, x, y, z) == true; },
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
    CustomPayloadEvent: ["on_player_custom_payload", function () { return { player: P(), channel: str("channel"), length: num("length") }; }],
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
    var list = handlers[entry];
    if (!list || !byEntry[entry]) return;
    var ev = byEntry[entry]();
    ev.cancelled = false;
    ev.cancel = function () { this.cancelled = true; };
    var before = { message: ev.message, kickMessage: ev.kickMessage, drop: ev.drop, granted: ev.granted, hatching: ev.hatching, amount: ev.amount,
                   motd: ev.motd, maxPlayers: ev.maxPlayers, level: ev.level, time: ev.time };
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
  }

  return {
    fire: fire, on: on, command: command, after: after, every: every, cancelTask: cancelTask, server: server, tokens: tokens,
    onEnable: function (fn) { enables.push(fn); }, onDisable: function (fn) { disables.push(fn); }
  };
})();

var on = __sdk.on, command = __sdk.command, after = __sdk.after, every = __sdk.every, cancelTask = __sdk.cancelTask;
var onEnable = __sdk.onEnable, onDisable = __sdk.onDisable, server = __sdk.server;
var ChatEvent = __sdk.tokens.ChatEvent, PlayerCommandEvent = __sdk.tokens.PlayerCommandEvent, JoinEvent = __sdk.tokens.JoinEvent;
var LeaveEvent = __sdk.tokens.LeaveEvent, LoginEvent = __sdk.tokens.LoginEvent, MoveEvent = __sdk.tokens.MoveEvent;
var TeleportEvent = __sdk.tokens.TeleportEvent, ToggleEvent = __sdk.tokens.ToggleEvent, GamemodeChangeEvent = __sdk.tokens.GamemodeChangeEvent;
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
