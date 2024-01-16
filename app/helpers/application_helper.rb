module ApplicationHelper
  def tailwind_text_classes_for(flash_type)
    {
      notice: 'text-green-700',
      error: 'text-red-700',
      alert: 'text-yellow-700',
    }.stringify_keys[flash_type.to_s] || flash_type.to_s
  end

  def tailwind_classes_for(flash_type)
    klasses = {
      notice: 'bg-green-50 border-l-4 border-green-700',
      error: 'bg-red-50 border-l-4 border-red-700',
      alert: 'bg-yellow-50 border-l-4 border-yellow-700',
    }.stringify_keys[flash_type.to_s] || flash_type.to_s

    "#{klasses} #{tailwind_text_classes_for(flash_type)}"
  end

  def render_errors_for(obj)
    render partial: 'shared/errors', locals: { obj: obj } if obj.errors.any?
  end

  def avatar_url_for(email, opts = {})
    size = opts[:size || 32]
    hash = Digest::MD5.hexdigest(email.downcase)
    "https://secure.gravatar.com/avatar/#{hash}.png?s=#{size}"
  end

end
