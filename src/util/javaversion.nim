## Port of pumpkin_util::version::JavaMinecraftVersion, as mirrored into
## tools/codegen/src/version.rs (206 lines) for token-emission use by other
## generators. Unlike the other data_codegen submodules this isn't
## JSON-driven - it's a hand-authored, ordered enum of every Java Edition
## protocol version this server distinguishes, so it's a direct port here
## rather than a `gen_*.nim` script under src/data_codegen/.
##
## Declaration order matters: upstream derives `PartialOrd`/`Ord` from
## enum discriminant order to compare versions ("is the client at least
## 1.20.5"), so this enum's declaration order must match upstream's
## exactly - it does, line for line.

type
  JavaMinecraftVersion* = enum
    jmvV1_7_2, jmvV1_7_6, jmvV1_8, jmvV1_9, jmvV1_9_1, jmvV1_9_2, jmvV1_9_3,
    jmvV1_10, jmvV1_11, jmvV1_11_1, jmvV1_12, jmvV1_12_1, jmvV1_12_2,
    jmvV1_13, jmvV1_13_1, jmvV1_13_2, jmvV1_14, jmvV1_14_1, jmvV1_14_2,
    jmvV1_14_3, jmvV1_14_4, jmvV1_15, jmvV1_15_1, jmvV1_15_2, jmvV1_16,
    jmvV1_16_1, jmvV1_16_2, jmvV1_16_3, jmvV1_16_4, jmvV1_17, jmvV1_17_1,
    jmvV1_18, jmvV1_18_2, jmvV1_19, jmvV1_19_1, jmvV1_19_3, jmvV1_19_4,
    jmvV1_20, jmvV1_20_2, jmvV1_20_3, jmvV1_20_5, jmvV1_21, jmvV1_21_2,
    jmvV1_21_4, jmvV1_21_5, jmvV1_21_6, jmvV1_21_7, jmvV1_21_9, jmvV1_21_11,
    jmvV26_1, jmvV26_2, jmvV26_3, jmvUnknown

proc toFieldIdent*(v: JavaMinecraftVersion): string =
  ## Port of `to_field_ident`: a snake_case name suitable as a struct field
  ## (`v1_21_4` for `V_1_21_4`), used where upstream keys a per-version
  ## config/behavior struct by field name.
  case v
  of jmvV1_7_2: "v1_7_2"
  of jmvV1_7_6: "v1_7_6"
  of jmvV1_8: "v1_8"
  of jmvV1_9: "v1_9"
  of jmvV1_9_1: "v1_9_1"
  of jmvV1_9_2: "v1_9_2"
  of jmvV1_9_3: "v1_9_3"
  of jmvV1_10: "v1_10"
  of jmvV1_11: "v1_11"
  of jmvV1_11_1: "v1_11_1"
  of jmvV1_12: "v1_12"
  of jmvV1_12_1: "v1_12_1"
  of jmvV1_12_2: "v1_12_2"
  of jmvV1_13: "v1_13"
  of jmvV1_13_1: "v1_13_1"
  of jmvV1_13_2: "v1_13_2"
  of jmvV1_14: "v1_14"
  of jmvV1_14_1: "v1_14_1"
  of jmvV1_14_2: "v1_14_2"
  of jmvV1_14_3: "v1_14_3"
  of jmvV1_14_4: "v1_14_4"
  of jmvV1_15: "v1_15"
  of jmvV1_15_1: "v1_15_1"
  of jmvV1_15_2: "v1_15_2"
  of jmvV1_16: "v1_16"
  of jmvV1_16_1: "v1_16_1"
  of jmvV1_16_2: "v1_16_2"
  of jmvV1_16_3: "v1_16_3"
  of jmvV1_16_4: "v1_16_4"
  of jmvV1_17: "v1_17"
  of jmvV1_17_1: "v1_17_1"
  of jmvV1_18: "v1_18"
  of jmvV1_18_2: "v1_18_2"
  of jmvV1_19: "v1_19"
  of jmvV1_19_1: "v1_19_1"
  of jmvV1_19_3: "v1_19_3"
  of jmvV1_19_4: "v1_19_4"
  of jmvV1_20: "v1_20"
  of jmvV1_20_2: "v1_20_2"
  of jmvV1_20_3: "v1_20_3"
  of jmvV1_20_5: "v1_20_5"
  of jmvV1_21: "v1_21"
  of jmvV1_21_2: "v1_21_2"
  of jmvV1_21_4: "v1_21_4"
  of jmvV1_21_5: "v1_21_5"
  of jmvV1_21_6: "v1_21_6"
  of jmvV1_21_7: "v1_21_7"
  of jmvV1_21_9: "v1_21_9"
  of jmvV1_21_11: "v1_21_11"
  of jmvV26_1: "v26_1"
  of jmvV26_2: "v26_2"
  of jmvV26_3: "v26_3"
  of jmvUnknown: "unknown"

