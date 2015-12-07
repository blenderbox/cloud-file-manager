{div, button, span} = React.DOM

documentStore = "http://document-store.herokuapp.com"
authorizeUrl      = "#{documentStore}/user/authenticate"
checkLoginUrl     = "#{documentStore}/user/info"
listUrl           = "#{documentStore}/document/all"
loadDocumentUrl   = "#{documentStore}/document/open"
saveDocumentUrl   = "#{documentStore}/document/save"
patchDocumentUrl  = "#{documentStore}/document/patch"
removeDocumentUrl = "#{documentStore}/document/delete"
renameDocumentUrl = "#{documentStore}/document/rename"

tr = require '../utils/translate'
isString = require '../utils/is-string'
jiff = require 'jiff'

ProviderInterface = (require './provider-interface').ProviderInterface
CloudContent = (require './provider-interface').CloudContent
CloudMetadata = (require './provider-interface').CloudMetadata

DocumentStoreAuthorizationDialog = React.createFactory React.createClass
  displayName: 'DocumentStoreAuthorizationDialog'

  getInitialState: ->
    docStoreAvailable: false

  componentWillMount: ->
    @props.provider._onDocStoreLoaded =>
      @setState docStoreAvailable: true

  authenticate: ->
    @props.provider.authorize()

  render: ->
    (div {},
      if @state.docStoreAvailable
        (button {onClick: @authenticate}, 'Authorization Needed')
      else
        'Trying to log into the Document Store...'
    )

