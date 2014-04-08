ImageExpand =
  init: ->
    return if !Conf['Image Expansion']

    @EAI = $.el 'a',
      className: 'expand-all-shortcut fa fa-expand'
      textContent: 'EAI' 
      title: 'Expand All Images'
      href: 'javascript:;'
    $.on @EAI, 'click', @cb.toggleAll
    Header.addShortcut @EAI, 3
    $.on d, 'scroll visibilitychange', @cb.playVideos

    Post.callbacks.push
      name: 'Image Expansion'
      cb: @node

  node: ->
    return unless @file and (@file.isImage or @file.isVideo)
    {thumb} = @file
    $.on thumb.parentNode, 'click', ImageExpand.cb.toggle
    if @isClone
      if @file.isImage and @file.isExpanding
        # If we clone a post where the image is still loading,
        # make it loading in the clone too.
        ImageExpand.contract @
        ImageExpand.expand @
        return
      if @file.isExpanded and @file.isVideo
        ImageExpand.setupVideoControls @
        return
    if ImageExpand.on and !@isHidden and (Conf['Expand spoilers'] or !@file.isSpoiler)
      ImageExpand.expand @

  cb:
    toggle: (e) ->
      return if e.shiftKey or e.altKey or e.ctrlKey or e.metaKey or e.button isnt 0
      post = Get.postFromNode @
      return if post.file.isExpanded and post.file.fullImage?.controls
      e.preventDefault()
      ImageExpand.toggle post

    toggleAll: ->
      $.event 'CloseMenu'
      if ImageExpand.on = $.hasClass ImageExpand.EAI, 'expand-all-shortcut'
        ImageExpand.EAI.className = 'contract-all-shortcut fa fa-compress'
        ImageExpand.EAI.title     = 'Contract All Images'
        func = ImageExpand.expand
      else
        ImageExpand.EAI.className = 'expand-all-shortcut fa fa-expand'
        ImageExpand.EAI.title     = 'Expand All Images'
        func = ImageExpand.contract

      g.posts.forEach (post) ->
        for post in [post].concat post.clones
          {file} = post
          return unless file and (file.isImage or file.isVideo) and doc.contains post.nodes.root
          if ImageExpand.on and (
            post.isHidden or
            !Conf['Expand spoilers'] and post.file.isSpoiler or
            !doc.contains(post.nodes.root) or
            Conf['Expand from here'] and Header.getTopOf(post.file.thumb) < 0)
              return
          $.queueTask func, post
        return

    playVideos: (e) ->
      for fullID, post of g.posts
        continue unless post.file and post.file.isVideo and post.file.isExpanded
        for post in [post].concat post.clones
          play = !d.hidden and !post.isHidden and doc.contains(post.nodes.root) and Header.isNodeVisible post.nodes.root
          if play then post.file.fullImage.play() else post.file.fullImage.pause()
      return

    setFitness: ->
      (if @checked then $.addClass else $.rmClass) doc, @name.toLowerCase().replace /\s+/g, '-'

  toggle: (post) ->
    {thumb} = post.file
    unless post.file.isExpanded or post.file.isExpanding
      ImageExpand.expand post
      return

    # Scroll back to the thumbnail when contracting the image
    # to avoid being left miles away from the relevant post.
    {root} = post.nodes
    {top, left} = (if Conf['Advance on contract'] then do ->
      next = root
      while next = $.x "following::div[contains(@class,'postContainer')][1]", next
        continue if $('.stub', next) or next.offsetHeight is 0
        return next
      root
    else 
      root
    ).getBoundingClientRect()

    if top < 0
      y = top
      if Conf['Fixed Header'] and not Conf['Bottom Header']
        headRect = Header.bar.getBoundingClientRect()
        y -= headRect.top + headRect.height

    if left < 0
      x = -window.scrollX
    window.scrollBy x, y if x or y
    ImageExpand.contract post

  contract: (post) ->
    if post.file.isVideo and video = post.file.fullImage
      video.pause()
      TrashQueue.add video, post
      post.file.thumb.parentNode.href = video.src
      post.file.thumb.parentNode.target = '_blank'
      for eventName, cb of ImageExpand.videoCB
        $.off video, eventName, cb
      $.rm post.file.videoControls
      delete post.file.videoControls
    $.rmClass post.nodes.root, 'expanded-image'
    $.rmClass post.file.thumb, 'expanding'
    delete post.file.isExpanding
    post.file.isExpanded = false

  expand: (post, src) ->
    # Do not expand images of hidden/filtered replies, or already expanded pictures.
    {thumb, isVideo} = post.file
    return if post.isHidden or post.file.isExpanded or $.hasClass thumb, 'expanding'
    $.addClass thumb, 'expanding'
    if el = post.file.fullImage
      # Expand already-loaded/ing picture.
      TrashQueue.remove el
    else
      el = post.file.fullImage = $.el (if isVideo then 'video' else 'img'),
        className: 'full-image'
      el.loop = true if isVideo
      $.on el, 'error', ImageExpand.error
      el.src = src or post.file.URL
    $.after thumb, el unless el is thumb.nextSibling
    $.asap (-> el.videoHeight or el.naturalHeight), ->
      ImageExpand.completeExpand post

  completeExpand: (post) ->
    {thumb} = post.file
    return unless $.hasClass thumb, 'expanding' # contracted before the image loaded
    delete post.file.isExpanding
    post.file.isExpanded = true

    complete = ->
      $.addClass post.nodes.root, 'expanded-image'
      $.rmClass  post.file.thumb, 'expanding'
      ImageExpand.setupVideo post if post.file.isVideo

    unless post.nodes.root.parentNode
      # Image might start/finish loading before the post is inserted.
      # Don't scroll when it's expanded in a QP for example.
      complete()
      return

    post.file.fullImage.play() if post.file.isVideo and !d.hidden and Header.isNodeVisible post.nodes.root
    {bottom} = post.nodes.root.getBoundingClientRect()
    $.queueTask ->
      complete()
      return unless bottom <= 0
      window.scrollBy 0, post.nodes.root.getBoundingClientRect().bottom - bottom

  videoCB:
    click: (e) ->
      if @paused and not @controls
        @play()
        e.stopPropagation()

    # dragging to the left contracts the video
    mousedown: (e) -> @dataset.mousedown = 'true' if e.button is 0
    mouseup: (e) -> @dataset.mousedown = 'false' if e.button is 0
    mouseover: (e) -> @dataset.mousedown = 'false'
    mouseout: (e) ->
      if @dataset.mousedown is 'true' and e.clientX <= @getBoundingClientRect().left
        ImageExpand.contract (Get.postFromNode @)

  setupVideoControls: (post) ->
    {file} = post
    video = file.fullImage

    # disable link to file so native controls can work
    file.thumb.parentNode.removeAttribute 'href'
    file.thumb.parentNode.removeAttribute 'target'

    # setup callbacks on video element
    video.dataset.mousedown = 'false'
    $.on video, eventName, cb for eventName, cb of ImageExpand.videoCB

    # setup controls in file info
    file.videoControls = $.el 'span',
      className: 'video-controls'
    if Conf['Show Controls']
      contract = $.el 'a',
        textContent: 'contract'
        href: 'javascript:;'
        title: 'You can also contract the video by dragging it to the left.'
      $.on contract, 'click', (e) -> ImageExpand.contract post
      $.add file.videoControls, [$.tn('\u00A0'), contract]
    $.add file.text, file.videoControls

  setupVideo: (post) ->
    ImageExpand.setupVideoControls post
    {file} = post
    video = file.fullImage
    video.muted = !Conf['Allow Sound']
    video.controls = Conf['Show Controls']
    if Conf['Autoplay']
      video.controls = false
      video.play()
      # Hacky workaround for Firefox forever-loading bug for very short videos
      if Conf['Show Controls']
        $.asap (-> (video.readyState >= 3 and video.currentTime <= Math.max 0.1, (video.duration - 0.5)) or !file.isExpanded), ->
          video.controls = true if file.isExpanded
        , 500

  error: ->
    post = Get.postFromNode @
    post.file.isReady = false
    $.rm @
    delete post.file.fullImage
    # Images can error:
    #  - before the image started loading.
    #  - after the image started loading.
    unless post.file.isExpanding or post.file.isExpanded
      # Don't try to re-expend if it was already contracted.
      return
    ImageExpand.contract post

    src = @src.split '/'
    if src[2] is 'i.4cdn.org'
      URL = Redirect.to 'file',
        boardID:  src[3]
        filename: src[5]
      if URL
        setTimeout ImageExpand.expand, 10000, post, URL
        return
      if g.DEAD or post.isDead or post.file.isDead
        return

    timeoutID = setTimeout ImageExpand.expand, 10000, post
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

  menu:
    init: ->
      return if !Conf['Image Expansion']

      el = $.el 'span',
        textContent: 'Image Expansion'
        className: 'image-expansion-link'

      {createSubEntry} = ImageExpand.menu
      subEntries = []
      for name, conf of Config.imageExpansion
        subEntries.push createSubEntry name, conf[1]

      $.event 'AddMenuEntry',
        type: 'header'
        el: el
        order: 105
        subEntries: subEntries

    createSubEntry: (name, desc) ->
      label = $.el 'label',
        innerHTML: "<input type=checkbox name='#{name}'> #{name}"
        title: desc
      input = label.firstElementChild
      if name in ['Fit width', 'Fit height']
        $.on input, 'change', ImageExpand.cb.setFitness
      input.checked = Conf[name]
      $.event 'change', null, input
      $.on input, 'change', $.cb.checked
      el: label
