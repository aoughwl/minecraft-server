## Port of upstream/config/src/server_links.rs

import std/tables

type
  ServerLinksConfig* = object
    enabled*: bool
    bugReport*: string
    support*: string
    status*: string
    feedback*: string
    community*: string
    website*: string
    forums*: string
    news*: string
    announcements*: string
    custom*: Table[string, string]

proc defaultServerLinksConfig*(): ServerLinksConfig =
  ServerLinksConfig(
    enabled: true,
    bugReport: "https://github.com/MC/the upstream server/issues",
    support: "",
    status: "",
    feedback: "",
    community: "",
    website: "",
    forums: "",
    news: "",
    announcements: "",
    custom: initTable[string, string](),
  )
