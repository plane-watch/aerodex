module AircraftHelper
  def cabin_configuration(config)
    [] if config.nil? || config.blank?
    classes = []
    config&.split(/(?=[A-Z])/)&.each do |section|
      class_type, count = section.scan(/([A-Z])(\d+)/).flatten
      case class_type
      when 'F', 'A'
        classes << "#{count} First Class"
      when 'C', 'J', 'R', 'D', 'I'
        classes << "#{count} Business Class"
      when 'W', 'P'
        classes << "#{count} Premium Economy"
      when 'Y', 'H', 'K', 'M', 'L', 'G', 'V', 'S', 'N,' 'Q', 'O', 'E'
        classes << "#{count} Economy"
      when 'B'
        classes << "#{count} Basic Economy"
      else
        classes << "#{count} Other"
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
    content_tag :span, status.capitalize, class: "ml-2 inline-flex items-center rounded-md px-2 py-0.5 shadow text-xs font-medium ring-1 ring-inset #{classes}"
  end
end
