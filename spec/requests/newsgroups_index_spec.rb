require 'rails_helper'

RSpec.describe 'Newsgroups index' do
  it 'retrieves info about all newsgroups' do
    first_group = create(:newsgroup, id: 'test.one', description: 'test1', status: 'y', updated_at: 2.minutes.ago)
    second_group = create(:newsgroup, id: 'test.two', description: 'test2', status: 'n', updated_at: 1.minute.ago)
    third_group = create(:newsgroup, id: 'test.three', description: 'test3', status: 'y', updated_at: 3.minutes.ago)
    first_post = create(:post, created_at: 5.years.ago, newsgroups: [first_group])
    second_post = create(:post, created_at: 2.months.ago, newsgroups: [first_group, third_group])
    third_post = create(:post, created_at: 9.days.ago, newsgroups: [first_group])
    create(:unread, user: oauth_user, post: second_post, personal_level: 1)
    create(:unread, user: oauth_user, post: third_post, personal_level: 2)
    allow(Flag).to receive(:last_full_news_sync_at).and_return(2.minutes.ago)

    get newsgroups_path

    expect(response).to be_successful
    expect(response_json.keys).to match_array [:meta, :newsgroups]
    expect(response_json[:meta]).to eq({ last_sync_at: Flag.last_full_news_sync_at.iso8601 })
    expect(response_json[:newsgroups].size).to be 3
    expect(response_json[:newsgroups][0]).to eq({
      id: 'test.one',
      description: 'test1',
      posting_allowed: true,
      unread_count: 2,
      max_unread_level: 2,
      newest_post_at: third_post.created_at.iso8601,
      oldest_post_at: first_post.created_at.iso8601
    })
    expect(response_json[:newsgroups][1]).to eq({
      id: 'test.two',
      description: 'test2',
      posting_allowed: false,
      unread_count: 0,
      max_unread_level: nil,
      newest_post_at: nil,
      oldest_post_at: nil
    })
    expect(response_json[:newsgroups][2]).to eq({
      id: 'test.three',
      description: 'test3',
      posting_allowed: true,
      unread_count: 1,
      max_unread_level: 1,
      newest_post_at: second_post.created_at.iso8601,
      oldest_post_at: second_post.created_at.iso8601
    })
  end
end
