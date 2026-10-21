lib CallbackSiteIdentityOracle
  fun invoke = adamas_callback_site_invoke(callback : (Int32, UInt8* -> Void)) : Void
  fun emit_first = adamas_callback_site_emit_first(code : Int32, payload : UInt8*) : Void
  fun emit_second = adamas_callback_site_emit_second(code : Int32, payload : UInt8*) : Void
  fun exit(status : Int32) : NoReturn
end

def raise(message : String) : NoReturn
  CallbackSiteIdentityOracle.exit(91_i32)
end

CallbackSiteIdentityOracle.invoke(->(code : Int32, payload : Pointer(UInt8)) do
  CallbackSiteIdentityOracle.emit_first(code, payload)
  nil
end)

CallbackSiteIdentityOracle.invoke(->(code : Int32, payload : Pointer(UInt8)) do
  CallbackSiteIdentityOracle.emit_second(code, payload)
  nil
end)
