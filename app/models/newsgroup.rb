class Newsgroup < ActiveRecord::Base
  has_many :unread_post_entries, dependent: :destroy
  has_many :posts, foreign_key: :newsgroup_name, primary_key: :name, dependent: :destroy
  has_many :subscriptions, foreign_key: :newsgroup_name, primary_key: :name, dependent: :destroy

  default_scope -> { order(:name) }

  def as_json(options = {})
    if options[:for_user]
      unread = unread_for_user(options[:for_user])
      super(except: :id).merge(
        unread_count: unread[:count],
        unread_class: unread[:personal_class],
        newest_date: posts.order(:date).last.try(:date)
      )
    else
      super(except: :id)
    end
  end

  def control?
    true if name[/^control\./]
  end

  def posting_allowed?
    status == 'y'
  end

  def self.where_posting_allowed
    where(status: 'y')
  end

  def unread_for_user(user)
    personal_class = nil
    count = unread_post_entries.where(user_id: user.id).count
    max_level = unread_post_entries.where(user_id: user.id).maximum(:personal_level)
    personal_class = PERSONAL_CLASSES[max_level] if max_level
    return { count: count, personal_class: personal_class }
  end

  def self.reimport!(post)
    wait_for_sync_or_timeout
    FileUtils.touch('tmp/syncing.txt')

    begin
      head = body = nil
      Net::NNTP.start(NEWS_SERVER) do |nntp|
        nntp.group(post.newsgroup_name)
        head = nntp.head(post.number)[1].join("\n")
        body = nntp.body(post.number)[1].join("\n")
      end
      entries = post.unread_post_entries + post.starred_post_entries
      post.delete # Shhh, don't run the destroy handlers
      new_post = Post.import!(post.newsgroup, post.number, head, body)
      entries.each do |entry|
        entry.update_attributes(post: new_post)
      end
    ensure
      FileUtils.rm('tmp/syncing.txt')
    end
  end

  def self.sync_group!(nntp, name, status, standalone = true, full_reload = false)
    if standalone
      wait_for_sync_or_timeout
      FileUtils.touch('tmp/syncing.txt')
    end

    begin
      if Newsgroup.where(name: name).exists?
        newsgroup = Newsgroup.where(name: name).first
        newsgroup.update_attributes(status: status)
      else
        newsgroup = Newsgroup.create!(name: name, status: status)
      end

      puts nntp.group(newsgroup.name)[1] if $in_rake
      my_posts = Post.where(newsgroup_name: newsgroup.name).pluck(:number)
      news_posts = nntp.listgroup(newsgroup.name)[1].map(&:to_i)
      to_delete = my_posts - news_posts
      to_import = news_posts - my_posts

      puts "Deleting #{to_delete.size} posts." if $in_rake
      to_delete.each do |number|
        Post.where(newsgroup_name: newsgroup.name, number: number).first.destroy
      end

      puts "Importing #{to_import.size} posts." if $in_rake
      to_import.each do |number|
        head = nntp.head(number)[1].join("\n")
        body = nntp.body(number)[1].join("\n")
        post = Post.import!(newsgroup, number, head, body)
        if not full_reload
          User.active.each do |user|
            if not post.authored_by?(user)
              personal_level = PERSONAL_CODES[post.personal_class_for_user(user)]
              subscription = user.subscriptions.for(newsgroup) || user.default_subscription
              unread_level = subscription.unread_level || user.default_subscription.unread_level
              email_level = subscription.email_level || user.default_subscription.email_level

              if personal_level >= unread_level
                UnreadPostEntry.create!(user: user, newsgroup: newsgroup, post: post, personal_level: personal_level)
              end

              if personal_level >= email_level
                Mailer.post_notification(post, user).deliver
              end
            end
          end
        end
        print '.' if $in_rake
      end
      puts if $in_rake
    ensure
      if standalone
        FileUtils.rm('tmp/syncing.txt')
      end
    end
  end

  def self.sync_all!(full_reload = false)
    wait_for_sync_or_timeout
    FileUtils.touch('tmp/syncing.txt')
    FileUtils.touch('tmp/reloading.txt') if full_reload

    begin
      Net::NNTP.start(NEWS_SERVER) do |nntp|
        my_groups = Newsgroup.select(:name).collect(&:name)
        news_groups = nntp.list[1].collect{ |line| line.split[0] }
        (my_groups - news_groups).each{ |name| Newsgroup.find_by_name(name).destroy }

        nntp.list[1].each do |line|
          s = line.split
          sync_group!(nntp, s[0], s[3], false, full_reload)
        end
      end
      FileUtils.touch('tmp/lastsync.txt')
    ensure
      FileUtils.rm('tmp/reloading.txt') if full_reload
      FileUtils.rm('tmp/syncing.txt')
    end
  end

  def self.reload_all!
    # This should only be run interactively via rake anyway
    Rails.logger = Logger.new(nil)
    ActiveRecord::Base.logger = Logger.new(nil)

    wait_for_sync_or_timeout
    FileUtils.touch('tmp/syncing.txt')
    puts "Deleting all existing post data...\n\n" if $in_rake
    StarredPostEntry.delete_all
    UnreadPostEntry.delete_all
    Post.delete_all
    Newsgroup.delete_all
    FileUtils.rm('tmp/syncing.txt')
    sync_all!(true)
  end

  def self.wait_for_sync_or_timeout
    if File.exists?('tmp/syncing.txt')
      print "Waiting for another active sync to complete... " if $in_rake
      15.times do
        sleep 1
        if not File.exists?('tmp/syncing.txt')
          puts "OK\n\n" if $in_rake
          return
        end
      end
      puts "timed out!\n\n" if $in_rake
      raise 'Timed out waiting for another active sync to complete'
    end
  end
end
