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

  save: (content, metadata, callback) ->
    try
      console.log("zisci storage saving")

      data = {
        'content': content._.content,
        'student': metadata.student,
        'document': metadata.document
      }

      $.ajax
        dataType: 'json'
        type: 'POST'
        url: "http://zdev.zoomin.bbox.ly/zi_sci_storage/save"
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
        url: "http://zdev.zoomin.bbox.ly/zi_sci_storage/load"
        data: {
          'student': metadata.student,
          'document': metadata.document
        }
        contentType: "application/json; charset=utf-8"
        success: (data) ->
          console.log("successful load, data:")
          console.log(data)

          content = cloudContentFactory.createEnvelopedCloudContent data

          console.log(content)

          callback null, content
        error: (jqXHR) ->
          console.log("error loading...")
          console.log(jqXHR)
    catch e
      callback "Unable to load '#{metadata.name}': #{e.message}"

  canOpenSaved: -> true

  openSaved: (openSavedParams, callback) ->
    metadata = new CloudMetadata
      name: openSavedParams
      type: CloudMetadata.File
      parent: null
      provider: @
    @load metadata, (err, content) ->
      callback err, content, metadata

  getOpenSavedParams: (metadata) ->
    metadata.name

module.exports = ZiSciStorageProvider
