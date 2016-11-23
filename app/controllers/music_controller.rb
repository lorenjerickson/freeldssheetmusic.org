class MusicController < StoreController
 @@per_page = 11116

 skip_before_filter :verify_authenticity_token, :only => [:add_comment, :search, :add_comment_competition]

  def session_object
    @_session_object ||= Session.find_or_create_by_sessid(session_id) # used for session_object method...which I use to lookup session things like bookmarks
  end

   # Wishlist items
  def wishlist
     @title = "Saved Bookmarked songs (this computer)"
     @wishlist_items = session_object.wishlist_items # lacks pagination...
  end

  def add_to_wishlist
    if params[:id]
      if item = Item.find_by_id(params[:id])
        if not_a_bot || logged_in_admin_user?
          session_object.wishlist_items << WishlistItem.new(:item_id => item.id)
        end
      else
        flash[:notice] = "Sorry, we couldn't find the item that you wanted to add to your wishlist. Please try again."
      end
    else
      flash[:notice] = "You didn't specify an item to add to your wishlist..."
    end
    redirect_to :action => 'wishlist' and return
  end

  def remove_wishlist_item
    WishlistItem.find(params[:id]).destroy
    render :text => '' # render nothing...
  end

  private
  def session_id
    # request.session_options[:id] is a big long string I believe..
    # like "abcdefrandomrandomrandom"
    request.session_options[:id]
  end

   # stable, but random just for them :)
  def session_rand
    # session_id is an always present big long string I believe..
    "rand(#{session_id.consistent_hash})"
  end

  def session_ip
    request.remote_ip
  end

  def look_for_recent_comment id
    @old_comment = Comment.find(:first, :conditions => ['product_id = ? and (created_ip = ? or created_session = ?)', id, session_ip, session_id], :order => "created_at desc")
  end

  public

  def check_if_out_of_space
    bytes_free = `df -B1 .`.split[10].to_i
    if bytes_free < 512.megabyte
      raise "low space #{bytes_free}"
    end
    render :text => "ok disk space #{bytes_free}"
  end

  def competition
    content = ContentNode.find_by_name('competition-header')
    @title = content.title
    @header = "" # let content define it, instead of overriding it...
    @show_green = true
    order = session_rand
    if params['order'] == 'newest'
      order = "updated_at desc"
    end
    @products = paginate_and_filter(Product.find(:all,
      :order => order,
      :conditions => ["is_competition=?", true]
    ), 50000)
    @was_filtered_able = false
    @display_bio = content.content
    render :action => 'competition.rhtml'
  end

  def competition_results
    @content_node = ContentNode.find_by_name('competition-results')
    @title = @content_node.title
    @products = Product.find(:all, :conditions => {:is_competition => true}).sort_by{|p| p.total_valid_competition_points }.reverse
    @peer_review_products = Product.find(:all, :conditions => {:is_competition => true}).sort_by{|p| p.competition_peer_review_average}.select{|p| p.competition_peer_review_average >= 4.0}.reverse

  end

  def add_comment_competition
    look_for_recent_comment params['id']
    product, comment = add_comment_helper true
    if @old_comment # smelly, ugly logic too yikes
      flash[:notice] = "Looks like you already voted for this song .  This year we only allow one vote per household per song, but feel free to vote on our other pieces"
      comment.destroy
    elsif comment
      flash[:notice] = "Vote/Review recorded! Thanks! Also feel free to check out our songs from other composers..."
    end

    redirect_to :action => :show, :id => product.code
  end

  def add_comment
    product, possible_comment = add_comment_helper false
    redirect_to :action => :show, :id => product.code
  end

  def is_spam_comment?
    if (params['recaptcha'] || '').downcase != 'sunday'
      return true
    end
    if params[:user_url] =~ /customink/i
      return true # some kind of live'ish spammer, hope I don't run into too many here
    end
    false
  end

  def add_comment_helper is_competition
   product = Product.find(params['id']) # don't handle 404 LOL
   if is_spam_comment?
     flash[:notice] = "Spam avoidance question answer failed (the answer is sunday, you put #{params['recaptcha']}) -- hit back in your browser and enter Monday in the last field, to enter sunday and try again!"
     return [product, nil]
   else
     new_hash = {}
     # extract the ones we care about
     for key in [:id, :comment, :user_name, :user_email, :user_url, :overall_rating, :difficulty_rating]
      new_hash[key] = params[key]
     end
     new_hash[:is_competition] = is_competition
     if is_competition && params[:overall_rating].to_i > 0
       #raise "voting has not started for this year yet, try again soon!"
     end
     comment = Comment.new(new_hash)
     comment.created_session = session_id
     comment.created_ip = session_ip
     comment.overall_rating ||= -1 # guess a DB default isn't enough [?] that is so weird...rails defaulting everything to nil...
     comment.created_admin_user_id = session[:user]
     comment.save
     product.comments << comment # might also perform a comment save?
     flash[:notice] = 'Comment saved! Thanks for your contribution to LDS music!'
     if !comment.is_competition? || (comment.is_competition? && comment.comment.present?) # only send competition ones if it says something...
       composer_email = product.composer_tag.andand.composer_email_if_contacted
       if comment.is_competition?
         subject = "Comment received from competition."
       else
         subject = "Thanks for song comment."
       end
       content = new_hash.select{|k, v| v.present? && k != :id && k != :is_competition && v.to_s != "-1" }.map{|k, v| "#{k}: #{v}\n"}.join + ' http://freeldssheetmusic.org/s/' + product.code
       unless composer_email.present?
         subject += " Please forward!" unless composer_email.present?
         content += "\n" + (product.composer_generic_contact_url).to_s
       end
       OrdersMailer.deliver_inquiry(subject, content, Preference.get_value('mail_username'), composer_email
      )
     end
     if is_competition
       product.clear_my_cache # so it can be noted as 5 star now :)
     else
       # don't want to slow down the site...
     end
   end
   [product, comment]
  end

 def product_matches p, parent_tag_groups
  # it must match one member of each group
  for tag_ids in parent_tag_groups.values
    return false if (tag_ids - p.tag_ids).length == tag_ids.length # no intersection? you're done
  end
  true
 end

 def redirect_to_original_url
   redirect_to_original_url_helper false
 end

 def redirect_to_original_url_v # v meaning "with view" :P
   redirect_to_original_url_helper true
 end

 private
 def redirect_to_original_url_helper inc_view
   product = Product.find_by_code(params[:id])
   if !product
     flash[:notice] = 'unexpected redirect not found this should never happen'
     render(:file => "#{RAILS_ROOT}/public/404.html", :status => 404) and return
   end
   if not_a_bot
     # this sometimes feels like it takes forever so...attempt to background it :|
     Thread.new {
       # avoid all after_save procs ...
       Product.increment_counter(:redirect_count, product.id)
       if inc_view
         Product.increment_counter(:view_count, product.id)
       end
     }
   end
   redirect_to product.original_url # not permanent redirect code...not sure which is right...
 end 

 private
 def redirect_to_tag name
   redirect_to '/' + name.gsub(' ', '_').gsub('/', '%2F'), :status => :moved_permanently # show_by_tags?
   true
 end

 def render_404_to_home string  # redirect them...
    flash[:notice] = "Sorry, we couldn't find what you were looking for, we've been under a bit of construction so please search again! " + string
    redirect_to :action => :search, :q => string.gsub('-', ' '), :status => 303 and return true # 303 is not found redirect 301 is moved permanently. this one...is messed up :) once had 404 here...which is an awful user experience...300 is multiple choices, didn't work, 303 is also "see other"?
 end

 public 
 def show
    id = params[:id]
    if !id.present?
      render(:file => "#{RAILS_ROOT}/public/404.html", :status => 404) and return
    end

    @product = Product.find_by_code(id, :include => [:downloads, {:tags => [:parent]}]) # no cacheing yet on the show page...
    # nb that we can't include :images because it comes in unsorted...Rails!!!

    if !@product
      options = [id.gsub(/[-]+/, '-'), id.gsub('_', ' '), id.gsub(/-competition$/, '')]
      for option in options
        if Product.find_by_code(option)
          redirect_to :action => 'show', :id => option, :status => :moved_permanently
          return false
        end
      end
      render_404_to_home(id) && return
    end
    look_for_recent_comment @product.id # for competition...

    if @product.code != id
      # mis capitalized
      redirect_to :action => 'show', :id => @product.code, :status => :moved_permanently
      return
    end
    if not_a_bot
      # avoid after_save blocks ...
      Product.increment_counter(:view_count, @product.id)
    end
    if @product.composer_tag && @product.voicing_tags[0]
       @title = "#{@product.name} (by #{@product.composer_tag.name} -- #{@product.voicing_tags.map{|t| t.name}.join(', ')})"
    else
       @title = @product.name
    end
    @images = @product.images

    @already_bookmarked = session_object.wishlist_items.map{|wl| wl.item}.include? @product

    render :layout => 'main_no_box'
  end

  def advanced_search
    # place holder...
  end

  def advanced_search_post
   tags = params[:product][:tag_ids].map{|id| Tag.find(id)}
   parent_tag_groups = {}
   for tag in tags
    if tag.parent
      parent_id = tag.parent.id
      child_id = tag.id
    else
      # allow for parent tags, too
      parent_id = child_id = tag.id
    end
     parent_tag_groups[parent_id] ||= []
     parent_tag_groups[parent_id] << child_id
   end

   all_products = Product.find(:all, :conditions => Product::CONDITIONS_AVAILABLE) # LODO sql for all the above :)
  
   @products = all_products.select{|p|
     product_matches(p, parent_tag_groups)
   }
  
   @do_not_paginate = true # XXXX enable paginate
   @title = 'Advanced search:' + tags.map{|t| t.name}.join(' and ') + " #{@products.count} songs"
   render :action => 'index.rhtml'
 end

  def filter_by_current_main_tag these_products
    @all_products_unfiltered = these_products
    if these_products.length > 1
      @was_filtered_able = true
      old_id = session['filter_all_tag_id']
      if old_id.present?
        @old_global_filter = old_id.to_i 
        these_products = these_products.select{|p| p.tag_ids.include? @old_global_filter }
        if @title
           @title += " (#{@all_products_unfiltered.size} arrangements limited to only #{Tag.find(old_id).name} [#{these_products.length}])"
        end
      end
    end
    these_products
  end 

  def change_global_filter
   id = params['id']
   session['filter_all_tag_id'] = id
   if id.present?
     flash[:notice] = "Ok, results (and future results) now filtered/limited to just #{Tag.find(id).name}"
   else
     flash[:notice] = "Ok, showing *all* results now (unfiltered--and also for future results)"
   end
   render :text => "alert('xyz');" # does nothing [?!]
  end

  def render_home # def home
    not_a_bot # for logging purposes :)
    # I think we could just put this into the routing itself, and not have to do the render component junk...sigh...
    @content_node = ContentNode.find_by_name('home')
    recent_products = Product.find(:all, :order => 'date_available DESC', :conditions => Product::CONDITIONS_AVAILABLE, :limit => 25)
    @recent_products = recent_products [0..3] # 4 == one line worth
    rand_products = Product.find(:all, :order => 'RAND()', :conditions => Product::CONDITIONS_AVAILABLE, :limit => 3)
    @rand_products = rand_products + recent_products[4..-1].shuffle[0..0] # add some random newer ones in there too :)

    render :action => :home
  end

