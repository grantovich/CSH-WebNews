@chunks = {}
@check_new_interval = 15000
@check_new_retry_interval = 5000
@draft_save_interval = 2000
@delay_click_time = 300
window.loaded_location = false
window.active_navigation = false
window.active_scroll_load = false
window.active_check_new = false
window.check_new_timeout = false
window.draft_save_timer = false
window.delay_click_timeout = false

jQuery.fn.outerHTML = ->
  $('<div>').append(this.eq(0).clone()).html()

jQuery.ajaxScript = (method, url, success = null) ->
  $.ajax {
    url: url,
    type: method,
    dataType: 'script',
    success: success
  }

@click = (elem, extra_data = null) ->
  if $(elem).is(':visible')
    $(elem).trigger('click', extra_data)
    if (href = $(elem).attr('href')) and href[0..1] == '#!'
      location.hash = href[1..-1]

@delay_click_group = (group_li) ->
  clearTimeout(window.delay_click_timeout)
  $('#groups_list .selected').removeClass('selected')
  $(group_li).addClass('selected')
  window.delay_click_timeout = setTimeout (->
    click $(group_li).find('a'), false
  ), delay_click_time

@delay_click_post = (post_tr) ->
  clearTimeout(window.delay_click_timeout)
  $('#posts_list .selected').removeClass('selected')
  $(post_tr).addClass('selected')
  scroll_to_selected_post()
  window.delay_click_timeout = setTimeout (->
    click post_tr, false
  ), delay_click_time

@align_activity_tables = ->
  tables = $('table.activity')
  if tables.length > 1
    max_width = Math.max(($(table).width() for table in tables)...)
    max_date_width = Math.max(($(table).find('td.date').first().width() for table in tables)...)
    $(table).width(max_width) for table in tables
    $(table).find('td.date').first().width(max_date_width) for table in tables

@fix_post_header = ->
  if $('#post_header').length > 0
    $('#post_view .content').css('top', $('#post_header').outerHeight() + 'px');

@target_external_links = ->
  $('a[href^="http"]:not([href*="' + window.location.host + '"])').attr('target', '_blank')

@set_loaded_location = ->
  window.loaded_location = location.hash.split('/')[1]

@clear_loaded_location = ->
  window.loaded_location = false

@refresh_loaded_location = ->
  clear_loaded_location()
  window.onhashchange()

@set_check_timeout = (delay = check_new_interval) ->
  window.check_new_timeout = setTimeout (->
    window.active_check_new = $.getScript '/check_new?location=' + encodeURIComponent(location.hash) +
      '&newsgroup=' + encodeURIComponent($('#groups_list .selected').attr('data-name')) +
      '&number=' + encodeURIComponent($('#posts_list .selected').attr('data-number'))
  ), delay

@clear_check_timeout = ->
  clearTimeout(window.check_new_timeout)

@abort_active_check = ->
  if window.active_check_new
    window.active_check_new.abort()
    window.active_check_new = false

@reset_check_timeout = (delay = check_new_interval) ->
  clear_check_timeout()
  abort_active_check()
  set_check_timeout(delay)

@abort_active_scroll = ->
  if window.active_scroll_load
    window.active_scroll_load.abort()
    window.active_scroll_load = false

@set_draft_interval = ->
  $('a.resume_draft').show()
  window.draft_save_timer = setInterval save_draft, draft_save_interval

@save_draft = ->
  localStorage['draft_html'] = $('#dialog').outerHTML()
  localStorage['draft_form'] = JSON.stringify($('#dialog form').serializeArray())

@clear_draft_interval = ->
  clearInterval(window.draft_save_timer)

@init_dialog = ->
  $('body').append(chunks.overlay.clone())
  $('#overlay').focus()

@open_dialog = (content) ->
  $('#overlay').append(content)
  key.setScope('dialog')

@close_dialog = ->
  $('#overlay').remove()
  key.setScope('main')
  if $('#dashboard').length > 0
    $('#dashboard').focus()
  else
    $('#posts_list').focus()

@scroll_to_selected_post = ->
  view_height = $('#posts_list').height()
  scroll_top = $('#posts_list').scrollTop()
  post_top = $('#posts_list .selected').first().position().top + scroll_top
  
  if post_top + 20 > scroll_top + view_height or post_top < scroll_top
    $('#posts_list').scrollTop(post_top - (view_height / 2))

# Calls expand_thread or collapse_thread depending on the current state
@toggle_thread_expand = (tr, check_selected = false) ->
  if tr.find('.expandable').length > 0
    return expand_thread(tr)
  else if tr.find('.expanded').length > 0 and (tr.hasClass('selected') or not check_selected)
    return collapse_thread(tr)