proc protocolVersion*(v: JavaMinecraftVersion): int32 =
  ## Port of `protocol_version`: the network protocol number for this
  ## version. -1 for `jmvUnknown`.
  int32(case v
  of jmvV1_7_2: 4
  of jmvV1_7_6: 5
  of jmvV1_8: 47
  of jmvV1_9: 107
  of jmvV1_9_1: 108
  of jmvV1_9_2: 109
  of jmvV1_9_3: 110
  of jmvV1_10: 210
  of jmvV1_11: 315
  of jmvV1_11_1: 316
  of jmvV1_12: 335
  of jmvV1_12_1: 338
  of jmvV1_12_2: 340
  of jmvV1_13: 393
  of jmvV1_13_1: 401
  of jmvV1_13_2: 404
  of jmvV1_14: 477
  of jmvV1_14_1: 480
  of jmvV1_14_2: 485
  of jmvV1_14_3: 490
  of jmvV1_14_4: 498
  of jmvV1_15: 573
  of jmvV1_15_1: 575
  of jmvV1_15_2: 578
  of jmvV1_16: 735
  of jmvV1_16_1: 736
  of jmvV1_16_2: 751
  of jmvV1_16_3: 753
  of jmvV1_16_4: 754
  of jmvV1_17: 755
  of jmvV1_17_1: 756
  of jmvV1_18: 757
  of jmvV1_18_2: 758
  of jmvV1_19: 759
  of jmvV1_19_1: 760
  of jmvV1_19_3: 761
  of jmvV1_19_4: 762
  of jmvV1_20: 763
  of jmvV1_20_2: 764
  of jmvV1_20_3: 765
  of jmvV1_20_5: 766
  of jmvV1_21: 767
  of jmvV1_21_2: 768
  of jmvV1_21_4: 769
  of jmvV1_21_5: 770
  of jmvV1_21_6: 771
  of jmvV1_21_7: 772
  of jmvV1_21_9: 773
  of jmvV1_21_11: 774
  of jmvV26_1: 775
  of jmvV26_2: 776
  of jmvV26_3: 777
  of jmvUnknown: -1)

proc fromProtocol*(protocol: uint32): JavaMinecraftVersion =
  ## Port of `from_protocol`: resolves a version from a network protocol
  ## number, or `jmvUnknown` if unrecognized.
  case protocol
  of 4: jmvV1_7_2
  of 5: jmvV1_7_6
  of 47: jmvV1_8
  of 107: jmvV1_9
  of 108: jmvV1_9_1
  of 109: jmvV1_9_2
  of 110: jmvV1_9_3
  of 210: jmvV1_10
  of 315: jmvV1_11
  of 316: jmvV1_11_1
  of 335: jmvV1_12
  of 338: jmvV1_12_1
  of 340: jmvV1_12_2
  of 393: jmvV1_13
  of 401: jmvV1_13_1
  of 404: jmvV1_13_2
  of 477: jmvV1_14
  of 480: jmvV1_14_1
  of 485: jmvV1_14_2
  of 490: jmvV1_14_3
  of 498: jmvV1_14_4
  of 573: jmvV1_15
  of 575: jmvV1_15_1
  of 578: jmvV1_15_2
  of 735: jmvV1_16
  of 736: jmvV1_16_1
  of 751: jmvV1_16_2
  of 753: jmvV1_16_3
  of 754: jmvV1_16_4
  of 755: jmvV1_17
  of 756: jmvV1_17_1
  of 757: jmvV1_18
  of 758: jmvV1_18_2
  of 759: jmvV1_19
  of 760: jmvV1_19_1
  of 761: jmvV1_19_3
  of 762: jmvV1_19_4
  of 763: jmvV1_20
  of 764: jmvV1_20_2
  of 765: jmvV1_20_3
  of 766: jmvV1_20_5
  of 767: jmvV1_21
  of 768: jmvV1_21_2
  of 769: jmvV1_21_4
  of 770: jmvV1_21_5
  of 771: jmvV1_21_6
  of 772: jmvV1_21_7
  of 773: jmvV1_21_9
  of 774: jmvV1_21_11
  of 775: jmvV26_1
  of 776: jmvV26_2
  of 777: jmvV26_3
  else: jmvUnknown