#  def reset
#    expire_page :action => :show_by_tags   
#    render :text => "ok reset 'em"
#  end

  #caches_page :show_by_tags, :index
  def render_cached_if_exists cache_name
    cache_name = cache_name.gsub('/', '_') # disallowed unix filenames :)
    if today_is_sunday?
      cache_name = cache_name + '_sunday'
    end
    filename = RAILS_ROOT+"/public/cache/#{cache_name}.html"
    if File.file? filename
     logger.info "rendering early cache #{cache_name}..."
     render :text => File.read(filename) and return true
     #send_file(filename) # needs more settings...
     #return true
    else
     logger.info "early cache doesn't exist #{cache_name}..."
    end
    false
  end

  def render_and_cache rhtml_name, cache_name
    cache_name = cache_name.gsub('/', '_') # disallowed unix filenames :)
    if today_is_sunday?
      cache_name = cache_name + '_sunday'
    end
    text = render_to_string rhtml_name
    cache_dir = RAILS_ROOT + "/public/cache"
    if !flash[:notice].present?
      File.write("#{cache_dir}/#{cache_name}.html", text) # :|
    end
    render :text => text 
  end

  # Shows products by tag or tags.
  # Tags are passed in as id #'s separated by commas. or were once upon a time snort snort
  def show_by_tags
    # Tags are passed in as an array.
    # Passed into this controller like this [except we only use at most one]...:
    # /tag_one/tag_two/tag_three/...
    start_time = Time.now
    not_a_bot # for logging purposes :P
    tag_names = params[:tags] || []
    if tag_names.length > 1
      # passenger or nginx bug, Primary%2FYouth gets translated to Primary/Youth and come in as separate tags to us at this point :|
      tag_names = [tag_names.join('/')]
    end
    
    if tag_names.length != 1 # also occurs for any url with a '.' in it? huh? basically this is a catch all for...any poor url now?
      render_404_to_home(tag_names.join(' ')) && return
    end
    tag_name = tag_names[0]

    if !session['filter_all_tag_id'].present? && !flash[:notice].present?
      return if render_cached_if_exists(tag_name)
    else
      if session['filter_all_tag_id'].present? 
        logger.info "not rendering cached because of filter"
      else
        logger.info "not rendering cached because of flash"
      end
    end

    # Generate tag ID list from names passed in

    if tag_name =~ / / # a convenience name typed in manually
      redirect_to_tag(tag_name) and return
    end
    real_name = tag_name.gsub('_', ' ') # allow for cleaner google links coming in...which were the ones we created :)
    temp_tag = Tag.find_by_name(real_name) 
    if !temp_tag
      @to_search = real_name
      render(:file => "#{RAILS_ROOT}/public/404_search.html", :status => 404) and return
    end
    if temp_tag.name != real_name # redirect on capitalization fail :)
      redirect_to_tag(temp_tag.name) and return
    end  

    @viewing_tags = [temp_tag]

    # Paginate products here so we don't have a ton of ugly SQL
    # and conditions in the controller
    # 
    # lacking #tag_ids for now [non eager load] but that might actually be ok...
    logger.info "prelude took #{Time.now - start_time}s" # 0.001s LOL
    start_time = Time.now
    all_products = Product.find_by_tag_id(temp_tag.id, "items.name ASC")
    logger.info "find_by_tag took #{Time.now - start_time}s" # 0.4s
    start_time = Time.now
    if !temp_tag.is_composer_tag?
      all_products = randomize_but_keep_titles_together(all_products)
    else
      # all_products.sort_by{|p| p.name} # already sorted by items.name in SQL, above, so don't need to
    end

    original_size = all_products.size
    if original_size > 0
      if temp_tag.is_topic_tag?
        @title = "#{temp_tag.name} sheet music (#{original_size} Free Arrangements)" # SEO targeting :|
      else # arrangement...
        @title = "#{temp_tag.name} (#{original_size} Free Arrangements)"
      end
    else
      # don't say Topics (0 free arrangements) LOL
      @title = temp_tag.name
    end
    @products = paginate_and_filter(all_products)

    if temp_tag.bio
      @display_bio = @viewing_tags[0].bio
    end

    if temp_tag.get_composer_contact_url.present?
      @composer_tag = @viewing_tags[0]
    end
    logger.info("step 2 took #{Time.now - start_time}s [this one starts slow then warms up]")
    start_time = Time.now

    setup_alpha_tag_sizes
    if !session['filter_all_tag_id'].present?
      render_and_cache('index.rhtml', tag_name)
    else
      render 'index.rhtml' # render every time if special list...though we could cache it too uh guess...
    end
   logger.info("step 3 took #{Time.now - start_time}s") # 1.6s

  end

  @@product_id_to_alpha_tags = {}
  def get_product_alpha_tag_ids product, parents
    @@product_id_to_alpha_tags[product.id] ||= parents.select{|t| product.tag_ids.include?(t.id)}.map &:id
  end

  def setup_alpha_tag_sizes
    @alpha_tag_to_product_ids = []
    alphas = Tag.find_ordered_parents
    alphas.map{ |alpha|
      ids_for_this_tag = []
      @products.each{ |product|
        product_alpha_tags = get_product_alpha_tag_ids(product, alphas)
        if product_alpha_tags.include?(alpha.id) # is there some cleverer way to do this?
          ids_for_this_tag << product.id
        end
      }
      @alpha_tag_to_product_ids << [alpha, ids_for_this_tag]
    }
  end

  def only_on_this_site # deprecated, i.e. unused I believe these days...
    @products = Tag.find_all_by_only_on_this_site(true).map{|t| t.products}.flatten 
    def @products.total_pages # fake it out :P
      1
    end
    render 'index.rhtml'
  end

  @@product_id_to_hymn_tag_name = {}

  def rand_for_product title_rands, product
    if !@@product_id_to_hymn_tag_name[product.id]
      # cache miss, lookup hymn_tags [and tags at all :| ]
      if product.hymn_tags.length > 0
        title_for_rand = product.hymn_tags.sort_by{|t| t.name}.first.name # all this work to avoid having to lookup tags often :|
      else
        title_for_rand = product.name # anything will do, an original presumably :|
      end
      @@product_id_to_hymn_tag_name[product.id] = title_for_rand
    end
    title_rands[@@product_id_to_hymn_tag_name[product.id]] ||= rand
  end

  def randomize_but_keep_titles_together all_products
    title_rands = {} # keep them organized by title.
    # keep them random within title though :P
    srand(session_id.consistent_hash) # dunno how else to do this :(
    all_products.sort_by!{ rand }
    all_products.sort_by!{ |p| 
      rand_for_product(title_rands, p) # this will also use our srand so be consistent
    }
  end
  
  # Downloads a file using the original way
  # this way forces an "out of browser" download which is good...
  def download_file
    download_helper 'attachment'
  end

  # inline is both mp3 and pdf's...
  def inline_download_file
    download_helper 'inline'
  end

  def ambiguous_download
    download_helper 'inline', false
  end

  def not_a_bot
    ua = request.headers['User-Agent']
    al = request.headers['Accept-Language']
    not_bot = al.present?

    not_bot = true if ua =~ /MSIE \d.\d|Mac |Apple|translate.google.com|Gecko|player|Windows NT/i # players and browser players, etc.
    not_bot = true if ua =~ /^Mozilla\/\d/ # [Mozilla/5.0] [] huh? maybe their default player? # This kind of kills our whole system though...
    not_bot = true if ua =~ /stagefright/ # android player
    # but it's fun to try and perfect :P
    # slightly prefer to undercount uh guess
    not_bot = false if ua =~ /http/i # like http://siteexplorer.info
    not_bot = false if ua =~ /@/i # like mail@emoz.com
    not_bot = false if ua =~ /httrack/i # scraper?
    not_bot = false if ua =~ /SiteExplorer/i
    not_bot = false if ua =~ /yahoo.*slurp/i
    not_bot = false if ua =~ /spider/i # baiduspider
    not_bot = false if ua =~ /bot[^a-z]/i # robot, bingbot (otherwise can't get the Mozilla with bingbot, above), various others calling themselves 'bot'
    not_bot = false if ua =~ /bots[^a-z]/i # ...yandex/bots)
    not_bot = false if ua =~ /robot/i #  http://help.naver.com/robots/ Yeti
    not_bot = false if ua =~ /crawler/i # alexa crawler etc.
    not_bot = false if ua =~ /webfilter/ # genio crawler
    not_bot = false if ua =~ /walker/i # webwalker
    not_bot = false if ua =~ /nutch/i # aghaven/nutch crawler
    not_bot = false if ua =~ /Chilkat/ # might be a crawler...prolly http://www.forumpostersunion.com/showthread.php?t=4895
    not_bot = false if ua =~ /search.goo.ne.jp/ # ichiro
    not_bot = false if ua =~ /Preview/ # BingPreview Google Web Preview I don't think those are humans...

    if not_bot
      prefix= "not bot:"
    else
      prefix= "yes bot:"
    end
    logger.info "#{prefix} [#{ua}] [#{al}]" unless ua =~ /Wget/
    if logged_in_admin_user?
      logger.info "logged in user, fingindo ser bot para nao adjustar numeros"
      return false
    end

    not_bot
  end

  def logged_in_admin_user?
    session[:user] 
  end

  def download_helper disposition, add_count = true # this can get down to 7ms
    file = Download.find(params[:download_id])
    if file && File.exist?(filename = file.full_filename)
      if add_count && not_a_bot
       # unfortunately I think mp3's get downloaded via browser sometimes (via qt) on page view
       # so I guess this'll be half and half still...
       file.update_attribute(:count, file.count + 1) # waaay faster than file.save gah, could use update_attributes here?
      end
      args = {:disposition => disposition}
      # allow for mp3 style download to not be type pdf
      # LODO this doesn't actually inline anything else besides pdf...but at least it wurx
      if filename =~ /\.pdf$/
        args[:type] = 'application/pdf'
      elsif filename =~ /\.(mid|midi|mp3|wav)/
        args[:type] = "audio/#{$1}"
      else
        logger.info "whoa unknown type from filename? #{filename}" 
      end
      args[:filename] = File.basename(filename)
      send_file(filename, args)
    else
      render(:file => "#{RAILS_ROOT}/public/404.html", :status => 404) and return
    end
  end

  def current_process_count_including_us
    count_including_us = `ps -ef | egrep ruby | wc -l`.to_i-2
  end

  def all_no_cache
    render :text => 'ok'
    # @no_individ_cache = true # LODO totally remove this junk... 
    # index # reads them all
  end

  # Our "all songs" list
  def index
    return if render_cached_if_exists('all_songs')
    @display_bio = "Choose a different category from the list on the left for a more precise list."
    respond_to do |format|
      format.html do
        @tags = Tag.find_alpha
        @viewing_tags = nil # paginate_and_filter
        @products = Product.find(:all,
          :order => 'name ASC',
          :conditions => Product::CONDITIONS_AVAILABLE
        )
        @title = "All Songs (alphabetic order) #{@products.size} total"
        def @products.total_pages # fake it out :P
          1
        end
        render_and_cache('index.rhtml', 'all_songs') and return
      end
      format.rss do
        render(:file => "#{RAILS_ROOT}/public/404.html", :status => 404) and return # no rss for now--facebook maybe requested this once? so 404 instead of clogging our logs with 500's
      end
    end
  end 

  #def popular_songs # songs_stats is straight rhtml...
  #end

  def most_recently_added
    @title = 'Recently added 100 songs'
    recent = Product.find(:all,
      :order => 'date_available DESC',
      :conditions => Product::CONDITIONS_AVAILABLE,
      :limit => 100
    )
    @products = paginate_and_filter(recent, 100)
    render :action => 'index.rhtml' and return
  end

  def look_for_exact_matching_tags search_term
    exact_match = Tag.find(:all, :conditions => ["REPLACE(REPLACE(tags.name , '\\'', ''), ',', '') = ?", search_term]) # already case insensitive
    if exact_match.size  == 1
      # this causes a subsequent cache miss, so don't do it: flash[:notice] = "Displaying the #{exact_match[0].name} category"
      redirect_to_tag(exact_match[0].name)
      true
    elsif exact_match.size > 1
      # prolly never get here...legacy code really...?
      @tags = exact_match
      render :action => 'search_found_tags.rhtml'
      true
    else
      false
    end
  end
  
  def composer_all_song_stats
    @composer = Tag.find_by_id(params[:id])
  end

  @@song_mutex = Mutex.new

  def all_songs_with_strings
    @@cached_all_songs ||= all_songs_with_strings_non_memoized() # init, kind of OK if multiple simultaneously :|
    if @@song_mutex.locked?
      return @@cached_all_songs # don't queue up...kind of :)
    end
    Thread.new {
      @@song_mutex.synchronize {
        #@@cached_all_songs = all_songs_with_strings_non_memoized() # refresh :) shouldn't need to since saving a product actually restart the whole durn app LOL
      }
    }
    @@cached_all_songs # unrefreshed version :)
  end

  def all_songs_with_strings_non_memoized
    all_songs_with_tags = Product.find(:all, :include => :tags, :conditions => Product::CONDITIONS_AVAILABLE, :order => session_rand)
    all_songs_with_tags.map{ |p| 
       all_tags =  p.tags.map{|t| t.name + " " + t.bio.to_s}.join(" ")
       big_string = (p.name.to_s + " " + p.description.to_s + " " + p.lyrics.to_s + " " + all_tags).downcase.split # split so mary doesn't match primary though some of this still occurs in the SQL query within description...
       [p, big_string]
    }
  end

  def search
    search_term = params[:q]
    unless search_term.present?
