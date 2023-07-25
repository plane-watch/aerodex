class CallsignPatternValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    begin
      Regexp.new(value)
    rescue RegexpError
      record.errors.add(attribute, "is not a valid regular expression")
    end
  end
end