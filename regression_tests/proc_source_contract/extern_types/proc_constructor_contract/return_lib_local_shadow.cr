alias ShadowWord = UInt8
lib LocalReturnAliasRuntime
  alias ShadowWord = Int32
  fun putchar(value : ShadowWord) : ShadowWord
end
LocalReturnAliasRuntime.putchar(70_i32)
LocalReturnAliasRuntime.putchar(10_i32)
