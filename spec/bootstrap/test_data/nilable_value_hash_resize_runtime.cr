lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

struct SmallValue
  getter value : Int32

  def initialize(@value : Int32)
  end
end

table = Hash(String, SmallValue?).new

512.times do |index|
  key = "nilable-key-#{index}"
  value = if index % 3 == 0
            nil
          else
            SmallValue.new(index * 7 + 3)
          end
  table[key] = value
end

all_values_match = true
512.times do |index|
  key = "nilable-key-#{index}"
  actual = table[key]

  if index % 3 == 0
    all_values_match = false unless actual.nil?
  else
    if actual.nil? || actual.value != index * 7 + 3
      all_values_match = false
    end
  end
end

if all_values_match
  LibC.printf("ADAMAS_NILABLE_HASH_RESIZE_OK\n")
end
