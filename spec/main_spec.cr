require "spec"

require "../src/main"

describe Adamas do
  it "defines a version" do
    Adamas::VERSION.should_not be_nil
  end
end