# Returns number of rows shown
@expand_thread = (tr) ->
  rows_changed = 0
  tr.find('.expandable').removeClass('expandable').addClass('expanded')
  for child in tr.nextUntil('[data-level=' + tr.attr('data-level') + ']')
    break if parseInt($(child).attr('data-level')) < parseInt(tr.attr('data-level'))
    if $(child).is(':hidden')
      $(child).show()
      rows_changed += 1
    $(child).find('.expandable').removeClass('expandable').addClass('expanded')
  return rows_changed

# Returns number of rows hidden
@collapse_thread = (tr) ->
  rows_changed = 0
  tr.find('.expanded').removeClass('expanded').addClass('expandable')
  for child in tr.nextUntil('[data-level=' + tr.attr('data-level') + ']')
    break if parseInt($(child).attr('data-level')) < parseInt(tr.attr('data-level'))
    if $(child).is(':visible')
      $(child).hide()
      rows_changed += 1
    $(child).find('.expanded').removeClass('expanded').addClass('expandable')
  return rows_changed


window.onhashchange = ->
  if location.hash.substring(0, 3) == '#!/'
    window.active_navigation.abort() if window.active_navigation
    window.active_navigation = $.getScript location.hash.replace('#!/', '')
    
    new_location = location.hash.split('/')[1]
    if new_location != window.loaded_location
      abort_active_scroll()
      clear_loaded_location()
      $('#group_view').empty().append(chunks.spinner.clone())
      $('#post_view').empty()
      $('#groups_list .selected').removeClass('selected')
      $('#groups_list [data-name="' + new_location + '"]').addClass('selected')
      if new_location == 'home'
        $('#group_view').css('bottom', '0')
        $('#group_view').css('border-bottom', '0')
        $('#post_view').css('top', '100%')
      else
        $('#group_view').css('bottom', '')
        $('#group_view').css('border-bottom', '')
        $('#post_view').css('top', '')

$ ->
  chunks.spinner = $('#loader .spinner').clone()
  chunks.overlay = $('#loader #overlay').clone()
  chunks.ajax_error = $('#loader #ajax_error').clone()
  $('#loader').remove()
  
  target_external_links()
  $('a.resume_draft').hide() if not localStorage['draft_form']
  
  if $('#startup_msg').length > 0
    init_dialog()
    $.getScript $('#startup_msg').attr('data-action')
  
  if location.hash == '' or location.hash.substring(0, 3) != '#!/'
    location.hash = '#!/home'
  else
    window.onhashchange()
  
  set_check_timeout()

$('a[href="#"]').live 'click', ->
  return false

$('.toggle').live 'click', ->
  # Fixing the width is handled in ajaxComplete
  a = $(this)
  $(a.attr('data-selector')).toggle()
  new_text = a.attr('data-text')
  if new_text
    a.attr('data-text', a.text())
    a.text(new_text)

$('a.new_draft').live 'click', (e) ->
  if localStorage['draft_form'] and not confirm('Really abandon your saved draft and start a new post?')
    e.stopImmediatePropagation()
    return false

$('a[href^="#?/"]').live 'click', ->
  key.setScope('intermediate')
  init_dialog()
  $.getScript @href.replace('#?/', '')
  return false

$('a.mark_read').live 'click', ->
  reset_check_timeout()
  $('#next_unread').attr('href', '#')
  
  path = 'mark_read'
  after_func = null
  scope = $(this).attr('data-scope')
  newsgroup = $('#groups_list .selected').attr('data-name')
  number = $('#posts_list .selected').attr('data-number')
  thread_id = $('#posts_list .selected').attr('data-thread')
  
  if thread_id and scope == 'thread'
    path += '?in_thread=true'
    path += '&newsgroup=' + encodeURIComponent(newsgroup) + '&number=' + number
    abort_active_scroll()
    after_func = -> $('#posts_list').scroll()
    $('#posts_list tr[data-thread="' + thread_id + '"]').removeClass('unread')
  else if newsgroup and scope == 'newsgroup'
    path += '?newsgroup=' + encodeURIComponent(newsgroup)
    group_item = $('#groups_list [data-name="' + newsgroup + '"]')
    group_item.removeClass('unread mine_reply mine_in_thread').find('.unread_count').remove()
    $('#next_unread').attr('href', '#') if $('#groups_list .unread_count').length == 0
    abort_active_scroll()
    after_func = -> $('#posts_list').scroll()
    $('#posts_list tbody tr').removeClass('unread')
  else if scope == 'all'
    path += '?all_posts=true'
    $('#groups_list li').removeClass('unread mine_reply mine_in_thread').find('.unread_count').remove()
    $('#next_unread').attr('href', '#')
    if window.loaded_location == 'home'
      document.title = 'CSH WebNews'
      $('#unread_line').text('Marked all posts read. Reloading activity feed...')
      $('#activity_feeds').remove()
      after_func = -> window.onhashchange()
    else
      abort_active_scroll()
      after_func = -> $('#posts_list').scroll()
  
  $.ajaxScript 'PUT', path, after_func
  return false

