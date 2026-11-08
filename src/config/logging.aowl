## Port of upstream/config/src/logging.rs

type
  LoggingConfig* = object
    enabled*: bool
    level*: string
    threads*: bool
    threadIds*: bool
    target*: bool
    color*: bool
    timestamp*: bool
    timestampFormat*: string
    file*: string

proc defaultLoggingConfig*(): LoggingConfig =
  LoggingConfig(
    enabled: true,
    level: "info",
    threads: false,
    threadIds: false,
    target: false,
    color: true,
    timestamp: true,
    timestampFormat: "[hour]:[minute]:[second]",
    file: "latest.log",
  )
