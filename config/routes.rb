Rails.application.routes.draw do
  root to: 'pages#home'
  get '/authenticate', to: 'pages#authenticate'

  get '/home',      to: 'pages#home'
  get '/activity',  to: 'pages#home'
  get '/check_new', to: 'pages#check_new'

  get '/about',       to: 'pages#about'
  get '/status',      to: 'pages#status'
  get '/new_user',    to: 'pages#new_user'
  get '/old_user',    to: 'pages#old_user'
  get '/rss_caution', to: 'pages#rss_caution'

  get '/user',          to: 'users#show',          as: :user
  get '/settings',      to: 'users#edit',          as: :edit_user
  put '/settings',      to: 'users#update',        as: :update_user
  put '/settings/api',  to: 'users#update_api',    as: :update_user_api
  get '/unread_counts', to: 'users#unread_counts'

  get '/compose',     to: 'posts#new',         as: :new_post
  post '/compose',    to: 'posts#create',      as: :create_post
  get '/next_unread', to: 'posts#next_unread'
  put '/mark_read',   to: 'posts#mark_read',   as: :mark_read

  get '/search',   to: 'posts#search', as: :search
  get '/search_entry', to: 'posts#search_entry', as: :search_entry

  constraints newsgroup: /[^\/]+/, number: /\d+/ do
    get '/newsgroups',                to: 'newsgroups#index',      as: :newsgroups
    get '/newsgroups/:newsgroup',     to: 'newsgroups#show',       as: :newsgroup
    get '/:newsgroup/index',          to: 'posts#index',           as: :posts
    get '/:newsgroup/:number',        to: 'posts#show',            as: :post
    get '/:newsgroup/:number/sticky', to: 'posts#edit_sticky',     as: :edit_post_sticky
    put '/:newsgroup/:number/sticky', to: 'posts#update_sticky',   as: :update_post_sticky
    put '/:newsgroup/:number/star',   to: 'posts#update_star',     as: :update_post_star
    delete '/:newsgroup/:number',     to: 'posts#destroy',         as: :destroy_post
    get '/:newsgroup/:number/cancel', to: 'posts#destroy_confirm', as: :confirm_destroy_post
  end
end
