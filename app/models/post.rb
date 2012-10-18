class Post < ActiveRecord::Base
  belongs_to :newsgroup, :foreign_key => :newsgroup, :primary_key => :name
  belongs_to :sticky_user, :class_name => 'User'
  has_many :unread_post_entries, :dependent => :destroy
  has_many :starred_post_entries, :dependent => :destroy
  has_many :plusone_post_entries, :dependent => :destroy
  has_many :unread_users, :through => :unread_post_entries, :source => :user
  has_many :starred_users, :through => :starred_post_entries, :source => :user
  has_many :plusone_users, :through => :plusone_post_entries, :source => :user
  before_destroy :kill_parent_id
  
  def as_json(options = {})
    if options[:minimal]
      json = { :number => number }
    else
      only = [:number, :subject, :date, :sticky_until]
      only += [:body] if options[:with_all]
      only += [:headers] if options[:with_headers]
      json = super(
        :only => only,
        :include => {:sticky_user => {:only => [:username, :real_name]}},
        :methods => [:author_name, :author_email]
      )
      if options[:with_all]
        json[:stripped] = stripped
        json[:parent] = original_parent ?
          original_parent.as_json(:minimal => true) :
          parent.as_json(:minimal => true)
        json[:thread_parent] = thread_parent.as_json(:minimal => true) if not thread_parent == self
        json[:reparented] = is_reparented? && !is_orphaned?
        json[:orphaned] = is_orphaned? && !original_parent
        json[:followup_to] = followup_newsgroup.name if followup_newsgroup
        json[:cross_posts] = (in_all_newsgroups - [self]).map{ |post| post.as_json(:minimal => true) }
        json[:plusone_by] = plusone_users
      end
    end
    
    json[:newsgroup] = newsgroup.name
    
    if options[:with_user]
      json.merge!(
        :starred => starred_by_user?(options[:with_user]),
        :unread_class => unread_class_for_user(options[:with_user]),
        :personal_class => personal_class_for_user(options[:with_user]),
        :plusoned => plusoned_by_user?(options[:with_user])
      )
    end
    
    return json
  end

  def plusoned
    plusone_users.count
  end

  def plusoned_by_user?(user)
    plusone_users.include?(user)
  end

  def plusone_users_names
    plusone_users.map do |user|
      user.real_name
    end
  end
  
  def author_name
    author[/(.*)<.*>/, 1].andand.gsub(/(\A|[^\\])"/, '\\1').andand.gsub('\\"', '"').andand.rstrip ||
      author[/.* \((.*)\)/, 1] || author
  end
  
  def author_email
    author[/.*<(.*)>/, 1] || author[/(.*) \(.*\)/, 1] || nil
  end
  
  def author_username
    author_email.split('@')[0] if author_email
  end
  
  def author_is_local?
    !author_email[LOCAL_EMAIL_DOMAIN].nil? if author_email
  end
  
  def first_line
    body.each_line do |line|
      if not (line.blank? or line[/^>/] or line[/(wrote|writes):$/] or
          line[/^In article/] or line[/^On.*\d{4}.*:/] or line[/wrote in message/] or
          line[/news:.*\.\.\.$/] or line[/^\W*snip\W*$/])
        first = line.sub(/ +$/, '')
        first = first.rstrip + '...' if first[/\w\n/]
        return first.rstrip
      end
    end
    return subject
  end
  
  def quoted_body
    author_name + " wrote:\n\n" + if body.blank?
      '>' + subject
    else
      sigless_body.split("\n").map{ |line| '>' + line }.join("\n")
    end + "\n\n"
  end
  
  def sigless_body
    return body.                               # Things to strip:
      sub(/(.*)\n-- \n.*/m, '\\1').            # '-- ' on its own line and all following text ("standard" sig)
      sub(/\n\n[-~].*[[:alpha:]].*\n*\z/, ''). # Non-blank final lines starting with [-~] and containing a letter
      rstrip
  end
  
  def self.sticky
    where('sticky_until is not null and sticky_until > ?', Time.now)
  end
  
  def is_sticky?
    !sticky_until.nil? and sticky_until > Time.now
  end
  
  def is_crossposted?(quick = false)
    if quick
      all_newsgroup_names.length > 1
    else
      in_all_newsgroups.length > 1
    end
  end
  
  def is_reparented?
    parent_id != original_parent_id
  end
  
  def is_orphaned?
    is_reparented? and parent_id == ''
  end
  
  def followup_newsgroup
    Newsgroup.find_by_name(headers[/^Followup-To: (.*)/i, 1])
  end
  
  def exists_in_followup_newsgroup?
    !in_newsgroup(followup_newsgroup).nil?
  end
  
  def all_newsgroups
    all_newsgroup_names.map{ |name| Newsgroup.find_by_name(name) }.reject(&:nil?)
  end
  
  def all_newsgroup_names
    headers[/^Newsgroups: (.*)/i, 1].split(',').map(&:strip)
  end
  
  def in_newsgroup(newsgroup)
    newsgroup.posts.find_by_message_id(message_id)
  end
  
  def in_all_newsgroups
    all_newsgroups.
      map{ |newsgroup| in_newsgroup(newsgroup) }.
      reject(&:nil?)
  end
  
  def parent
    parent_id == '' ? nil : Post.where(:hidden => false, :message_id => parent_id, :newsgroup => newsgroup.name).first
  end
  
  def children
    Post.where(:hidden => false, :parent_id => message_id, :newsgroup => newsgroup.name).order('date')
  end
  
  def thread_parent
    message_id == thread_id ? self : Post.where(:hidden => false, :message_id => thread_id, :newsgroup => newsgroup.name).first
  end
  
  def all_in_thread
    Post.where(:hidden => false, :thread_id => thread_id, :newsgroup => newsgroup.name).order('date')
  end
  
  def thread_tree_for_user(user, flatten = false, as_json = false, all_posts = nil)
    all_posts ||= all_in_thread.to_a
    {
      :post => (as_json ? self.as_json(:with_user => user) : self),
      :children => if flatten
        all_posts.reject{ |p| p == self }.map{ |p| {
          :post => (as_json ? p.as_json(:with_user => user) : p), :children => []
        }.merge(as_json ? {} : {
          :unread => p.unread_for_user?(user),
          :personal_class => p.personal_class_for_user(user)
        })}
      else
        all_posts.
          select{ |p| p.parent_id == self.message_id }.
          map{ |p| p.thread_tree_for_user(user, flatten, as_json, all_posts) }
      end
    }.merge(as_json ? {} : {
      :unread => self.unread_for_user?(user),
      :personal_class => self.personal_class_for_user(user)
    })
  end
  
  def original_parent_id
    headers[/^References: (.*)/i, 1].to_s.split.map{ |r| r[/<.*>/] }[-1] || ''
  end
  
  def original_parent
    Post.where(:message_id => original_parent_id).first
  end
  
  def authored_by?(user)
    author_name == user.real_name or author_email == user.email
  end
  
  def user_in_thread?(user)
    return true if authored_by?(user)
    return all_in_thread.reduce(false){ |m, post| m || post.authored_by?(user) }
  end
  
  def self.starred_by_user(user)
    joins(:starred_post_entries).where(:starred_post_entries => { :user_id => user.id })
  end
  
  def starred_by_user?(user)
    starred_users.include?(user)
  end
  
  def self.unread_for_user(user)
    joins(:unread_post_entries).where(:unread_post_entries => { :user_id => user.id })
  end
  
  def unread_for_user?(user)
    !unread_class_for_user(user).nil?
  end
  
  def unread_class_for_user(user)
    entry = user.unread_post_entries.find_by_post_id(self)
    if entry
      if entry.user_created
        :manual
      else
        :auto
      end
    else
      nil
    end
  end
  
  def mark_read_for_user(user)
    was_unread = false
    in_all_newsgroups.each do |post|
      entry = post.unread_post_entries.where(:user_id => user.id).first
      if entry
        entry.destroy
        was_unread = true
      end
    end
    return was_unread
  end
  
  def thread_unread_for_user?(user)
    return true if unread_for_user?(user)
    return all_in_thread.reduce(false){ |m, post| m || post.unread_for_user?(user) }
  end
  
  def personal_class_for_user(user, check_thread = true)
    case
      when authored_by?(user) then :mine
      when parent && parent.authored_by?(user) then :mine_reply
      when check_thread && thread_parent.user_in_thread?(user) then :mine_in_thread
    end
  end
  
  def thread_unread_class_for_user(user)
    PERSONAL_CLASSES[user.unread_posts.where(:thread_id => thread_id).maximum(:personal_level)]
  end
  
  def kill_parent_id
    # Sub-optimal, should re-parent to next reference up the chain
    # (but posts getting canceled when they already have replies is rare)
    Post.where(:parent_id => message_id).each do |post|
      post.update_attributes(:parent_id => '', :thread_id => post.message_id)
    end
  end
  
  def build_cancel_message(user, reason)
    m = "From: #{user.real_name} <#{user.email}>"
    m += "\nSubject: cmsg cancel #{message_id}"
    m += "\nNewsgroups: " + all_newsgroup_names.join(',')
    m += "\nControl: cancel #{message_id}"
    m += "\nContent-Type: text/plain; charset=utf-8; format=flowed"
    m += "\nUser-Agent: CSH-WebNews"
    
    m += "\n\nThe following message was canceled by #{user.real_name}:\n"
    [
      headers[/^From: .*/i],
      headers[/^Subject: .*/i],
      headers[/^Date: .*/i],
      headers[/^Newsgroups: .*/i],
      headers[/^Message-ID: .*/i]
    ].each do |header|
      m += "\n  #{header}"
    end
    
    if not reason.blank?
      m += "\n\n" + Post.flowed_encode('The reason given was: ' + reason)
    end
    
    return m
  end
  
  def self.build_message(p)
    p[:subject].encode!('US-ASCII', :invalid => :replace, :undef => :replace).gsub(/[\t\r\n\f]/, '')
    p[:api_agent].encode!('US-ASCII', :invalid => :replace, :undef => :replace).gsub(/[\t\r\n\f]/, '') rescue nil
    m = "From: #{p[:user].real_name} <#{p[:user].email}>"
    m += "\nSubject: #{p[:subject]}"
    m += "\nNewsgroups: #{p[:newsgroups].join(',')}"
    m += "\nFollowup-To: #{p[:newsgroups].first}" if p[:newsgroups].size > 1
    if p[:reply_post]
      existing_refs = p[:reply_post].headers[/^References: (.*)/i, 1]
      existing_refs ? existing_refs += ' ' : existing_refs = ''
      m += "\nReferences: #{existing_refs + p[:reply_post].message_id}"
    end
    m += "\nContent-Type: text/plain; charset=utf-8; format=flowed"
    if p[:api_agent]
      m += "\nUser-Agent: CSH-WebNews-API (#{p[:api_agent]})"
    else
      m += "\nUser-Agent: CSH-WebNews"
    end

    if p[:custom_headers]
      p[:custom_headers].keys.each do |header|
        m += "\nX-WebNews-#{header}: #{p[:custom_headers][header]}"
      end
    end
    
    m += "\n\n#{flowed_encode(p[:body].rstrip)}\n"
    return m
  end
  
  def self.import!(newsgroup, number, headers, body)
    stripped = false
    headers.gsub!(/\n( |\t)/, ' ')
    headers.encode!('US-ASCII', :invalid => :replace, :undef => :replace)
  
    part_headers, body = multipart_decode(headers, body)
    stripped = true if headers[/^Content-Type:.*mixed/i]
    
    body = body.unpack('m')[0] if part_headers[/^Content-Transfer-Encoding: base64/i]
    body = body.unpack('M')[0] if part_headers[/^Content-Transfer-Encoding: quoted-printable/i]
    
    if part_headers[/^Content-Type:.*(X-|unknown)/i]
      body.encode!('UTF-8', 'US-ASCII', :invalid => :replace, :undef => :replace)
    elsif part_headers[/^Content-Type:.*charset/i]
      begin
        body.encode!('UTF-8', part_headers[/^Content-Type:.*charset="?([^"]+?)"?(;|$)/i, 1],
          :invalid => :replace, :undef => :replace)
      rescue
        body.encode!('UTF-8', 'US-ASCII', :invalid => :replace, :undef => :replace)
      end
    else
      begin
        body.encode!('UTF-8', 'US-ASCII') # RFC 2045 Section 5.2
      rescue
        begin
          body.encode!('UTF-8', 'Windows-1252')
        rescue
          body.encode!('UTF-8', 'US-ASCII', :invalid => :replace, :undef => :replace)
        end
      end
    end
    
    if body[/^begin(-base64)? \d{3} /]
      body.gsub!(/^begin \d{3} .*?\nend\n/m, '')
      body.gsub!(/^begin-base64 \d{3} .*?\n====\n/m, '')
      stripped = true
    end
    
    body = flowed_decode(body) if part_headers[/^Content-Type:.*format="?flowed"?/i]
    
    body.rstrip!
    
    date = Time.parse(
      headers[/^Injection-Date: (.*)/i, 1] ||
      headers[/^NNTP-Posting-Date: (.*)/i, 1] ||
      headers[/^Date: (.*)/i, 1]
    )
    author = headers[/^From: (.*)/i, 1]
    subject = headers[/^Subject: (.*)/i, 1]
    message_id = headers[/^Message-ID: (.*)/i, 1]
    references = headers[/^References: (.*)/i, 1].to_s.split.map{ |r| r[/<.*>/] }
    
    parent_id = references[-1] || ''
    thread_id = message_id
    possible_thread_id = references[0] || ''
    parent = where(:message_id => parent_id, :newsgroup => newsgroup.name).first
    
    # Note: Doesn't try to fix replies ("Re:") that simply have no References at all
    if parent_id != '' and not parent
      if where(:message_id => parent_id).exists?
        parent_id = ''
      else
        if possible_thread_id != '' and
            where(:message_id => possible_thread_id, :newsgroup => newsgroup.name).exists?
          parent_id = thread_id = possible_thread_id
        else
          possible_thread_parent =
            where('subject = ? and newsgroup = ? and date < ?',
              subject.sub(/Re: /i, ''), newsgroup.name, date).order('date DESC').first ||
            where('subject = ? and newsgroup = ? and date < ?',
              subject, newsgroup.name, date).order('date').first
          
          if possible_thread_parent
            parent_id = thread_id = possible_thread_parent.message_id
          else
            parent_id = ''
          end
        end
      end
    elsif parent # Parent exists and is in the same newsgroup
      thread_id = parent.thread_id
    end

    hidden = false
    hidden = headers[/^X-WebNews-Hidden: (.*)/i, 1] == "True"
    
    create!(:newsgroup => newsgroup,
            :number => number,
            :subject => subject,
            :author => author,
            :date => date,
            :message_id => message_id,
            :parent_id => parent_id,
            :thread_id => thread_id,
            :stripped => stripped,
            :headers => headers,
            :body => body,
            :hidden => hidden)
  end
  
  # See RFC 3676 for "format=flowed" spec
  
  def self.flowed_decode(body)
    new_body_lines = []
    body.each_line do |line|
      line.chomp!
      quotes = line[/^>+/]
      line.sub!(/^>+/, '')
      line.sub!(/^ /, '')
      if line != '-- ' and
          new_body_lines.length > 0 and
          !new_body_lines[-1][/^-- $/] and
          new_body_lines[-1][/ $/] and
          quotes == new_body_lines[-1][/^>+/]
        new_body_lines[-1] << line
      else
        new_body_lines << quotes.to_s + line
      end
    end
    return new_body_lines.join("\n")
  end
  
  def self.flowed_encode(body)
    body.split("\n").map do |line|
      line.rstrip!
      quotes = ''
      if line[/^>/]
        quotes = line[/^([> ]*>)/, 1].gsub(' ', '')
        line.gsub!(/^[> ]*>/, '')
      end
      line = ' ' + line if line[/^ /]
      if line.length > 78
        line.gsub(/(.{1,#{72 - quotes.length}}|[^\s]+)(\s+|$)/, "#{quotes}\\1 \n").rstrip
      else
        quotes + line
      end
    end.join("\n")
  end
  
  def self.multipart_decode(headers, body)
    if headers[/^Content-Type: multipart/i]
      boundary = Regexp.escape(headers[/^Content-Type:.*boundary ?= ?"?([^"]+?)"?(;|$)/i, 1])
      match = /.*?#{boundary}\n(.*?)\n\n(.*?)\n(--)?#{boundary}/m.match(body)
      part_headers = match[1].gsub(/\n( |\t)/, ' ')
      part_body = match[2]
      return multipart_decode(part_headers, part_body)
    else
      return headers, body
    end
  end
end
