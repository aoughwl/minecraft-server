# src/plugin

The server side of plugins. Plugins are programs the **aoughwl engine** runs (aowlmony or JavaScript); see `docs/PLUGINS.md` for how
to write one.

| file | what |
|---|---|
| `engine/aoe.aowl` | the binding to the engine's C API (`aoe_engine.dll`, built by `tools/build_engine_dll.sh`) |
| `engine/enginehost.aowl` | loading programs and the host callback; the integer call protocol an interpreted aowlmony plugin uses |
| `engine/engineplugins.aowl` | the host calls plugins get (players, commands, tasks, events), the JavaScript bundler, and the chaining of the server's event hooks |
| `engine/enginejobs.aowl` | plugin jobs: named kernels on worker threads, `on_job` delivery (docs/PLUGIN_JOBS.md) |
| `pluginmanager.aowl` | the plugin manager: discovery, load/unload/reload, `/plugin`, `/plugins`, hot reload |
| `pluginmgr.aowl` | start-up, the join/leave events, the experience/respawn/death wrappers |
| `pluginhooks.aowl`, `pluginhooksevents.aowl` | the hooks the network and entity code call; empty until the engine chains onto them |
| `api/events/` | the event objects the server fires (`fire<Event>`), one file per event |

The engine stays outside this: it loads and runs programs. Everything about *which* plugins exist and when they load is here.
