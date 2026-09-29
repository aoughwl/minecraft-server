## Lighting engine calculation mode.
## Port of upstream/config/src/lighting.rs
## Serde attrs (`rename_all = "lowercase"`) dropped - no (de)serialize layer
## ported yet.

type
  LightingEngineConfig* = enum
    lecDefault ## Default Vanilla lighting propagation.
    lecFull    ## Full skylight everywhere (no shadows).
    lecDark    ## Completely dark lighting everywhere (zero light).

proc defaultLightingEngineConfig*(): LightingEngineConfig {.inline.} =
  lecDefault
