# These inflection rules are supported but not enabled by default:
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym "ICAO"
  inflect.acronym "FIR"
  inflect.acronym 'ACARS'
  inflect.acronym 'CASA'

  inflect.uncountable %w(aircraft)
end
