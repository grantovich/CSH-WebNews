class PostsController < ApplicationController
  before_filter :get_newsgroup
  before_filter :get_post, :except => [:search, :search_entry, :create]
  before_filter :get_newsgroups_for_search, :only => :search_entry
  before_filter :get_newsgroups_for_posting, :only => :new
  before_filter :set_list_layout_and_offset, :only => [:index, :search]
  before_filter :set_limit_from_params, :only => [:index, :search]

  def index
    @not_found = true if params[:not_found]
    @flat_mode = true if @current_user.thread_mode == :flat
    
    if @post
      thread_selected = @post
      thread_selected = @post.thread_parent if not @flat_mode
      @from_older = (params[:include_older] or not @api_access) ? thread_selected.date : nil
      @from_newer = (params[:include_newer] or not @api_access) ? thread_selected.date : nil
    end
    
    if not @limit
      @limit = (@from_older and @from_newer) ? INDEX_DEF_LIMIT_2 : INDEX_DEF_LIMIT_1
      @limit *= 2 if @flat_mode
    end
    
    @limit += 1
    
    if not (@from_older or @from_newer or thread_selected)
      @from_older = Post.order('date').last.date + 1.second
    end
    
    if @from_older
      date_condition = (params[:older_inclusive] ? 'date <= ?' : 'date < ?')
      if @flat_mode
        @posts_older = @newsgroup.posts.where(date_condition, @from_older).order('date DESC').limit(@limit)
      else
        @posts_older = @newsgroup.posts.
          where("parent_id = ? and #{date_condition}", '', @from_older).
          order('date DESC').limit(@limit)
      end
    end
    
    if @from_newer
      date_condition = (params[:newer_inclusive] ? 'date >= ?' : 'date > ?')
      if @flat_mode
        @posts_newer = @newsgroup.posts.where(date_condition, @from_newer).order('date').limit(@limit).reverse
      else
        @from_newer = @newsgroup.posts.where(:date => @from_newer).first.thread_parent.date
        @posts_newer = @newsgroup.posts.
          where("parent_id = ? and #{date_condition}", '', @from_newer).
          order('date').limit(@limit).reverse
      end
    end
    
    if @posts_older
      @more_older = @posts_older.length > 0 && !@posts_older[@limit - 1].nil?
      @posts_older.delete_at(-1) if @posts_older.length == @limit
    end
    if @posts_newer
      @more_newer = @posts_newer.length > 0 && !@posts_newer[@limit - 1].nil?
      @posts_newer.delete_at(-1) if @posts_newer.length == @limit
    end
    
    if not @flat_mode
      flatten = (@current_user.thread_mode == :hybrid)
      @posts_selected = thread_selected.thread_tree_for_user(@current_user, flatten, @api_access) if thread_selected
      [@posts_older, @posts_newer].each do |posts|
        posts.map!{ |post| post.thread_tree_for_user(@current_user, flatten, @api_access) } if posts
      end
    else
      @posts_selected = {:post => thread_selected} if thread_selected
      [@posts_older, @posts_newer].each do |posts|
        posts.map!{ |post| {:post => post} } if posts
      end
    end
    
    get_next_unread_post
    
    respond_to do |wants|
      wants.js do
        # js template
      end
      wants.json do
        json = {}
        json.merge!(:posts_selected => @posts_selected) if @posts_selected
        json.merge!(:posts_older => @posts_older, :more_older => @more_older) if @posts_older
        json.merge!(:posts_newer => @posts_newer, :more_newer => @more_newer) if @posts_newer
        render :json => json
      end
    end
  end
  
  def search
    if @api_rss
      @limit = INDEX_RSS_LIMIT if not @limit
    else
      @limit = INDEX_DEF_LIMIT_1 * 2 if not @limit
      @limit += 1
    end
    
    conditions, values, error = build_search_conditions
    
    if @from_older and not @api_rss
      conditions << 'date < ?'
      values << @from_older
    end
    if not @newsgroup
      conditions << 'newsgroup not like ?'
      values << 'control%'
    end
    if params[:unread] and params[:personal_class]
      min_level = PERSONAL_CODES[params[:personal_class].to_sym]
      if min_level
        conditions << 'unread_post_entries.personal_level >= ?'
        values << min_level
      else
        generic_error :bad_request, 'personal_class_invalid',
          "'#{params[:personal_class]}' is not a valid personal class" and return
      end
    end
    
    @search_params = params.except(:api_key, :api_agent,
      :format, :action, :controller, :source, :commit, :validate, :utf8, :_)
    
    if error
      generic_error(:bad_request, error[0], error[1]) and return
    elsif params[:validate]
      render :partial => 'search_redirect' and return
    end
    
    @search_mode = @flat_mode = true
    if @search_params.include?(:starred) and @search_params.reject{ |k,v| v.blank? }.length == 1
      @starred_only = true
    end
    
    scope = Post.scoped
    scope = scope.sticky if params[:sticky]
    scope = scope.starred_by_user(@current_user) if params[:starred]
    scope = scope.unread_for_user(@current_user) if params[:unread]
    scope = scope.where(:newsgroup => @newsgroup.name) if @newsgroup
    @posts_older = scope.where(conditions.join(' and '), *values).order('date DESC').limit(@limit)
    if not @api_rss
      @more_older = @posts_older.length > 0 && !@posts_older[@limit - 1].nil?
      @posts_older.delete_at(-1) if @posts_older.length == @limit
    end
    @posts_older.map!{ |post| {:post => post} }
    
    get_next_unread_post
    
    respond_to do |wants|
      wants.js { render 'index' }
      wants.rss { render 'search' }
      wants.json { render :json => { :posts_older => @posts_older, :more_older => @more_older } }
    end
  end
  
  def search_entry
    render 'shared/dialog'
  end
  
  def next_unread
    get_next_unread_post
    if params[:mark_read]
      was_unread = @next_unread_post.mark_read_for_user(@current_user)
    end
    render :json => {
      :post => @next_unread_post.as_json(
        :with_user => @current_user, :with_all => true, :with_headers => params[:with_headers]
      )
    }.merge(params[:mark_read] ? { :was_unread => was_unread } : {})
  end
  
  def show
    respond_to do |wants|
      wants.js do
        @search_mode = (params[:search_mode] ? true : false)
        if @post
          @post_was_unread = @post.mark_read_for_user(@current_user)
          get_next_unread_post
          @admin_cancel = true if @current_user.is_admin? and not @post.authored_by?(@current_user)
        else
          @not_found = true
        end
      end
      
      wants.json do
        if params[:mark_read]
          was_unread = @post.mark_read_for_user(@current_user)
        end
        render :json => {
          :post => @post.as_json(
            :with_user => @current_user, :with_all => true, :with_headers => params[:with_headers]
          ).merge(params[:html_body] ? { :body => view_context.post_html_body(@post) } : {})
        }.merge(params[:mark_read] ? { :was_unread => was_unread } : {})
      end
    end
  end
  
  def new
    @new_post = Post.new(:newsgroup => @newsgroup)
    if @post
      @new_post.subject = 'Re: ' + @post.subject.sub(/^Re: ?/, '')
      @new_post.body = @post.quoted_body
    elsif @api_access
      generic_error :bad_request, 'number_missing',
        "This method requires a post, identified by 'newsgroup' and 'number' parameters" and return
    end
    respond_to do |wants|
      wants.js { render 'shared/dialog' }
      wants.json { render :json => { :new_post => { :subject => @new_post.subject, :body => @new_post.body } } }
    end
  end
  
  def create
    post_newsgroups = []
    @sync_error = nil
    body = params[:body] || params[:post].andand[:body]
    subject = params[:subject] || params[:post].andand[:subject]
  
    if subject.blank?
      generic_error :bad_request, 'subject_missing', "Posting requires a subject line" and return
    end
    
    if not @newsgroup
      generic_error :bad_request, 'newsgroup_missing', "Posting requires a newsgroup" and return
    elsif not @newsgroup.posting_allowed?
      generic_error :bad_request, 'newsgroup_locked',
        "Newsgroup '#{@newsgroup.name}' does not allow posting" and return
    end
    post_newsgroups << @newsgroup
    
    if not params[:crosspost_to].blank?
      crosspost_to = Newsgroup.find_by_name(params[:crosspost_to])
      if crosspost_to.nil?
        generic_error :not_found, 'newsgroup_not_found',
          "Cross-post newsgroup '#{params[:crosspost_to]}' does not exist" and return
      elsif not crosspost_to.posting_allowed?
        generic_error :forbidden, 'newsgroup_locked',
          "Cross-post newsgroup '#{crosspost_to.name}' does not allow posting" and return
      elsif crosspost_to == @newsgroup
        generic_error :bad_request, 'newsgroup_duplicated',
          "Cross-post newsgroup '#{crosspost_to.name}' is the same as the primary newsgroup" and return
      end
      post_newsgroups << crosspost_to
    end
    
    # TODO: Generalize the concept of "extra cross-post newsgroups" as a configuration option
    if params[:crosspost_sysadmin]
      n = Newsgroup.find_by_name('csh.lists.sysadmin')
      if post_newsgroups.include?(n)
        generic_error :bad_request, 'newsgroup_duplicated',
          "csh.lists.sysadmin is selected twice for cross-posting" and return
      end
      post_newsgroups << n
    end
    
    if params[:crosspost_alumni]
      n = Newsgroup.find_by_name('csh.lists.alumni')
      if post_newsgroups.include?(n)
        generic_error :bad_request, 'newsgroup_duplicated',
          "csh.lists.alumni is selected twice for cross-posting" and return
      end
      post_newsgroups << n
    end
    
    reply_newsgroup = reply_post = nil
    if params[:reply_newsgroup]
      reply_newsgroup = Newsgroup.find_by_name(params[:reply_newsgroup])
      reply_post = Post.where(:newsgroup => params[:reply_newsgroup], :number => params[:reply_number]).first
      if reply_post.nil?
        generic_error :not_found, 'post_not_found', "Can't reply to nonexistent post number '#{params[:reply_number]}' in newsgroup '#{params[:reply_newsgroup]}'" and return
      end
    end
    
    post_string = Post.build_message(
      :user => @current_user,
      :newsgroups => post_newsgroups.map(&:name),
      :subject => subject,
      :body => body.to_s,
      :reply_post => reply_post,
      :api_agent => params[:api_agent]
    )
    
    new_message_id = nil
    begin
      Net::NNTP.start(NEWS_SERVER) do |nntp|
        new_message_id = nntp.post(post_string)[1][/<.*?>/]
      end
    rescue
      generic_error :internal_server_error, 'nntp_post_error', 'NNTP server error: ' + $!.message and return
    end
    
    begin
      Net::NNTP.start(NEWS_SERVER) do |nntp|
        post_newsgroups.each{ |n| Newsgroup.sync_group!(nntp, n.name, n.status) }
      end
      @new_post = @newsgroup.posts.find_by_message_id(new_message_id)
      if not @new_post
        @sync_error = "Your post was accepted by the news server, but it appears to have been held for moderation or silently discarded; contact the server administrators before attempting to post again"
      end
    rescue
      @sync_error = "Your post was accepted by the news server and does not need to be resubmitted, but an error occurred while resyncing the newsgroups: #{$!.message}"
    end
    
    respond_to do |wants|
      wants.js {}
      wants.json do
        if @sync_error
          json_error :internal_server_error, 'nntp_sync_error', @sync_error
        else
          render :json => { :post => @new_post.as_json(:minimal => true) }
        end
      end
    end
  end
  
  def destroy
    if @post.nil?
      # API case handled by get_post
      form_error "The post you are trying to cancel doesn't exist" and return
    end
    
    if not @post.newsgroup.posting_allowed?
      generic_error :bad_request, 'newsgroup_locked',
        "Posts in read-only newsgroups cannot be canceled" and return
    end
    
    if not @post.authored_by?(@current_user) and not @current_user.is_admin?
      generic_error :forbidden, 'requires_admin',
        "Admin privileges are required to cancel a post that you did not author" and return
    end
    
    if @post.children.count != 0
      generic_error :bad_request, 'post_has_replies', "Posts that have replies cannot be canceled" and return
    end
    
    if params[:confirm_cancel].blank?
      generic_error :bad_request, 'confirm_cancel_missing',
        "The 'confirm_cancel' parameter must be present when calling this method" and return
    end
    
    begin
      Net::NNTP.start(NEWS_SERVER) do |nntp|
        nntp.post(@post.build_cancel_message(@current_user, params[:reason]))
      end
    rescue
      generic_error :internal_server_error, 'nntp_post_error', 'NNTP server error: ' + $!.message and return
    end
    
    begin
      Net::NNTP.start(NEWS_SERVER) do |nntp|
        @post.all_newsgroups.each{ |n| Newsgroup.sync_group!(nntp, n.name, n.status) }
        Newsgroup.sync_group!(nntp, 'control.cancel', 'n')
      end
    rescue
      @sync_error = "Your cancel was accepted by the news server and does not need to be resubmitted, but an error occurred while resyncing the newsgroups: #{$!.message}"
    end
    
    respond_to do |wants|
      wants.js {}
      wants.json do
        if @sync_error
          json_error :internal_server_error, 'nntp_sync_error', @sync_error
        else
          head :ok
        end
      end
    end
  end
  
  def destroy_confirm
    @admin_cancel = !@post.authored_by?(@current_user)
    render 'shared/dialog'
  end
  
  def mark_read
    if params[:mark_unread]
      if @post
        if not @post.unread_for_user?(@current_user)
          UnreadPostEntry.create!(
            :user => @current_user, :newsgroup => @post.newsgroup, :post => @post,
            :personal_level => PERSONAL_CODES[@post.personal_class_for_user(@current_user)],
            :user_created => true
          )
        else
          @current_user.unread_post_entries.find_by_post_id(@post).update_attributes!(:user_created => true)
        end
      else
        generic_error :bad_request, 'number_missing',
          "mark_unread can only be used with a single post, identified by 'newsgroup' and 'number' parameters"
        return
      end
    else
      if @post
        if params[:in_thread]
          @current_user.unread_post_entries.where(:post_id => Post.where(:thread_id => @post.thread_id)).destroy_all
        else
          @post.mark_read_for_user(@current_user)
        end
      elsif @newsgroup
        @current_user.unread_post_entries.where(:newsgroup_id => @newsgroup.id).destroy_all
      elsif params[:all_posts]
        @current_user.unread_post_entries.destroy_all
      else
        generic_error :bad_request, 'newsgroup_missing',
          "This method requires at least a 'newsgroup' parameter or an 'all_posts' parameter"
        return
      end
    end
    
    respond_to do |wants|
      wants.js { get_next_unread_post }
      wants.json { head :ok }
    end
  end
  
  def edit_sticky
    render 'shared/dialog'
  end
  
  def update_sticky
    if not @current_user.is_admin?
      generic_error :forbidden, 'requires_admin',
        "Admin privileges are required to sticky or unsticky posts" and return
    end
    
    if @post.nil?
      # API case handled by get_post
      form_error "The post you are trying to sticky doesn't exist" and return
    elsif @post != @post.thread_parent
      generic_error :bad_request, 'post_not_stickable',
        "Only the initial post in a thread can be made sticky" and return
    end
    
    if params[:do_sticky] or (@api_access and not params[:unstick])
      if params[:sticky_until].blank?
        generic_error :bad_request, 'sticky_until_missing',
          "An expiration date is required to make a post sticky" and return
      end
      t = Chronic.parse(params[:sticky_until])
      if t.nil?
        generic_error :bad_request, 'sticky_until_invalid',
          "The expiration date '#{params[:sticky_until]}' could not be parsed" and return
      end
      sticky_until = t - t.sec - ((((t.min + 15) % 30) - 15) * 1.minute)
      if sticky_until <= Time.now
        generic_error :bad_request, 'sticky_until_unacceptable',
          "The expiration date must be in the future, when rounded to the nearest half-hour" and return
      end
      @post.in_all_newsgroups.each do |post|
        post.update_attributes(:sticky_user => @current_user, :sticky_until => sticky_until)
      end
    else
      if not @post.sticky_until.nil?
        @post.in_all_newsgroups.each do |post|
          post.update_attributes(:sticky_user => @current_user, :sticky_until => Time.now - 1.second)
        end
      end
    end
    
    respond_to do |wants|
      wants.js {}
      wants.json { head :ok }
    end
  end
  
  def update_star
    if @post.nil?
      # API case handled by get_post
      @star_error = "The post you are trying to star/unstar doesn't exist" and return
    end
    
    if @post.starred_by_user?(@current_user)
      @post.starred_post_entries.find_by_user_id(@current_user.id).destroy
      @starred = false
    else
      StarredPostEntry.create!(:user => @current_user, :post => @post)
      @starred = true
    end
    
    respond_to do |wants|
      wants.js {}
      wants.json { render :json => { :starred => @starred } }
    end
  end

  def update_plusone
    if @post.nil?
      @plusone_error = "The post you are trying to +1 doesn't exist" and return
    end

    unless @post.plusoned_by_user?(@current_user)
      PlusonePostEntry.create!(:user => @current_user, :post => @post)

      @plusoned = true

      post_string = Post.build_message(
        :user => @current_user,
        :newsgroups => [ @newsgroup.name ],
        :subject => @post.subject,
        :body => "+1",
        :reply_post => @post,
        :api_agent => params[:api_agent]
      )
      
      new_message_id = nil
      begin
        Net::NNTP.start(NEWS_SERVER) do |nntp|
          new_message_id = nntp.post(post_string)[1][/<.*?>/]
        end
      rescue
    puts $!.message
        generic_error :internal_server_error, 'nntp_post_error', 'NNTP server error: ' + $!.message and return
      end
      
      begin
        Net::NNTP.start(NEWS_SERVER) do |nntp|
          post_newsgroups.each{ |n| Newsgroup.sync_group!(nntp, n.name, n.status) }
        end
        @new_post = @newsgroup.posts.find_by_message_id(new_message_id)
        if not @new_post
          @sync_error = "Your post was accepted by the news server, but it appears to have been held for moderation or silently discarded; contact the server administrators before attempting to post again"
    puts @sync_error
        end
      rescue
        @sync_error = "Your post was accepted by the news server and does not need to be resubmitted, but an error occurred while resyncing the newsgroups: #{$!.message}"
    puts @sync_error
      end
    end

    puts new_message_id
    puts post_string
    puts @sync_error

    respond_to do |wants|
      wants.js {}
      wants.json { render :json => { :plusoned => @plusoned } }
    end
  end
  
  private
    
    def set_list_layout_and_offset
      if params[:from_older] or params[:from_newer]
        @full_layout = false
        begin
          @from_older = Time.parse(params[:from_older]) if params[:from_older]
        rescue
          generic_error :bad_request, 'datetime_invalid',
            "The from_older value '#{params[:from_older]}' could not be parsed as a datetime" and return
        end
        begin
          @from_newer = Time.parse(params[:from_newer]) if params[:from_newer]
        rescue
          generic_error :bad_request, 'datetime_invalid',
            "The from_newer value '#{params[:from_newer]}' could not be parsed as a datetime" and return
        end
      else
        @full_layout = true
      end
    end
    
    def set_limit_from_params
      if params[:limit]
        begin
          @limit = Integer(params[:limit])
          max_limit = @api_rss ? INDEX_RSS_LIMIT : INDEX_MAX_LIMIT
          if not @limit.between?(0, max_limit)
            generic_error :bad_request, 'limit_unacceptable',
              "The limit value '#{@limit}' is outside the acceptable range (0..#{max_limit})" and return
          end
        rescue
          generic_error :bad_request, 'limit_invalid',
            "The limit value '#{params[:limit]}' could not be parsed as an integer'" and return
        end
      end
    end
    
    def build_search_conditions
      conditions = []
      values = []
      error = nil
      
      if not params[:keywords].blank?
        begin
          phrases = Shellwords.split(params[:keywords])
          keyword_conditions = []
          keyword_values = []
          exclude_conditions = []
          exclude_values = []
          
          phrases.each do |phrase|
            if phrase[0] == '-'
              exclude_conditions << '('
              exclude_conditions[-1] += 'subject like ?'
              exclude_values << '%' + phrase[1..-1] + '%'
              if not params[:subject_only]
                exclude_conditions[-1] += ' or body like ?'
                exclude_values << '%' + phrase[1..-1] + '%'
              end
              exclude_conditions[-1] += ')'
            else
              keyword_conditions << '('
              keyword_conditions[-1] += 'subject like ?'
              keyword_values << '%' + phrase + '%'
              if not params[:subject_only]
                keyword_conditions[-1] += ' or body like ?'
                keyword_values << '%' + phrase + '%'
              end
              keyword_conditions[-1] += ')'
            end
          end
          
          conditions << '(' + 
            '(' + keyword_conditions.join(' and ') + ')' + (
              exclude_conditions.empty? ?
                '' : ' and not (' + exclude_conditions.join(' or ') + ')'
            ) + ')'
          values += keyword_values + exclude_values
        rescue
          error = ['keywords_invalid', 'The keywords string contains an unbalanced quote']
        end
      end
      
      if not params[:authors].blank?
        authors = params[:authors].split(',').map(&:strip)
        conditions << '(' + (['author like ?'] * authors.size).join(' or ') + ')'
        authors.each do |author|
          values << '%' + author + '%'
        end
      end
      
      if not params[:date_from].blank?
        date_from = params[:date_from]
        date_from = 'January 1, ' + date_from if date_from[/^\d{4}$/]
        date_from = Chronic.parse(date_from)
        if not date_from
          error = ['date_from_invalid', "The start date '#{params[:date_from]}' could not be parsed"]
        else
          conditions << 'date >= ?'
          values << date_from
        end
      end
      if not params[:date_to].blank?
        date_to = params[:date_to]
        date_to = 'January 1, ' + (date_to.to_i + 1).to_s if date_to[/^\d{4}$/]
        date_to = Chronic.parse(date_to)
        if not date_to
          error = ['date_to_invalid', "The end date '#{params[:date_to]}' could not be parsed"]
        else
          conditions << 'date <= ?'
          values << date_to
        end
      end
      
      return conditions, values, error
    end
end
