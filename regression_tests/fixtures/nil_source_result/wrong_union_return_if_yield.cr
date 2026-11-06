def wrong_union_return_if_yield(&block : -> T) : Int32 | T forall T
  return "bad" if yield
  yield
end

wrong_union_return_if_yield { true }
