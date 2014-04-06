ImageHover =
  init: ->
    if Conf['Image Hover']
      Post.callbacks.push
        name: 'Image Hover'
        cb:   @node
    if Conf['Image Hover in Catalog']
      CatalogThread.callbacks.push
        name: 'Image Hover'
        cb:   @catalogNode
  node: ->
    return unless @file?.isImage or @file?.isVideo
    $.on @file.thumb, 'mouseover', ImageHover.mouseover
  catalogNode: ->
    return unless @thread.OP.file?.isImage
    $.on @nodes.thumb, 'mouseover', ImageHover.mouseover
  mouseover: (e) ->
    post = if $.hasClass @, 'thumb'
      g.posts[@parentNode.dataset.fullID]
    else
      Get.postFromNode @
    {isVideo} = post.file
    if post.file.fullImage
      el = post.file.fullImage
      TrashQueue.remove el
    else
      el = $.el (if isVideo then 'video' else 'img'),
        className: 'full-image'
        src: post.file.URL
      post.file.fullImage = el
      {thumb} = post.file
      $.after (if isVideo and Conf['Show Controls'] then thumb.parentNode else thumb), el
    el.id = 'ihover'
    el.dataset.fullID = post.fullID
    if isVideo
      el.loop = true
      el.controls = false
      el.muted = not Conf['Allow Sound']
      el.play() if Conf['Autoplay']
    naturalHeight = if post.file.isVideo then 'videoHeight' else 'naturalHeight'
    UI.hover
      root: @
      el: el
      latestEvent: e
      endEvents: 'mouseout click'
      asapTest: -> el[naturalHeight]
      cb: ->
        if isVideo
          el.pause()
          TrashQueue.add el
        el.removeAttribute 'id'
    $.on el, 'error', ImageHover.error
  error: ->
    return unless doc.contains @
    post = g.posts[@dataset.fullID]

    src = @src.split '/'
    if src[2] is 'i.4cdn.org'
      URL = Redirect.to 'file',
        boardID:  src[3]
        filename: src[5].replace /\?.+$/, ''
      if URL
        @src = URL
        return
      if g.DEAD or post.isDead or post.file.isDead
        return

    timeoutID = setTimeout (=> @src = post.file.URL + '?' + Date.now()), 3000
    <% if (type === 'crx') { %>
    $.ajax post.file.URL,
      onloadend: ->
        return if @status isnt 404
        clearTimeout timeoutID
        post.kill true
    ,
      type: 'head'
    <% } else { %>
    # XXX CORS for i.4cdn.org WHEN?
    $.ajax "//a.4cdn.org/#{post.board}/res/#{post.thread}.json", onload: ->
      return if @status isnt 200
      for postObj in @response.posts
        break if postObj.no is post.ID
      if postObj.no isnt post.ID
        clearTimeout timeoutID
        post.kill()
      else if postObj.filedeleted
        clearTimeout timeoutID
        post.kill true
    <% } %>
