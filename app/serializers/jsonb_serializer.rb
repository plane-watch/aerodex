class JsonbSerializer

  def self.dump(hash)
    hash
  end

  def self.load(hash)
    HashWithIndifferentAccess.new(hash)
  end
end