$('a.mark_unread').live 'click', ->
  clear_check_timeout()
  abort_active_check()
  $('#posts_list .selected').addClass('unread')
  $.ajaxScript 'PUT', @href.replace('#~/', ''), -> set_check_timeout(0)
  return false

$('#star_post_button').live 'click', ->
  $.ajaxScript 'PUT', @href.replace('#~/', '')
  return false

$('#plusone_post_button').live 'click', ->
  $.ajaxScript 'PUT', @href.replace('#~/', '')
  return false

$('a.update_api_settings').live 'click', ->
  $('#update_api_buttons').text('Working...')
  $.ajaxScript 'PUT', @href.replace('#~/', '')
  return false

$('#crosspost_toggle').live 'click', ->
  $('#crosspost_to').val('')
  $('.crosspost_options input').val([])

$('a.minimize_draft').live 'click', ->
  save_draft()

$('a.dialog_cancel').live 'click', ->
  clear_draft_interval()
  close_dialog()

$('a.clear_draft').live 'click', ->
  localStorage.removeItem('draft_html')
  localStorage.removeItem('draft_form')
  $('a.resume_draft').hide()

$('a.resume_draft').live 'click', ->
  init_dialog()
  open_dialog(localStorage['draft_html'])
  for elem in JSON.parse(localStorage['draft_form'])
    $('#dialog form [name="' + elem.name + '"]').val(elem.value)
  $('#post_body').putCursorAtEnd() if $('#post_body').val() != ''
  set_draft_interval()

$('#new_post [type="submit"]').live 'click', (e) ->
  body = $('#new_post #post_body').first().val()
  if $.trim(body).length == 0 and not confirm('Really submit this post with no content?')
    e.stopImmediatePropagation()
    return false

$('[type="submit"]').live 'click', ->
  $('#dialog .buttons').hide()
  $('#dialog .loading').text('Working...')
  $('#dialog .errors').text('')

$('a.refresh').live 'click', ->
  refresh_loaded_location()

$('#posts_list .expander').live 'click', (e) ->
  toggle_thread_expand($(this).closest('tr'))
  e.stopImmediatePropagation()

$('#posts_list tbody tr').live 'click', (e, do_toggle = true) ->
  tr = $(this)
  
  href = tr.find('a').attr('href')
  if href.substring(0, 3) == '#~/'
    $.getScript href.replace('#~/', '')
  else
    location.hash = href
  
  toggle_thread_expand(tr, true) if do_toggle
  
  $('#posts_list .selected').removeClass('selected')
  tr.addClass('selected')
  return false

$('a, input').live 'mousedown', -> this.style.outlineStyle = 'none'
$('a, input').live 'blur', -> this.style.outlineStyle = ''

$('a, input, select, textarea, button').live 'focus', ->
  if $('#dialog').length > 0 and $(this).parents('#dialog').length == 0
    $('#dialog').find('a[href], input, select, textarea, button').
      filter(':not([disabled])').filter(':visible').first().focus()
    return false
  else if $('#overlay').length > 0 and $('#dialog').length == 0
    $('#overlay').focus()
    return false

$(window).resize ->
  fix_post_header()

$(document).ajaxComplete ->
  align_activity_tables()
  fix_post_header()
  target_external_links()
  for a in $('.toggle')
    if not $(a).hasClass('width_fixed')
      $(a).width($(a).width() + 1)
      $(a).addClass('width_fixed')
      $($(a).attr('data-selector')).toggle()

$(document).ajaxError (event, jqxhr, settings, exception) ->
  if jqxhr.readyState != 0
    if settings.url.match 'check_new'
      $('body').append(chunks.ajax_error.clone()) if $('#ajax_error').length == 0
      window.active_check_new = false
      set_check_timeout(check_new_retry_interval)
    else
      alert("An error occurred requesting #{settings.url}\n\nThis might be due to a connection issue on your end, or it might indicate a bug in WebNews. Check your connection and refresh the page. If this error persists, please file a bug report with the steps needed to reproduce it.")
