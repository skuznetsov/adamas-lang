# EXPECT: channel_receive_ok

ch = Channel(Int32).new

spawn do
  ch.send(7)
end

value = ch.receive
if value == 7
  puts "channel_receive_ok"
else
  puts "channel_receive_bad: #{value}"
end
