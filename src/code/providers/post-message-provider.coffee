ProviderInterface = (require './provider-interface').ProviderInterface
getQueryParam = require '../utils/get-query-param'

class PostMessageProvider extends ProviderInterface

  @Name: 'postMessage'

  constructor: (@options = {}, @client) ->
    super
      capabilities:
        save: false
        resave: false
        export: if getQueryParam "saveSecondaryFileViaPostMessage" then 'auto' else false
        load: false
        list: false
        remove: false
        rename: false
        close: false

  canOpenSaved: -> false

  saveAsExport: (content, metadata, callback) ->
    window.parent.postMessage({
      action: "saveSecondaryFile",
      extension: metadata.extension,
      mimeType: metadata.mimeType,
      content: content
    }, "*")
    callback? null

module.exports = PostMessageProvider
