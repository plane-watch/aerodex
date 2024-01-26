class OperatorProcessor
  OPERATOR_REWRITE_PATTERNS = [
    [/Royal Flying Doctor Service.*/, 'Royal Flying Doctor Service'],
    [/State Of New South Wales Represented By Nsw Police Force/, 'NSW Police Force'],
    [/State Of New South Wales Represented By Nsw Rural Fire Service/, 'NSW Rural Fire Service'],
    [/State Of Western Australia - Represented By Commissioner Of Police/, 'Western Australia Police Force'],
  ]

  @@TRANSFORM_DATA = {}

  def self.normalise_name(name)
    OPERATOR_REWRITE_PATTERNS.each { |p| name.gsub!(p[0], p[1]) }
    name
  end

  def self.transform_field(key, value)
    if @@TRANSFORM_DATA[key].nil?
      return nil
    end

    {
      key: @@TRANSFORM_DATA[key][:field] || key,
      value: @@TRANSFORM_DATA[key][:function] ? @@TRANSFORM_DATA[key][:function].call(value) : value
    }
  end
end