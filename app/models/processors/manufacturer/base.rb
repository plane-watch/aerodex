# frozen_string_literal: true

module Processors
  module Manufacturer
    # Base class for manufacturer-related processors
    class Base
      include Processors::Base

      @transform_data = {}
    end
  end
end