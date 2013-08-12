Linkify =
  init: ->
    return if g.VIEW is 'catalog' or not Conf['Linkify']

    @regString = if Conf['Allow False Positives']
      ///(
        \b(
          [-a-z]+://
          |
          [a-z]{3,}\.[-a-z0-9]+\.[a-z]
          |
          [-a-z0-9]+\.[a-z]
          |
          [\d]+\.[\d]+\.[\d]+\.[\d]+/
          |
          [a-z]{3,}:[a-z0-9?]
          |
          [^\s@]+@[a-z0-9.-]+\.[a-z0-9]
        )
        [^\s'"]+
      )///gi
    else
      /(((magnet|mailto)\:|(www\.)|(news|(ht|f)tp(s?))\:\/\/){1}\S+)/gi

    if Conf['Comment Expansion']
      ExpandComment.callbacks.push @node

    if Conf['Title Link']
      $.sync 'CachedTitles', Linkify.titleSync

    Post::callbacks.push
      name: 'Linkify'
      cb:   @node

  node: ->
    if @isClone
      if Conf['Embedding']
        i = 0
        items = $$ '.embed', @nodes.comment
        while el = items[i++]
          $.on el, 'click', Linkify.cb.toggle
          Linkify.cb.toggle.call el if $.hasClass el, 'embedded'

      return

    snapshot = $.X './/br|.//text()', @nodes.comment
    i = 0
    while node = snapshot.snapshotItem i++

      continue if node.parentElement.nodeName is "A"

      if Linkify.regString.test node.data
        Linkify.regString.lastIndex = 0
        Linkify.gatherLinks snapshot, @, node, i

    return unless Conf['Embedding'] or Conf['Link Title']

    items = @nodes.links
    i = 0
    while range = items[i++]
      if data = Linkify.services range
        Linkify.embed data if Conf['Embedding']
        Linkify.title data if Conf['Link Title']

    return

  gatherLinks: (snapshot, post, node, i) ->
    {data} = node
    len    = data.length
    links  = []

    while (match = Linkify.regString.exec data)
      {index} = match
      link    = match[0]
      len2    = index + link.length

      break if len is len2

      range = document.createRange();
      range.setStart node, index
      range.setEnd   node, len2
      links.push range

    Linkify.regString.lastIndex = 0

    if match
      links.push Linkify.seek snapshot, post, node, match, i

    for range in links.reverse()
      Linkify.makeLink range, post

    return

  seek: (snapshot, post, node, match, i) ->
    link    = match[0]
    range = document.createRange()
    range.setStart node, match.index

    while (next = snapshot.snapshotItem i++) and next.nodeName isnt 'BR'
      node = next
      data = node.data
      if result = /[\s'"]/.exec data
        {index} = result
        range.setEnd node, index
        Linkify.regString.lastIndex = index
        Linkify.gatherLinks snapshot, post, node, i

    if range.collapsed
      range.setEndAfter node

    range

  makeLink: (range, post) ->
    link = range.toString()
    link =
      if link.contains ':'
        link
      else (
        if link.contains '@'
          'mailto:'
        else
          'http://'
      ) + link

    a = $.el 'a',
      className: 'linkify'
      rel:       'nofollow noreferrer'
      target:    '_blank'
      href:      link
    $.add a, range.extractContents()
    range.insertNode a
    post.nodes.links.push a
    return

  services: (link) ->
    href = link.href

    for key, type of Linkify.types
      continue unless match = type.regExp.exec href
      return [key, match[1], match[2], link]

    return

  embed: (data) ->
    [key, uid, options, link] = data
    href = link.href
    embed = $.el 'a',
      className:   'embedder'
      href:        'javascript:;'
      textContent: '(embed)'

    for name, value of {key, href, uid, options}
      embed.dataset[name] = value

    embed.dataset.nodedata = link.innerHTML

    $.addClass link, "#{embed.dataset.key}"

    $.on embed, 'click', Linkify.cb.toggle
    $.after link, [$.tn(' '), embed]

    if Conf['Auto-embed']
      Linkify.cb.toggle.call embed

    data.push embed

    return

  title: (data) ->
    [key, uid, options, link, embed] = data
    return unless service = Linkify.types[key].title
    titles = Conf['CachedTitles']
    if title = titles[uid]
      # Auto-embed may destroy our links.
      if link
        link.textContent = title[0]
      if Conf['Embedding']
        embed.dataset.title = title[0]
    else
      try
        $.cache service.api(uid), ->
          title = Linkify.cb.title @, data
      catch err
        if link
          link.innerHTML = "[#{key}] <span class=warning>Title Link Blocked</span> (are you using NoScript?)</a>"
        return
      if title
        titles[uid]  = [title, Date.now()]
        $.set 'CachedTitles', titles

  titleSync: (value) ->
    Conf['CachedTitles'] = value

  cb:
    toggle: ->
      [string, @textContent] = if $.hasClass @, "embedded"
        ['unembed', '(embed)']
      else
        ['embed', '(unembed)']
      $.replace @previousElementSibling, Linkify.cb[string] @
      $.toggleClass @, 'embedded'

    embed: (a) ->
      # We create an element to embed
      el = (type = Linkify.types[a.dataset.key]).el a

      # Set style values.
      el.style.cssText = if style = type.style
        style
      else
        "border: 0; width: 640px; height: 390px"

      return el

    unembed: (a) ->
      # Recreate the original link.
      el = $.el 'a',
        rel:         'nofollow noreferrer'
        target:      'blank'
        className:   'linkify'
        href:        a.dataset.href
        innerHTML:   a.dataset.title or a.dataset.nodedata

      $.addClass el, a.dataset.key

      return el

    title: (response, data) ->
      [key, uid, options, link, embed] = data
      service = Linkify.types[key].title
      switch response.status
        when 200, 304
          text = "#{service.text JSON.parse response.responseText}"
          if Conf['Embedding']
            embed.dataset.title = text
        when 404
          text = "[#{key}] Not Found"
        when 403
          text = "[#{key}] Forbidden or Private"
        else
          text = "[#{key}] #{@status}'d"
      link.textContent = text if link

  types:
    audio:
      regExp: /(.*\.(mp3|ogg|wav))$/
      el: (a) ->
        $.el 'audio',
          controls:    'controls'
          preload:     'auto'
          src:         a.dataset.uid

    gist:
      regExp: /.*(?:gist.github.com.*\/)([^\/][^\/]*)$/
      el: (a) ->
        div = $.el 'iframe',
          # Github doesn't allow embedding straight from the site, so we use an external site to bypass that.
          src: "http://www.purplegene.com/script?url=https://gist.github.com/#{a.dataset.uid}.js"
      title:
        api: (uid) -> "https://api.github.com/gists/#{uid}"
        text: ({files}) ->
          return file for file of files when files.hasOwnProperty file

    image:
      regExp: /(http|www).*\.(gif|png|jpg|jpeg|bmp)$/
      style: 'border: 0; width: auto; height: auto;'
      el: (a) ->
        $.el 'div',
          innerHTML: "<a target=_blank href='#{a.dataset.href}'><img src='#{a.dataset.href}'></a>"

    InstallGentoo:
      regExp: /.*(?:paste.installgentoo.com\/view\/)([0-9a-z_]+)/
      el: (a) ->
        $.el 'iframe',
          src: "http://paste.installgentoo.com/view/embed/#{a.dataset.uid}"

    LiveLeak:
      regExp: /.*(?:liveleak.com\/view.+i=)([0-9a-z_]+)/
      el: (a) ->
        $.el 'object',
          innerHTML:  "<embed src='http://www.liveleak.com/e/#{a.dataset.uid}?autostart=true' wmode='opaque' width='640' height='390' pluginspage='http://get.adobe.com/flashplayer/' type='application/x-shockwave-flash'></embed>"

    MediaCrush:
      regExp: /.*(?:mediacru.sh\/)([0-9a-z_]+)/i
      style: 'border: 0; width: 640px; height: 480px; resize: both;'
      el: (a) ->
        $.el 'iframe',
          src: "https://mediacru.sh/#{a.dataset.uid}"
# MediaCrush CORS When?
#
#        el = $.el 'div'
#        $.cache "https://mediacru.sh/#{a.dataset.uid}.json", ->
#          {status} = @
#          return unless [200, 304].contains status
#          {files} = JSON.parse req.response
#          file = file for file of files when files.hasOwnProperty file
#          el.innerHTML = switch file.type
#            when 'video/mp4', 'video/ogv'
#              """
#<video autoplay loop>
#  <source src="https://mediacru.sh/#{a.dataset.uid}.mp4" type="video/mp4;">
#  <source src="https://mediacru.sh/#{a.dataset.uid}.ogv" type="video/ogg; codecs='theora, vorbis'">
#</video>"""
#            when 'image/png', 'image/gif', 'image/jpeg'
#              "<a target=_blank href='#{a.dataset.href}'><img src='https://mediacru.sh/#{file.file}'></a>"
#            when 'image/svg', 'image/svg+xml'
#              "<embed src='https://mediacru.sh/#{file.file}' type='image/svg+xml' />"
#            when 'audio/mpeg'
#              "<audio controls><source src='https://mediacru.sh/#{file.file}'></audio>"
#        el


    pastebin:
      regExp: /.*(?:pastebin.com\/(?!u\/))([^#\&\?]*).*/
      el: (a) ->
        div = $.el 'iframe',
          src: "http://pastebin.com/embed_iframe.php?i=#{a.dataset.uid}"

    SoundCloud:
      regExp: /.*(?:soundcloud.com\/|snd.sc\/)([^#\&\?]*).*/
      style: 'height: auto; width: 500px; display: inline-block;'
      el: (a) ->
        div = $.el 'div',
          className: "soundcloud"
          name: "soundcloud"
        $.ajax(
          "//soundcloud.com/oembed?show_artwork=false&&maxwidth=500px&show_comments=false&format=json&url=https://www.soundcloud.com/#{a.dataset.uid}"
          onloadend: ->
            div.innerHTML = JSON.parse(@responseText).html
          false)
        div
      title:
        api: (uid) -> "//soundcloud.com/oembed?show_artwork=false&&maxwidth=500px&show_comments=false&format=json&url=https://www.soundcloud.com/#{uid}"
        text: (_) -> _.title

    TwitchTV:
      regExp: /.*(?:twitch.tv\/)([^#\&\?]*).*/
      style: "border: none; width: 640px; height: 360px;"
      el: (a) ->
        if result = /(\w+)\/(?:[a-z]\/)?(\d+)/i.exec a.dataset.uid
          [_, channel, chapter] = result

          $.el 'object',
            data: 'http://www.twitch.tv/widgets/archive_embed_player.swf'
            innerHTML: """
<param name='allowFullScreen' value='true' />
<param name='flashvars' value='channel=#{channel}&start_volume=25&auto_play=false#{if chapter then "&chapter_id=" + chapter else ""}' />
"""

        else
          channel = (/(\w+)/.exec a.dataset.uid)[0]

          $.el 'object',
            data: "http://www.twitch.tv/widgets/live_embed_player.swf?channel=#{channel}"
            innerHTML: """
<param  name="allowFullScreen" value="true" />
<param  name="movie" value="http://www.twitch.tv/widgets/live_embed_player.swf" />
<param  name="flashvars" value="hostname=www.twitch.tv&channel=#{channel}&auto_play=true&start_volume=25" />
"""

    Vocaroo:
      regExp: /.*(?:vocaroo.com\/)([^#\&\?]*).*/
      style: 'border: 0; width: 150px; height: 45px;'
      el: (a) ->
        $.el 'object',
          innerHTML: "<embed src='http://vocaroo.com/player.swf?playMediaID=#{a.dataset.uid.replace /^i\//, ''}&autoplay=0' wmode='opaque' width='150' height='45' pluginspage='http://get.adobe.com/flashplayer/' type='application/x-shockwave-flash'></embed>"

    Vimeo:
      regExp:  /.*(?:vimeo.com\/)([^#\&\?]*).*/
      el: (a) ->
        $.el 'iframe',
          src: "//player.vimeo.com/video/#{a.dataset.uid}?wmode=opaque"
      title:
        api: (uid) -> "https://vimeo.com/api/oembed.json?url=http://vimeo.com/#{uid}"
        text: (_) -> _.title

    Vine:
      regExp: /.*(?:vine.co\/)([^#\&\?]*).*/
      style: 'border: none; width: 500px; height: 500px;'
      el: (a) ->
        $.el 'iframe',
          src: "https://vine.co/#{a.dataset.uid}/card"

    YouTube:
      regExp: /.*(?:youtu.be\/|youtube.*v=|youtube.*\/embed\/|youtube.*\/v\/|youtube.*videos\/)([^#\&\?]*)\??(t\=.*)?/
      el: (a) ->
        $.el 'iframe',
          src: "//www.youtube.com/embed/#{a.dataset.uid}#{if a.dataset.option then '#' + a.dataset.option else ''}?wmode=opaque"
      title:
        api: (uid) -> "https://gdata.youtube.com/feeds/api/videos/#{uid}?alt=json&fields=title/text(),yt:noembed,app:control/yt:state/@reasonCode"
        text: (data) -> data.entry.title.$t