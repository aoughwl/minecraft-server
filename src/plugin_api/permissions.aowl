## Built-in plugin permission identifiers (sandboxing capability strings).
## Port of upstream/plugin-api/src/permissions.rs

const
  NetworkDns* = "network.dns"
    ## Allows the plugin to perform DNS resolution.
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
    ## Allows the plugin to send datagrams on a non-connected UDP socket.
  NetworkLoopback* = "network.loopback"
    ## Restricts all networking permissions to loopback addresses (localhost) only.
  NetworkOutbound* = "network.outbound"
    ## Allows the plugin to make outbound TCP/UDP connections. Warning: powerful.
  HttpOutbound* = "http.outbound"
    ## Allows the plugin to make outbound HTTP connections (wasi:http, distinct
    ## from `NetworkOutbound`'s wasi:sockets).
  FsReadData* = "fs.read.data"
    ## Allows the plugin to read files within its own data folder
    ## (`plugins/data/<name>`).
  FsWriteData* = "fs.write.data"
    ## Allows the plugin to write (and read) files within its own data folder.
    ## Implies `FsReadData`.
  SysEnv* = "sys.env"
    ## Allows the plugin to read all environment variables.
  SysEnvPrefix* = "sys.env."
    ## Prefix for a specific-environment-variable permission, e.g. "sys.env.PATH".
  SysInfo* = "sys.info"
    ## Allows the plugin to read system information (CPU, Memory, OS).
  SysInfoCpu* = "sys.info.cpu"
    ## Allows the plugin to read CPU information.
  SysInfoRam* = "sys.info.ram"
    ## Allows the plugin to read RAM information.
  SysInfoOs* = "sys.info.os"
    ## Allows the plugin to read OS information.
