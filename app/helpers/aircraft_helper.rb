module AircraftHelper
  def cabin_configuration(config)
    [] if config.nil? || config.blank?
    classes = []
    config&.split(/(?=[A-Z])/)&.each do |section|
      class_type, count = section.scan(/([A-Z])(\d+)/).flatten
      classes << case class_type
                 when 'F', 'A'
                   "#{count} First Class"
                 when 'C', 'J', 'R', 'D', 'I'
                   "#{count} Business Class"
                 when 'W', 'P'
                   "#{count} Premium Economy"
                 # TODO: `'N,' 'Q'` is implicit string concatenation, so this
                 # branch tests for the single value 'N,Q'. As `class_type` is
                 # always one character it can never match, and configurations
                 # using 'N' or 'Q' fall through to 'Other' rather than
                 # 'Economy'. The intent was almost certainly `'N', 'Q'`.
                 # Left as-is because correcting it changes rendered output,
                 # which is outside the scope of a formatting change.
                 when 'Y', 'H', 'K', 'M', 'L', 'G', 'V', 'S', 'N,' 'Q', 'O', 'E'
                   "#{count} Economy"
                 when 'B'
                   "#{count} Basic Economy"
                 else
                   "#{count} Other"
                 end
    end

    classes
  end

  def aircraft_status_badge(status)
    classes = case status.downcase
              when 'active'
                'bg-green-50 text-green-400 ring-green-600/20'
              when 'stored', 'withdrawn'
                'bg-yellow-50 text-yellow-400 ring-yellow-600/20'
              when 'destroyed', 'scrapped', 'written off'
                'bg-red-50 text-red-400 ring-red-600/20'
              else
                'bg-gray-50 text-gray-400 ring-gray-600/20'
              end
    content_tag :span, status.capitalize,
                class: "ml-2 inline-flex items-center rounded-md px-2 py-0.5 shadow text-xs font-medium ring-1 ring-inset #{classes}"
  end
end
