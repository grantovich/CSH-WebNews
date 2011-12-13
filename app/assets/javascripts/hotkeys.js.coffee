$ ->
  $ns = $("#posts_list")    # Namespace
  ts = 'tr[data-level="1"]' # Topic Selector
  ss = 'tr.selected'        # Selected Selector
  $(document).keydown (e) ->
    return if isTyping(e) 

    code = if e.keyCode then e.keyCode else e.which # X Browser Support
    switch code
      when 74 # j/J
        if e.shiftKey # J
          # Click next topic
          click $ns.find(ss).nextAll(ts).first()
        else if e.ctrlKey # ^j
          # Go to next group
          click $("#groups_list li.selected").next('li')
        else          # j
          # Click the next row from the one that is selected
          click $ns.find(ss).next('tr')
      when 75 # k/K
        if e.shiftKey # K
          # Go to previous topic
          click $ns.find(ss).prevAll(ts)[1]
        else if e.ctrlKey # ^k
          # Go to previous group
          click $("#groups_list li.selected").prev('li')
        else          # k
          # Go to previous row
          click $ns.find(ss).prev('tr')
      when 78         # n
        # Go to Next Unread
        click $("#next_unread")
      when 79 # o/O
        if e.shiftKey # O
          # Close the current topic
          click $ns.find(ss).prevAll(ts).first()
        else          # o
          # Open/Close the selected row
          click $ns.find(ss)
      when 82 # r/R
        if e.shiftKey # R
          # Mark all as read
          click $("#toolbar .mark_read")
        else          # r
          # Mark all in group read
          click $("#group_view .mark_read")

    false # Prevent Default

# Don't interrupt the user typing a message
isTyping = (e) ->
  element = null
  # X Browser Support
  if e.target 
    element = e.target
  else if e.srcElement 
    element = e.srcElement

  if element.nodeType == 3 
    element = element.parentNode

  if(element.tagName == 'INPUT' || element.tagName == 'TEXTAREA')
    return true
  else
    return false

click = (el) ->
  $el = $(el)
  $el.click()
  if (hash = $el.attr('href')) && hash[0..1] == '#!'
    location.hash = hash[1..-1]
  
