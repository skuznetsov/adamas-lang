def nil_guarded_any?(values : Array(Int32?)?) : Bool
  return false unless values

  values.any? do |value|
    next false unless value
    value > 0
  end
end

def nil_guarded_else?(value : String?) : Bool
  unless value.nil?
    value.includes?("needle")
  else
    true
  end
end

def live_guarded_any?(values : Array(Int32?)?) : Bool
  return false unless values

  values.any? do |value|
    next false unless value
    value > 0
  end
end

puts nil_guarded_any?(nil)
puts nil_guarded_else?(nil)
puts live_guarded_any?([1, nil])
