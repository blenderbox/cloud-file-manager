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
        export: false
        load: true
        list: false
        remove: false
        rename: false
        close: false

  @Name: 'ZiSciStorage'
  @Available: ->
    result = try
      test = 'ZiSciStorageProvider::auth'
      window.localStorage.setItem(test, test)
      window.localStorage.removeItem(test)
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
      if typeof content._.content is 'object'
        content._.content = JSON.stringify(content._.content)

      data = {
        'content': content._.content,
        'student': metadata.providerData.student,
        'document': metadata.providerData.document
      }

      $.ajax
        dataType: 'json'
        type: 'POST'
        url: metadata.providerData.endpoint + "save"
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
    catch e
      callback "Unable to save: #{e.message}"

  load: (metadata, callback) ->
    try
      console.log(metadata)
      $.ajax
        dataType: 'json'
        type: 'GET'
        url: metadata.providerData.endpoint + "load"
        data: {
          'student': metadata.providerData.student,
          'document': metadata.providerData.document
        }
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
    ZiSciException = (message) ->
      this.message = message

    if not currentStudent?
      throw new ZiSciException "Need to provide currentStudent as global variable"
    if not currentDocument?
      throw new ZiSciException "Need to provide currentDocument as global variable"
    if not codapStorageEndpoint?
      throw new ZiSciException "Need to provide codapStorageEndpoint as global variable"

    @client.openProviderFile @name, {
      'student': currentStudent,
      'document': currentDocument,
      'endpoint': codapStorageEndpoint
    }
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

module.exports = ZiSciStorageProvider
