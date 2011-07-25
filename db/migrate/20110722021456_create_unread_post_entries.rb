class CreateUnreadPostEntries < ActiveRecord::Migration
  def change
    create_table :unread_post_entries do |t|
      t.references :user
      t.string :newsgroup
      t.integer :number
    end
  end
end