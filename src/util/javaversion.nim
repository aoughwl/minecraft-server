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
    jmvV26_1, jmvV26_2, jmvV26_3

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
