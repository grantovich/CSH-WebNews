class AddHiddenToPost < ActiveRecord::Migration
  def change
    add_column :posts, :hidden, :boolean
    Post.all.each do |post|
      post.update_attributes!(:hidden => false)
    end
  end
end
