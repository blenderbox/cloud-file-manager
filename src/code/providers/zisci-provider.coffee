ProviderInterface = (require './provider-interface').ProviderInterface
cloudContentFactory = (require './provider-interface').cloudContentFactory
CloudMetadata = (require './provider-interface').CloudMetadata

class ZiSciStorageProvider extends ProviderInterface

  constructor: (@options = {}, @client) ->
    super
      name: ZiSciStorageProvider.Name
      displayName: @options.displayName or ('ZiSciStorage')
      urlDisplayName: @options.urlDisplayName
      capabilities:
        save: 'auto'
        resave: true
        export: 'auto'
        load: true
        list: false
        remove: false
        rename: true
        close: true

  @Name: 'ZiSciStorage'
  @Available: ->
    result = try
      ZISCI_CODAP_OPTIONS?
      true
    catch
      false

  authorized: (@authCallback) ->
    if @authCallback
      @authCallback true
    else
      true

  isAuthorizationRequired: ->
    false

  save: (content, metadata, callback) ->
    try
      if @_isBase64(content)
        @_saveImage(content, metadata, callback)

      else if typeof content._.content is 'object'
        @_saveCODAPDocument(content, metadata, callback)

      else
        throw {
          name: "ZiSciException",
          message: "Content must be base64 image or CloudContent with json"
        }
    catch e
      # callback "Unable to save: #{e.message}"
      throw e

  _saveImage: (content, metadata, callback) ->
    data = {
      'content': content,
      'image': true,
      'student': @options.ziSciOptions.currentStudent,
      'document': @options.ziSciOptions.currentDocument
    }

    $.ajax
      dataType: 'json'
      type: 'POST'
      url: @options.ziSciOptions.codapStorageEndpoint + "save_image"
      data: JSON.stringify(data),
      contentType: "application/json; charset=utf-8"
      success: (data) ->
        console.log("success, data:")
        console.log(data)

        # callback null, data
        console.log('successfully saved image')
      error: (jqXHR) ->
        console.log("error...")
        console.log(jqXHR)

    # callback? null
    console.log('done saving image')

  _saveCODAPDocument: (content, metadata, callback) ->
    content._.content = JSON.stringify(content._.content)

    data = {
      'content': content._.content,
      'student': @options.ziSciOptions.currentStudent,
      'document': @options.ziSciOptions.currentDocument
    }

    if @options.ziSciOptions.masterId
      console.log("Master document, not saving")
      return false

    $.ajax
      dataType: 'json'
      type: 'POST'
      url: @options.ziSciOptions.codapStorageEndpoint + "save"
      data: JSON.stringify(data),
      contentType: "application/json; charset=utf-8"
      success: (data) ->
        console.log("success, data:")
        console.log(data)

        callback null, data
      error: (jqXHR) ->
        console.log("error...")
        console.log(jqXHR)

    callback? null

  load: (metadata, callback) ->
    try
      # Sometimes we may want to load the master document, such as in the admin view, to preview.
      if @options.ziSciOptions.masterId?
        data = {
          'masterId': @options.ziSciOptions.masterId
        }
      # Or else let's assume it's a student's copy of the document.
      else
        data = {
          'student': @options.ziSciOptions.currentStudent,
          'document': @options.ziSciOptions.currentDocument
        }

      $.ajax
        dataType: 'json'
        type: 'GET'
        url: @options.ziSciOptions.codapStorageEndpoint + "load"
        data: data,
        contentType: "application/json; charset=utf-8"
        success: (data) ->
          console.log("successful load, data:")
          console.log(data)

          # Try to turn into JSON object, or else assume regular string
          try
            jsonContent = JSON.parse(data.content)
            data.content = jsonContent
          catch e
            # Do nothing, data.content stays the same

          content = cloudContentFactory.createEnvelopedCloudContent data

          console.log(content)

          callback null, content
        error: (jqXHR) ->
          console.log("error loading...")
          console.log(jqXHR)
          document.getElementById("codap")?.innerHTML = "Error loading document"
    catch e
      callback "Unable to load '#{metadata.name}': #{e.message}"

  handleUrlParams: ->
    if not ZISCI_CODAP_OPTIONS?
      throw {
        name: "ZiSciException",
        message: "Need to provide ZiSci Codap Options"
      }

    @options.ziSciOptions = ZISCI_CODAP_OPTIONS
    @client.openProviderFile @name, {}

    true

  canOpenSaved: -> false

  openSaved: (openSavedParams, callback) ->
    metadata = new CloudMetadata
      name: "ZiSci CODAP Document"
      type: CloudMetadata.File
      parent: null
      provider: @
    @load metadata, (err, content) ->
      callback err, content, metadata

  _isBase64: (str) ->
    try
      window.btoa(window.atob(str)) is str
    catch err
      false

module.exports = ZiSciStorageProvider
