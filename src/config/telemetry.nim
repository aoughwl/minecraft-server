## Port of pumpkingmc/crates/pumpkin-config/src/telemetry.rs

import std/options

type
  TelemetryConfig* = object
    enabled*: bool
    endpoint*: string
    intervalSecs*: uint64
    public*: bool
    serverName*: Option[string]

proc defaultTelemetryConfig*(): TelemetryConfig =
  TelemetryConfig(
    enabled: true,
    endpoint: "https://market.pumpkinmc.org/api/v1/rest/telemetry/heartbeat",
    intervalSecs: 300'u64,
    public: false,
    serverName: none[string](),
  )

proc validate*(t: TelemetryConfig) =
  discard
