# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
ActiveSupport::Inflector.inflections(:en) do |inflect|
  # inflect.plural /^(ox)$/i, "\\1en"
  # inflect.singular /^(ox)en/i, "\\1"
  # inflect.irregular "person", "people"
  # inflect.uncountable %w( fish sheep )

  inflect.acronym 'ICAO'  # International Civil Aviation Organization
  inflect.acronym 'FIR'   # Flight Information Region
  inflect.acronym 'ACARS' # Aircraft Communications Addressing and Reporting System
  inflect.acronym 'CASA'  # Civil Aviation Safety Authority (Australia)
  inflect.acronym 'CAANZ' # Civil Aviation Authority of New Zealand
  inflect.acronym 'VRS'   # Virtual Radar Server
  inflect.acronym 'CSV'   # Comma-Separated Values
  inflect.uncountable %w[aircraft]
end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end
