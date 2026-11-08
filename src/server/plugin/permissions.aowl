## Native-plugin permission-string constants and their human-readable
## descriptions.
## Ported from the upstream reference implementation's plugin/permissions.rs

const
  NetworkDns* = "network.dns"
    ## Allows the plugin to perform DNS resolution (resolving hostnames to IP addresses).
  NetworkTcp* = "network.tcp"
    ## Allows the plugin to use TCP sockets.
  NetworkUdp* = "network.udp"
    ## Allows the plugin to use UDP sockets.
  NetworkTcpConnect* = "network.tcp.connect"
    ## Allows the plugin to initiate TCP connections.
  NetworkTcpBind* = "network.tcp.bind"
    ## Allows the plugin to bind TCP listeners (accept inbound connections).
  NetworkUdpConnect* = "network.udp.connect"
    ## Allows the plugin to send and receive UDP packets to specific destinations.
  NetworkUdpBind* = "network.udp.bind"
    ## Allows the plugin to bind UDP sockets to local ports.
  NetworkUdpOutgoingDatagram* = "network.udp.outgoingdatagram"
    ## Allows the plugin to send a datagram on a non-connected UDP socket.
  NetworkLoopback* = "network.loopback"
    ## Restricts all networking permissions to loopback addresses (localhost) only.
  NetworkOutbound* = "network.outbound"
    ## Allows the plugin to make outbound TCP/UDP connections.
    ## This gives the plugin full access to the host's network interfaces.
    ## **Warning:** powerful; only grant to trusted plugins.
  HttpOutbound* = "http.outbound"
    ## Allows the plugin to make outbound HTTP connections. Separate from
    ## `NetworkOutbound` - this is the higher-level HTTP surface, the other
    ## is raw sockets.
  FsReadData* = "fs.read.data"
    ## Allows the plugin to read files within its own data folder
    ## (`plugins/data/<name>`).
  FsWriteData* = "fs.write.data"
    ## Allows the plugin to write (and read) files within its own data
    ## folder. Implies `FsReadData`.
  SysEnv* = "sys.env"
    ## Allows the plugin to read all environment variables.
  SysEnvPrefix* = "sys.env."
    ## Prefix used with a specific variable name, e.g. `"sys.env.PATH"`.
  SysInfo* = "sys.info"
    ## Allows the plugin to read system information (CPU, Memory, OS).
  SysInfoCpu* = "sys.info.cpu"
    ## Allows the plugin to read CPU information.
  SysInfoRam* = "sys.info.ram"
    ## Allows the plugin to read RAM information.
  SysInfoOs* = "sys.info.os"
    ## Allows the plugin to read OS information.

proc startsWith(s, prefix: string): bool =
  if prefix.len > s.len:
    return false
  for i in 0 ..< prefix.len:
    if s[i] != prefix[i]:
      return false
  true

proc getPermissionDescription*(permission: string): (bool, string) =
  ## Port of `get_permission_description`. Returns `(found, description)`
  ## in place of Rust's `Option<&'static str>`.
  case permission
  of NetworkDns:
    (true, "Allows the plugin to perform DNS resolution (resolving hostnames to IP addresses).")
  of NetworkTcp:
    (true, "Allows the plugin to use TCP sockets.")
  of NetworkUdp:
    (true, "Allows the plugin to use UDP sockets.")
  of NetworkTcpConnect:
    (true, "Allows the plugin to initiate TCP connections.")
  of NetworkTcpBind:
    (true, "Allows the plugin to bind TCP listeners (accept inbound connections).")
  of NetworkUdpConnect:
    (true, "Allows the plugin to send and receive UDP packets to specific destinations.")
  of NetworkUdpBind:
    (true, "Allows the plugin to bind UDP sockets to local ports.")
  of NetworkUdpOutgoingDatagram:
    (true, "Allows the plugin to send datagram on non-connected UDP socket.")
  of NetworkLoopback:
    (true, "Restricts all networking permissions to loopback addresses (localhost) only.")
  of NetworkOutbound:
    (true, "Allows the plugin to make outbound TCP/UDP connections. (POWERFUL)")
  of HttpOutbound:
    (true, "Allows the plugin to make outbound HTTP requests (through wasi:http)")
  of FsReadData:
    (true, "Allows the plugin to read files within its own data folder.")
  of FsWriteData:
    (true, "Allows the plugin to write (and read) files within its own data folder. Implies fs.read.data.")
  of SysEnv:
    (true, "Allows the plugin to read all environment variables.")
  of SysInfo:
    (true, "Allows the plugin to read system information (CPU, Memory, OS).")
  of SysInfoCpu:
    (true, "Allows the plugin to read CPU information.")
  of SysInfoRam:
    (true, "Allows the plugin to read RAM information.")
  of SysInfoOs:
    (true, "Allows the plugin to read OS information.")
  else:
    if startsWith(permission, SysEnvPrefix):
      (true, "Allows the plugin to read specific environment variables.")
    else:
      (false, "")
