# Forked stdlib: inside `Crystal::*`, `System::Time` means `Crystal::System::Time`.
# EXPECT: system_time_shorthand_unpack_ok
module Crystal::EventLoop::SystemTimeShorthandProbe
  def self.run
    s, n = System::Time.instant
    puts s
    puts n
    puts "system_time_shorthand_unpack_ok"
  end
end

Crystal::EventLoop::SystemTimeShorthandProbe.run
