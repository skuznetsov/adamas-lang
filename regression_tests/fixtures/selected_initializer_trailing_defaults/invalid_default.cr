class SelectedInitializerInvalidDefault
  def initialize(required : Int32, optional : Int32 = "not an Int32")
  end
end

SelectedInitializerInvalidDefault.new(1)
