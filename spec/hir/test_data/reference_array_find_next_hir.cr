class ReferenceArrayFindNextItem
  getter kind : Int32

  def initialize(@kind : Int32)
  end
end

variants = [ReferenceArrayFindNextItem.new(0), ReferenceArrayFindNextItem.new(1)]
best = variants.find do |variant|
  next if variant.kind == 0
  variant.kind == 1
end
missing = variants.find { |variant| variant.kind == 7 }
empty = ([] of ReferenceArrayFindNextItem).find { |variant| variant.kind == 1 }

if best && best.kind == 1 && missing.nil? && empty.nil?
  puts "generated-reference-array-find-next-ok"
else
  puts "generated-reference-array-find-next-wrong"
end
