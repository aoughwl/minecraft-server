import { x } from "server";
export const unused = 1;
export function start() { hostS("server_log", "module loaded"); }
export function on_player_command() { hostS("server_log", "module saw " + hostv("event_str", "message")); }
