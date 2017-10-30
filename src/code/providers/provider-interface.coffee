{div} = React.DOM

isString = require '../utils/is-string'

class CloudFile
  constructor: (options) ->
    {@content, @metadata} = options

class CloudMetadata
  constructor: (options) ->
    {@name, @type, @description, @content, @url, @provider = null, @parent = null, @providerData={}, @overwritable, @sharedContentId, @sharedContentSecretKey, @mimeType} = options
    @_updateFilename()

  @Folder: 'folder'
  @File: 'file'
  @Label: 'label'

  @Extension: null

  @mapTypeToCloudMetadataType: (iType) ->
    # for now mapping is 1-to-1 defaulting to 'file'
    iType or @File

  @withExtension: (name, defaultExtension, keepOriginalExtension) ->
    if keepOriginalExtension and ~name.indexOf(".")
      return name
    extension = CloudMetadata.Extension or defaultExtension
    if extension
      @newExtension name, extension
    else
      name

  @newExtension: (name, extension) ->
    # drop last extension, if there is one
    name = name.substr(0, name.lastIndexOf('.')) or name
    name + "." + extension

  path: ->
    _path = []
    parent = @parent
    while parent isnt null
      _path.unshift parent
      parent = parent.parent
    _path

  rename: (newName) ->
    @name = newName
    @_updateFilename()

  _updateFilename: ->
    @filename = @name
    if @name?.substr? and CloudMetadata.Extension? and @type is CloudMetadata.File
      extLen = CloudMetadata.Extension.length
      @name = @name.substr(0, @name.length - (extLen+1)) if @name.substr(-extLen+1) is ".#{CloudMetadata.Extension}"
      @filename = CloudMetadata.withExtension @name, null, true

# singleton that can create CloudContent wrapped with global options
class CloudContentFactory
  constructor: ->
    @envelopeMetadata = {}

  # set initial envelopeMetadata or update individual properties
  setEnvelopeMetadata: (envelopeMetadata) ->
    for key of envelopeMetadata
      @envelopeMetadata[key] = envelopeMetadata[key]

  # returns new CloudContent containing enveloped data
  createEnvelopedCloudContent: (content) ->
    new CloudContent (@envelopContent content), (@_identifyContentFormat content)

  # envelops content with metadata, returns an object.
  # If content was already an object (Object or JSON) with metadata,
  # any existing metadata will be retained.
  # Note: calling `envelopContent` may be safely called on something that
  # has already had `envelopContent` called on it, and will be a no-op.
  envelopContent: (content) ->
    envelopedCloudContent = @_wrapIfNeeded content
    for key of @envelopeMetadata
      envelopedCloudContent[key] ?= @envelopeMetadata[key]
    return envelopedCloudContent

  _identifyContentFormat: (content) ->
    return if not content?
    result = { isCfmWrapped: false, isPreCfmFormat: false }
    if isString content
      try content = JSON.parse content
    # Currently, we assume 'metadata' is top-level property in
    # non-CFM-wrapped documents. Could put in a client callback
    # that would identify whether the document required
    # conversion to eliminate this assumption from the CFM.
    if content.metadata
      return result
    if content.cfmVersion? or content.content?
      result.isCfmWrapped = true
    else
      result.isPreCfmFormat = true
    result

  # envelops content in {content: content} if needed, returns an object
  _wrapIfNeeded: (content) ->
    if isString content
      try content = JSON.parse content
    if content.content?
      return content
    else
      return {content}

class CloudContent
  # wrapping defaults to true but can be overridden by client via appOptions
  @wrapFileContent: true

  constructor: (@_ = {}, @_contentFormat) ->

  # getContent and getContentAsJSON return the file content as stored on disk
  getContent: ->
    if CloudContent.wrapFileContent then @_ else @_.content
  getContentAsJSON: ->
    JSON.stringify if CloudContent.wrapFileContent then @_ else @_.content

  # returns the client-visible content (excluding wrapper for wrapped clients)
  getClientContent: ->
    @_.content

  requiresConversion: ->
    (CloudContent.wrapFileContent isnt @_contentFormat?.isCfmWrapped) or @_contentFormat?.isPreCfmFormat

  clone: -> new CloudContent (_.cloneDeep @_), (_.cloneDeep @_contentFormat)

  setText: (text) -> @_.content = text
  getText: -> if @_.content is null then '' else if isString(@_.content) then @_.content else JSON.stringify @_.content

  addMetadata: (metadata) -> @_[key] = metadata[key] for key of metadata
  get: (prop) -> @_[prop]
  set: (prop, value) -> @_[prop] = value
  remove: (prop) -> delete @_[prop]

  getSharedMetadata: ->
    # only include necessary fields
    shared = {}
    shared._permissions = @_._permissions if @_._permissions?
    shared.shareEditKey = @_.shareEditKey if @_.shareEditKey?
    shared.sharedDocumentId = @_.sharedDocumentId if @_.sharedDocumentId?
    shared.accessKeys = @_.accessKeys if @_.accessKeys?
    shared

  copyMetadataTo: (to) ->
    metadata = {}
    for own key, value of @_
      if key isnt 'content'
        metadata[key] = value
    to.addMetadata metadata

class ProviderInterface

  constructor: (options) ->
    {@name, @displayName, @urlDisplayName, @capabilities} = options

  @Available: -> true

  can: (capability) ->
    !!@capabilities[capability]

  canAuto: (capability) ->
    @capabilities[capability] is 'auto'

  isAuthorizationRequired: ->
    false

  authorized: (callback) ->
    if callback
      callback true
    else
      true

  renderAuthorizationDialog: ->
    (AuthorizationNotImplementedDialog {provider: @})

  renderUser: ->
    null

  filterTabComponent: (capability, defaultComponent) ->
    defaultComponent

  matchesExtension: (name) ->
    return false if not name
    if CloudMetadata.ReadableExtensions? and CloudMetadata.ReadableExtensions.length > 0
      for extension in CloudMetadata.ReadableExtensions
        return true if name.substr(-extension.length) is extension
        if extension is ""
          return true if !~name.indexOf(".")
      return false
    else
      # may seem weird but it means that without an extension specified all files match
      true

  handleUrlParams: ->
    false # by default, no additional URL handling

  dialog: (callback) ->
    @_notImplemented 'dialog'

  save: (content, metadata, callback) ->
    @_notImplemented 'save'

  saveAsExport: (content, metadata, callback) ->
    # default implementation invokes save
    if @can 'save', metadata
      @save content, metadata, callback
    else
      @_notImplemented 'saveAsExport'

  load: (callback) ->
    @_notImplemented 'load'

  list: (metadata, callback) ->
    @_notImplemented 'list'

  remove: (metadata, callback) ->
    @_notImplemented 'remove'

  rename: (metadata, newName, callback) ->
    @_notImplemented 'rename'

  close: (metadata, callback) ->
    @_notImplemented 'close'

  setFolder: (metadata) ->
    @_notImplemented 'setFolder'

  canOpenSaved: -> false

  openSaved: (openSavedParams, callback) ->
    @_notImplemented 'openSaved'

  getOpenSavedParams: (metadata) ->
    @_notImplemented 'getOpenSavedParams'

  fileOpened: ->
    # do nothing by default

  _notImplemented: (methodName) ->
    # this uses a browser alert instead of client.alert because this is just here for debugging
    alert "#{methodName} not implemented for #{@name} provider"

module.exports =
  CloudFile: CloudFile
  CloudMetadata: CloudMetadata
  CloudContent: CloudContent
  cloudContentFactory: new CloudContentFactory()
  ProviderInterface: ProviderInterface
