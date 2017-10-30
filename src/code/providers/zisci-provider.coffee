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
        save: true
        resave: true
        export: true
        load: true
        list: false
        remove: false
        rename: true
        close: true

  @Name: 'ZiSciStorage'
  @Available: ->
    result = try
      ZiSciCodapOptions?
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
      # debugger

      if @_isBase64(content._.content)
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
    # debugger

    data = {
      'content': content,
      'image': true,
      'student': metadata.ZiSciCodapOptions.currentStudent,
      'document': metadata.ZiSciCodapOptions.currentDocument
    }

    $.ajax
      dataType: 'json'
      type: 'POST'
      url: metadata.ZiSciCodapOptions.codapStorageEndpoint + "save_image"
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
      'student': metadata.providerData.currentStudent,
      'document': metadata.providerData.currentDocument
    }

    if metadata.providerData.masterId
      console.log("Master document, not saving")
      return false

    $.ajax
      dataType: 'json'
      type: 'POST'
      url: metadata.providerData.codapStorageEndpoint + "save"
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
      console.log(metadata)

      # Sometimes we may want to load the master document, such as in the admin view, to preview.
      if metadata.providerData.masterId?
        data = {
          'masterId': metadata.providerData.masterId
        }
      # Or else let's assume it's a student's copy of the document.
      else
        data = {
          'student': metadata.providerData.currentStudent,
          'document': metadata.providerData.currentDocument
        }

      $.ajax
        dataType: 'json'
        type: 'GET'
        url: metadata.providerData.codapStorageEndpoint + "load"
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
    if not ZiSciCodapOptions?
      throw {
        name: "ZiSciException",
        message: "Need to provide ZiSci Codap Options"
      }

    @client.openProviderFile @name, ZiSciCodapOptions
    true

  canOpenSaved: -> false

  openSaved: (openSavedParams, callback) ->
    metadata = new CloudMetadata
      name: "ZiSci CODAP Document"
      type: CloudMetadata.File
      parent: null
      provider: @
      providerData: openSavedParams
    @load metadata, (err, content) ->
      callback err, content, metadata

  _isBase64: (str) ->
    try
      window.btoa(window.atob(str)) is str
    catch err
      false

module.exports = ZiSciStorageProvider
