<% if @plusone_error %>
alert('<%= @plusone_error %>')
<% else %>

<% if @plusoned %>
$('#plusone_post_button').addClass('plusoned')
<% else %>
$('#plusone_post_button').removeClass('plusoned')
<% end %>

<% end %>