proc supportsConfigurationState*(v: JavaMinecraftVersion): bool =
  v.protocolVersion() >= jmvV1_20_2.protocolVersion()

proc isModern*(v: JavaMinecraftVersion): bool =
  v.protocolVersion() >= jmvV1_13.protocolVersion()

proc hasRegistries*(v: JavaMinecraftVersion): bool =
  v.protocolVersion() >= jmvV1_16.protocolVersion()

proc displayName*(v: JavaMinecraftVersion): string =
  ## Port of the `Display` impl (human-readable version string, e.g.
  ## "1.21.4"), distinct from `toFieldIdent`'s identifier-safe form.
  case v
  of jmvV1_7_2: "1.7.2"
  of jmvV1_7_6: "1.7.6"
  of jmvV1_8: "1.8"
  of jmvV1_9: "1.9"
  of jmvV1_9_1: "1.9.1"
  of jmvV1_9_2: "1.9.2"
  of jmvV1_9_3: "1.9.3"
  of jmvV1_10: "1.10"
  of jmvV1_11: "1.11"
  of jmvV1_11_1: "1.11.1"
  of jmvV1_12: "1.12"
  of jmvV1_12_1: "1.12.1"
  of jmvV1_12_2: "1.12.2"
  of jmvV1_13: "1.13"
  of jmvV1_13_1: "1.13.1"
  of jmvV1_13_2: "1.13.2"
  of jmvV1_14: "1.14"
  of jmvV1_14_1: "1.14.1"
  of jmvV1_14_2: "1.14.2"
  of jmvV1_14_3: "1.14.3"
  of jmvV1_14_4: "1.14.4"
  of jmvV1_15: "1.15"
  of jmvV1_15_1: "1.15.1"
  of jmvV1_15_2: "1.15.2"
  of jmvV1_16: "1.16"
  of jmvV1_16_1: "1.16.1"
  of jmvV1_16_2: "1.16.2"
  of jmvV1_16_3: "1.16.3"
  of jmvV1_16_4: "1.16.4"
  of jmvV1_17: "1.17"
  of jmvV1_17_1: "1.17.1"
  of jmvV1_18: "1.18"
  of jmvV1_18_2: "1.18.2"
  of jmvV1_19: "1.19"
  of jmvV1_19_1: "1.19.1"
  of jmvV1_19_3: "1.19.3"
  of jmvV1_19_4: "1.19.4"
  of jmvV1_20: "1.20"
  of jmvV1_20_2: "1.20.2"
  of jmvV1_20_3: "1.20.3"
  of jmvV1_20_5: "1.20.5"
  of jmvV1_21: "1.21"
  of jmvV1_21_2: "1.21.2"
  of jmvV1_21_4: "1.21.4"
  of jmvV1_21_5: "1.21.5"
  of jmvV1_21_6: "1.21.6"
  of jmvV1_21_7: "1.21.7"
  of jmvV1_21_9: "1.21.9"
  of jmvV1_21_11: "1.21.11"
  of jmvV26_1: "26.1"
  of jmvV26_2: "26.2"
  of jmvV26_3: "26.3"
  of jmvUnknown: "unknown"

const
  CurrentMcVersion* = jmvV26_3
    ## Port of `pumpkin_data::packet::CURRENT_MC_VERSION` (currently
    ## generated as V_26_3 upstream; a hand-copied constant here since the
    ## `pumpkin-data` registry crate isn't ported).
  LowestSupportedMcVersion* = jmvV26_3
    ## Port of `pumpkin_data::packet::LOWEST_SUPPORTED_MC_VERSION` (also
    ## V_26_3 upstream at time of writing - current and lowest-supported
    ## happen to coincide right now).