class DocumentStoreProvider extends ProviderInterface

  constructor: (@options = {}) ->
    super
      name: DocumentStoreProvider.Name
      displayName: @options.displayName or (tr '~PROVIDER.DOCUMENT_STORE')
      capabilities:
        save: true
        load: true
        list: true
        remove: true
        rename: true
        share: true

    @user = null

  @Name: 'documentStore'

  previouslySavedContent: null

  authorized: (@authCallback) ->
    if @authCallback
      if @user
        @authCallback true
      else
        @_checkLogin()
    else
      @user isnt null

  authorize: ->
    @_showLoginWindow()

  _onDocStoreLoaded: (@docStoreLoadedCallback) ->
    if @_docStoreLoaded
      @docStoreLoadedCallback()

  _loginSuccessful: (@user) ->
    @_loginWindow?.close()
    @authCallback true

  _checkLogin: ->
    provider = @
    $.ajax
      dataType: 'json'
      url: checkLoginUrl
      xhrFields:
        withCredentials: true
      success: (data) ->
        provider.docStoreLoadedCallback()
        provider._loginSuccessful(data)
      error: ->
        provider.docStoreLoadedCallback()

  _loginWindow: null

  _showLoginWindow: ->
    if @_loginWindow and not @_loginWindow.closed
      @_loginWindow.focus()
    else

      computeScreenLocation = (w, h) ->
        screenLeft = window.screenLeft or screen.left
        screenTop  = window.screenTop  or screen.top
        width  = window.innerWidth  or document.documentElement.clientWidth  or screen.width
        height = window.innerHeight or document.documentElement.clientHeight or screen.height

        left = ((width / 2) - (w / 2)) + screenLeft
        top = ((height / 2) - (h / 2)) + screenTop
        return {left, top}

      width = 1000
      height = 480
      position = computeScreenLocation width, height
      windowFeatures = [
        'width=' + width
        'height=' + height
        'top=' + position.top or 200
        'left=' + position.left or 200
        'dependent=yes'
        'resizable=no'
        'location=no'
        'dialog=yes'
        'menubar=no'
      ]

      @_loginWindow = window.open(authorizeUrl, 'auth', windowFeatures.join())

      pollAction = =>
        try
          href = @_loginWindow.location.href
          if (href is window.location.href)
            clearInterval poll
            @_loginWindow.close()
            @_checkLogin()
        catch e
          # console.log e

      poll = setInterval pollAction, 200

  renderAuthorizationDialog: ->
    (DocumentStoreAuthorizationDialog {provider: @, authCallback: @authCallback})

  renderUser: ->
    if @user
      (span {}, (span {className: 'document-store-icon'}), @user.name)
    else
      null

  list: (metadata, callback) ->
    $.ajax
      dataType: 'json'
      url: listUrl
      context: @
      xhrFields:
        withCredentials: true
      success: (data) ->
        list = []
        for own key, file of data
          list.push new CloudMetadata
            name: file.name
            providerData: {id: file.id}
            type: CloudMetadata.File
            provider: @
        callback null, list
      error: ->
        callback null, []

  loadSharedContent: (id, callback) ->
    sharedMetadata = new CloudMetadata
      sharedContentId: id
      type: CloudMetadata.File
    @load(sharedMetadata, callback)

  load: (metadata, callback) ->
    withCredentials = unless metadata.sharedContentId then true else false
    $.ajax
      url: loadDocumentUrl
      data:
        recordid: metadata.providerData?.id or metadata.sharedContentId
      context: @
      xhrFields:
        {withCredentials}
      success: (data) ->
        if @options.patch then @previouslySavedContent = data
        callback null, new CloudContent data.content or data
      error: ->
        message = if metadata.sharedContentId
          "Unable to load document '#{metadata.sharedContentId}'. Perhaps the file was not shared?"
        else
          "Unable to load #{metadata.name or metadata.providerData?.id or 'file'}"
        callback message

  saveSharedContent: (content, callback) ->
    # for the moment, create completely random runKey and don't
    # bother to store it.
    runKey = Math.random().toString(16).substring(2)
    sharedMetadata = new CloudMetadata
      sharedContentSecretKey: runKey
      type: CloudMetadata.File
    @save content, sharedMetadata, (err, data) ->
      callback err, data.id

  save: (content, metadata, callback) ->
    content = @_wrapContent content.getContent(), metadata.sharedContentSecretKey

    withCredentials = true

    params = {}
    if metadata.providerData.id then params.recordid = metadata.providerData.id
    if metadata.sharedContentSecretKey
      params.runKey = metadata.sharedContentSecretKey
      withCredentials = false

    # See if we can patch
    if metadata.overwritable and @previouslySavedContent and
        diff = @_createDiff @previouslySavedContent, content
      sendContent = diff
      url = patchDocumentUrl
    else
      if metadata.name then params.recordname = metadata.name
      url = saveDocumentUrl
      sendContent = content

    url = @_addParams(url, params)

    $.ajax
      dataType: 'json'
      method: 'POST'
      url: url
      data: sendContent
      context: @
      xhrFields:
        {withCredentials}
      success: (data) ->
        if @options.patch then @previouslySavedContent = content
        if data.id then metadata.providerData.id = data.id
        callback null, data
      error: ->
        callback "Unable to save "+metadata.name

  remove: (metadata, callback) ->
    $.ajax
      url: removeDocumentUrl
      data:
        recordname: metadata.name
      context: @
      xhrFields:
        withCredentials: true
      success: (data) ->
        callback null, data
      error: ->
        callback "Unable to load "+metadata.name

  rename: (metadata, newName, callback) ->
    $.ajax
      url: renameDocumentUrl
      data:
        recordid: metadata.providerData.id
        newRecordname: newName
      context: @
      xhrFields:
        withCredentials: true
      success: (data) ->
        metadata.name = newName
        callback null, metadata
      error: ->
        callback "Unable to rename "+metadata.name

  _addParams: (url, params) ->
    return url unless params
    kvp = []
    for key, value of params
      kvp.push [key, value].map(encodeURI).join "="
    return url + "?" + kvp.join "&"

  # The document server requires the content to be JSON, and it must have
  # certain pre-defined keys in order to be listed when we query the list
  _wrapContent: (content, share) ->
    if isString content
      try
        content = JSON.parse content
      catch
    JSON.stringify
      appName: @options.appName
      appVersion: @options.appVersion
      appBuildNum: @options.appBuildNum
      content: content
      _permissions: if share then 1 else 0

  _createDiff: (json1, json2) ->
    try
      opts =
        hash: @options.patchObjectHash if typeof @options.patchObjectHash is "function"
      diff = jiff.diff(JSON.parse(json1), JSON.parse(json2), opts)
      return JSON.stringify diff
    catch
      return null

module.exports = DocumentStoreProvider
