class SelectedInitializerMissingRequired
  def initialize(name : String?, external_name : String?, type_annotation : String, flag : Bool = false)
  end
end

SelectedInitializerMissingRequired.new(nil, nil)
