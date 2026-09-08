lib LibC
  fun exit(status : Int32) : NoReturn
  fun putchar(value : Int32) : Int32
end
class EntryOwner
  struct Entry
    def initialize(@name : Int32)
    end
    def name : Int32
      @name
    end
  end
  class Handle
    @read : Bool = false
    def initialize(@value : Int32)
    end
    def self.open(value : Int32, & : self ->)
      yield new(value)
    end
    def next_entry : EntryOwner::Entry?
      return nil if @read
      @read = true
      EntryOwner::Entry.new(@value)
    end
  end
  def read_entry(dir)
    return unless dir
    dir.next_entry
  end
  def each_child(value : Int32, &)
    Handle.open(value) do |dir|
      while entry = read_entry(dir)
        yield entry
      end
    end
  end
end
owner = EntryOwner.new
owner.each_child(73) do |entry|
  LibC.putchar(entry.name)
end
owner.each_child(94) do |entry|
  LibC.putchar(entry.name)
end
LibC.putchar(10)
LibC.exit(0)
