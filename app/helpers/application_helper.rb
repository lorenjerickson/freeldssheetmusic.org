# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
	include Substruct
	
	def current_user_notice
    unless session[:user]
      link_to "Log In", :controller => "/accounts", :action=>"login"
    else
      link_to "Log Out", :controller => "/accounts", :action=>"logout"
    end
  end
  
  def make_label(name, required=false)
    output_str = "<label>"
    output_str << "<span style=\"color:red;\">*</span>" if required == true
    output_str << name
    output_str << "</label>"
    return output_str
  end
  
  # Overridden number_to_currency which can handle
  # an array for price "ranges", as passed back by
  # Product::display_price
  #
  # We only pass 2 items in, but could display more...
  #
  def sub_number_to_currency(number, options = {:unit => "$", :separator => ".", :delimiter => ","})
    if number.class == Array
      str = number_to_currency(number[0], options) + "+"
    elsif number.nil?
      str = options[:unit]
    else
      str = number_to_currency(number, options)
    end
    
    return str
  end
  
  # When browsing the store by tags we need to know what
  # is the main "parent" tag or tag group.
  #
  # This lets us display the "active" state in the UI
  # appears to vary based on @viewing_tags
  #
  def is_main_tab_active?(tab_id)
    if @viewing_tags
      for tag in [@viewing_tags[0], @viewing_tags[0].parent, @viewing_tags[0].parent.andand.parent]
        if tag.andand.id == tab_id
          # main bar subnav disabled currently...
          #@show_subnav = true
          #@main_tag_active = Tag.find(tab_id)
          #@subnav_tags = @main_tag_active.children
          #@show_subnav = false if (@main_tag_active.products.size==0)  # don't show ones that we want them to choose another subcat on 
          return true
        end
      end
    end
    
    return false
  end
  
  def is_sub_tab_active?(tab_id) # unused, I think
    if @viewing_tags && @viewing_tags.size > 1 && @viewing_tags[1].id == tab_id
      @show_subnav = true
      return true
    end
    return false
  end

  def tag_link_nav tag, is_bullet_style=true
    if tag.name_in_nav.present?
      tag_link(tag, tag.name_in_nav, is_bullet_style)
    else
      tag_link(tag, tag.name, is_bullet_style)
    end
  end

  def tag_link tag, name_to_use=tag.name, is_bullet=false
    escaped_name = URI.escape(tag.name, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
    if is_bullet
      "<a style=\"margin-left: -20px; padding-left: 20px;\" href=\"/#{escaped_name.gsub("%20", "_")}\">#{name_to_use}</a>"
    else
      "<a href=\"/#{escaped_name.gsub("%20", "_")}\">#{name_to_use}</a>"
    end
  end

end
