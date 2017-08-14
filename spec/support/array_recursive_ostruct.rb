# Helps constructing inputs similar to kubeclient results
module ArrayRecursiveOpenStruct
  def array_recursive_ostruct(hash)
    RecursiveOpenStruct.new(hash, :recurse_over_arrays => true)
  end
end

RSpec.configure do |c|
  c.include ArrayRecursiveOpenStruct
  c.extend ArrayRecursiveOpenStruct
end
