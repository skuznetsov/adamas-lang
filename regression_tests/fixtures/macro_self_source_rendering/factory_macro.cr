macro build_factory(label, return_type, expression)
  def self.build({{label.id}} value : Int32) : {{return_type}}
    {{expression}}
  end
end
