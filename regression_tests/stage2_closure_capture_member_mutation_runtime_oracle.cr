struct Options
  property show_version : Bool = false
end

def takes_block(&block : ->) : Nil
end

def run_oracle : Int32
  options = Options.new

  if ARGV.empty?
    takes_block { options.show_version = true }
  end

  if options.show_version
    puts "version-ok"
  else
    puts "version-false"
  end
  0
end

exit run_oracle
