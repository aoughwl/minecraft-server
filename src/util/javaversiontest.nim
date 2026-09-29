## Round-trip/spot-check test for javaversion.nim's protocol-number
## additions, run via `nimony c -r`.

import std/assertions
import std/syncio
import javaversion

assert protocolVersion(jmvV1_7_2) == 4
assert protocolVersion(jmvV1_21_11) == 774
assert protocolVersion(jmvV26_3) == 777
assert protocolVersion(jmvUnknown) == -1

assert fromProtocol(4) == jmvV1_7_2
assert fromProtocol(774) == jmvV1_21_11
assert fromProtocol(777) == jmvV26_3
assert fromProtocol(999999) == jmvUnknown

assert supportsConfigurationState(jmvV1_20_2)
assert supportsConfigurationState(jmvV26_3)
assert not supportsConfigurationState(jmvV1_20)

assert isModern(jmvV1_13)
assert not isModern(jmvV1_12_2)

assert hasRegistries(jmvV1_16)
assert not hasRegistries(jmvV1_15_2)

assert displayName(jmvV1_21_4) == "1.21.4"
assert displayName(jmvUnknown) == "unknown"

assert CurrentMcVersion == jmvV26_3
assert LowestSupportedMcVersion == jmvV26_3

echo "javaversion protocol-number checks passed"