#      flash[:notice] = "please enter a search query at all!" # NB this doesn't get displayed right since it's a cache...LODO fix
      redirect_to :action => 'index' and return false
    end

    if !not_a_bot
      # yes bot :)
      if params[:page].present? && params[:page].to_i > 1
         logger.info "rejecting bot with long search query!"
         redirect_to :action => 'index' and return false # why do bots do this to me with ancient search links?
      end
    end

    start = Time.now
    original_search_term = search_term
    session[:last_search] = original_search_term # try to save it away, in case of direct tag found, though this is ignored for cached pages..

    # work for I'll go, and ros' [?] also strip random punct.
    @search_term = original_search_term.downcase.gsub(/[.,'"] /, " ").gsub(/[.,'"]/, "").gsub(/sheet|music/, '').strip # ignore still, still, still, etc. in case they get punct wrong, we expect no punct. anyway, but XXX test with hymn names with punct for exact match

    if look_for_exact_matching_tags @search_term
      return
    end

    if @search_term =~ /piano/
      flash[:notice] = "Warning, you have the word piano in your search, however, most songs in our database have piano accompaniment, so we don't even mention it in our indexes, so you may want to consider removing that word from your search, as it will skew results to things like piano instrumentals, etc."
    end
    if @search_term =~ /ob+l+ig+at+o/ && @search_term !~ /obbligato/
      flash[:notice] = "Warning, you may want to search for obbligato instead"
    end

    name_without_punct="REPLACE(REPLACE(items.name, '\\'', ''), ',', '')"
    # let's or lets => let (apostrophe and after are removed, end s's are removed, like for mothers day)
    # oh => o
    # duets => duet
    # and => ''
    # your => you (they might have wanted you're...) so query you matches you're since the ' is replaced out...
    words_to_search_for = @search_term.split.map{|word| first_part=word.split("'")[0]}.map{|word| word == 'oh' ? 'o' : word}.map{|word| word.sub(/s$/, '')}
    words_to_search_for.reject!{|name| name.in? ['with', 'and', 'or', 'the', 'a', 'by', 'for'] || name.length < 2}
    words_to_search_for.map!{|name| name.gsub(/[^a-z0-9]/, '')}

    super_search_terms = words_to_search_for.map{|name| ["%#{name}%"]*3}.flatten

    # basically, given I will go, also pass back any piece that contains "i" and "will" and "go" somewhere in it, just in case for flipped words...
    super_search_query = (["(#{name_without_punct} like ? or tags.name like ? or items.description like ?)"]*(super_search_terms.length/3)).join(" and ")

    conds = [
        "(items.name LIKE ? OR code = ? OR (#{super_search_query})) AND #{Product::CONDITIONS_AVAILABLE}", 
        "%#{@search_term}%", @search_term # name, code
    ] + super_search_terms

    # need to include tags so that the query can work...
    products = Product.find(:all, :include => :tags,
      :conditions => conds,
      :order => session_rand
    )

    # allow searches like "christmas duet" to work...unclear how to do this in sql...

    with_all_words_somewhere = all_songs_with_strings().select{ |p, big_string| 
       words_to_search_for.all?{|word| big_string.contain? word}
    }.map{ |p, big_string| p}

    # search for all products of (basically) precise matching tags, too
    # this might be redundant to the above these days...
    tags = Tag.find(:all,
      :include => :products,
      :order => session_rand,
      :conditions => [ "(tags.name LIKE ?) AND #{Product::CONDITIONS_AVAILABLE}", "%#{@search_term}%"]
    )
    from_tags = tags.map{|t| t.products.map(&:id)}.flatten

    # put more precise hits first...
    good_hits = Product.find(:all, 
       :conditions => ["#{name_without_punct} like ? AND #{Product::CONDITIONS_AVAILABLE}",  "%#{@search_term}%"], 
       :order => session_rand
    )
    start_with_hits = Product.find(:all, 
       :conditions => ["#{name_without_punct} like ? AND #{Product::CONDITIONS_AVAILABLE}",  "#{@search_term}%"], 
       :order => session_rand
    )
    # logger.info "start with was " +  ["#{name_without_punct} like ? AND #{Product::CONDITIONS_AVAILABLE}",  "#{@search_term}%"].inspect

    all_ids_merged = (start_with_hits.map(&:id) + good_hits.map(&:id) + products.map(&:id) + from_tags + with_all_words_somewhere.map(&:id)).uniq

    # re map to product objects...
    all_products = all_ids_merged.map{|id| Product.find(id) }
    Rails.logger.info "search #{@search_term} returned #{all_products.length} results in #{Time.now - start}s"

    if not_a_bot
      per_page = 50 # make "bad" (too large) queries return somewhat quickly, at least until we have better cacheing figured out... 
    else
      per_page = 5000 # just get it over with for search engines...else they'll requery this 20 times to get all the pages...
    end
    @products = paginate_and_filter all_products, per_page
    Rails.logger.info "using per_page=#{per_page} and showing #{@products.size}"
    setup_alpha_tag_sizes

    # If only one product comes back, take em directly to it.
    if all_ids_merged.size == 1 && @products.length > 0
      # only redirect if one query matches, not if their filter gets it down to just 1 possible, since we don't list filters at all on the show page
      flash[:notice] = 'Found (showing) one song that matches: ' + @search_term
      redirect_to :action => 'show', :id => @products[0].code and return
    else
      @title = "Search Results for: #{original_search_term} (#{all_products.size} songs)"
      render :action => 'index.rhtml'
    end
  end

#  def search_and_paginate_and_filter terms
#    products = Product.find terms
#    paginate_and_filter(products)
#  end

  def paginate_and_filter products, per_page = @@per_page
    # filter first
    products = filter_by_current_main_tag products
    # Paginate products so we don't have a ton of ugly SQL
    # and conditions in the controller
    list = products
    pager = Paginator.new(list, list.size, per_page, params[:page])
    returning WillPaginate::Collection.new(params[:page] || 1, per_page, list.size) do |p|
      p.replace list[pager.current.offset, pager.items_per_page]
    end
  end

end
