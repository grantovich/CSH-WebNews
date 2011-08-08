selected = $('#groups_list .selected').attr('data-name')
loaded = $('#groups_list [data-loaded]').attr('data-name')

$('#groups_list nav').html('<%= j render('newsgroups/index') %>')

$('#groups_list [data-name="' + selected + '"]').addClass('selected')
$('#groups_list [data-name="' + loaded + '"]').attr('data-loaded', 'true')

unread_in_loaded = parseInt($('#groups_list [data-name="' + loaded + '"]').attr('data-unread'))
new_in_loaded = unread_in_loaded - $('#posts_list .unread').length
if new_in_loaded > 0
  posts = if new_in_loaded == 1 then 'post' else 'posts'
  $('#group_view .new_posts').text(new_in_loaded + ' new ' + posts + ' in this group!')

setTimeout (->
  $.getScript '/check_new'
), check_new_delay
