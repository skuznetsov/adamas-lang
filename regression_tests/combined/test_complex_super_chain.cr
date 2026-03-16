# Complex: Multi-level super calls, module method resolution order
# EXPECT: super_chain_all_ok

module Loggable
  def log_action(action : String) : String
    "[LOG] #{action}"
  end
end

module Cacheable
  def cache_key : String
    "cache:#{self.class}"
  end
end

class Repository
  include Loggable

  def find(id : Int32) : String
    "repo:#{id}"
  end

  def save(data : String) : String
    log_action("save(#{data})")
  end
end

class CachedRepository < Repository
  include Cacheable

  def find(id : Int32) : String
    key = cache_key
    "#{key}->#{super(id)}"
  end

  def save(data : String) : String
    key = cache_key
    "#{key}->#{super(data)}"
  end
end

class AuditedRepository < CachedRepository
  def find(id : Int32) : String
    result = super(id)
    puts log_action("find(#{id})")
    result
  end

  def save(data : String) : String
    result = super(data)
    puts log_action("save-audit(#{data})")
    result
  end
end

repo = AuditedRepository.new
puts repo.find(42)
puts repo.save("test")

# --- Virtual dispatch through base ---
repos = [] of Repository
repos << Repository.new
repos << CachedRepository.new
repos << AuditedRepository.new

repos.each do |r|
  puts r.find(1)
end

# --- Module method resolution with super ---
module Stringifiable
  def to_s : String
    "Stringifiable"
  end
end

class Base2
  def to_s : String
    "Base2"
  end
end

class Mid2 < Base2
  include Stringifiable

  def to_s : String
    "Mid2(#{super})"
  end
end

class Leaf2 < Mid2
  def to_s : String
    "Leaf2(#{super})"
  end
end

puts Leaf2.new.to_s

puts "super_chain_all_ok"
