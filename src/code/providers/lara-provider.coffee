ProviderInterface = (require './provider-interface').ProviderInterface
cloudContentFactory = (require './provider-interface').cloudContentFactory
CloudMetadata = (require './provider-interface').CloudMetadata
DocumentStoreUrl = require './document-store-url'
PatchableContent = require './patchable-content'
getQueryParam = require '../utils/get-query-param'
base64 = (require 'js-base64').Base64
pako = require 'pako'

# This provider supports the lara:... protocol used for documents launched
# from LARA. It looks up the document ID and access keys from the LARA
# interactive run state and then uses the V2 DocStore API to read/write
# documents from the Concord Document Store. It does not support arbitrary
# opening/saving of documents and so should not appear in the list of
# places users can choose to open/save files like Google Drive does.

class LaraProvider extends ProviderInterface

  @Name: 'lara'

  constructor: (@options = {}, @client) ->
    super
      name: LaraProvider.Name
      capabilities:
        save: true
        resave: true
        export: false
        load: true
        list: false
        remove: false
        rename: false
        close: false

    @urlParams = {
      documentServer: getQueryParam "documentServer"
      launchFromLara: getQueryParam "launchFromLara"
    }
    @removableQueryParams = ['launchFromLara', 'runAsGuest']

    @laraParams = if @urlParams.launchFromLara then @decodeParams(@urlParams.launchFromLara) else null
    @openSavedParams = null
    @collaboratorUrls = []

    @docStoreUrl = new DocumentStoreUrl @urlParams.documentServer

    @savedContent = new PatchableContent(@options.patchObjectHash)

  encodeParams: (params) ->
    base64.encodeURI(JSON.stringify(params))

  decodeParams: (params) ->
    try
      decoded = JSON.parse(base64.decode(params))
    catch e
      decoded = null
    decoded

  handleUrlParams: ->
    if @laraParams
      @client.openProviderFile @name, @laraParams
      true # signal that the provider is handling the params
    else
      false

  logLaraData: (laraData) ->
    laraData.collaboratorUrls = @collaboratorUrls if @collaboratorUrls?.length
    @options.logLaraData laraData if @options.logLaraData
    @client.log 'logLaraData', laraData

  # don't show in provider open/save dialogs
  filterTabComponent: (capability, defaultComponent) ->
    null

  extractRawDataFromRunState: (runState) ->
    rawData = runState?.raw_data or {}
    if typeof rawData is "string"
      try
        rawData = JSON.parse(rawData)
      catch e
        rawData = {}
    rawData

  can: (capability, metadata) ->
    hasReadOnlyAccess = metadata?.providerData?.accessKeys?.readOnly? and
                        not metadata?.providerData?.accessKeys?.readWrite?
    requiresWriteAccess = ['save', 'resave', 'remove', 'rename'].indexOf(capability) >= 0
    super(capability, metadata) and not (requiresWriteAccess and hasReadOnlyAccess)

  load: (metadata, callback) ->
    {method, url} = @docStoreUrl.v2LoadDocument(metadata.providerData?.recordid)

    if metadata.providerData?.accessKeys?.readOnly
      accessKey = 'RO::' + metadata.providerData.accessKeys.readOnly
    else if metadata.providerData?.accessKeys?.readWrite
      accessKey = 'RW::' + metadata.providerData.accessKeys.readWrite

    $.ajax
      type: method
      url: url
      dataType: 'json'
      data:
        accessKey: accessKey
      context: @

      success: (data) =>
        @logLaraData {
          operation: 'open'
          documentID: metadata.providerData?.recordid
          documentUrl: url
        }
        content = cloudContentFactory.createEnvelopedCloudContent data

        # for documents loaded by id or other means (besides name),
        # capture the name for use in the CFM interface.
        # 'docName' at the top level for CFM-wrapped documents
        # 'name' at the top level for unwrapped documents (e.g. CODAP)
        # 'name' at the top level of 'content' for wrapped CODAP documents
        metadata.rename metadata.name or data.docName or data.name or data.content?.name
        if metadata.name
          content.addMetadata docName: metadata.filename

        callback null, content

      error: (jqXHR) ->
        callback "Unable to load #{metadata.name or metadata.providerData?.recordid or 'file'}"

  save: (cloudContent, metadata, callback, disablePatch) ->
    content = cloudContent.getContent()

    # See if we can patch
    canPatch = @options.patch and metadata.overwritable and not disablePatch
    patchResults = @savedContent.createPatch(content, canPatch)

    if patchResults.shouldPatch and not patchResults.diffLength
      # no reason to patch if there are no diffs
      callback null # no error indicates success
      return

    params = {}
    if not patchResults.shouldPatch and metadata.filename
      params.recordname = metadata.filename

    if (metadata?.providerData?.accessKeys?.readWrite?)
      params.accessKey = 'RW::' + metadata.providerData.accessKeys.readWrite

    {method, url} = if patchResults.shouldPatch \
                      then @docStoreUrl.v2PatchDocument(metadata.providerData.recordid, params) \
                      else @docStoreUrl.v2SaveDocument(metadata.providerData.recordid, params)

    logData =
      operation: 'save'
      provider: 'LaraProvider'
      shouldPatch: patchResults.shouldPatch
      method: method
      # elide all but first two chars of accessKey
      url: url.substr(0, url.indexOf('accessKey') + 16) + '...'
      params: JSON.stringify({ recordname: params.recordname })
      content: patchResults.sendContent.substr(0, 512)
    @client.log 'save', logData

    $.ajax
      dataType: 'json'
      type: method
      url: url
      data: pako.deflate patchResults.sendContent
      contentType: patchResults.mimeType
      processData: false
      beforeSend: (xhr) ->
        xhr.setRequestHeader('Content-Encoding', 'deflate')
      context: @
      success: (data) ->
        @savedContent.updateContent(if @options.patch then _.cloneDeep(content) else null)
        if data.recordid then metadata.providerData.recordid = data.recordid

        callback null, data

      error: (jqXHR) ->
        # if patch fails, try a full save
        if patchResults.shouldPatch
          @save(cloudContent, metadata, callback, true)
        # if full save fails, return error message
        else
          try
            responseJson = JSON.parse jqXHR.responseText
            if responseJson.message is 'error.duplicate'
              callback "Unable to create #{metadata.name}. File already exists."
            else
              callback "Unable to save #{metadata.name}: [#{responseJson.message}]"
          catch
            callback "Unable to save #{metadata.name}"

  canOpenSaved: -> true

  openSaved: (openSavedParams, callback) ->
    metadata = new CloudMetadata
      type: CloudMetadata.File
      provider: @

    if typeof openSavedParams is "string"
      openSavedParams = @decodeParams openSavedParams

    @openSavedParams = openSavedParams
    @collaboratorUrls = if openSavedParams?.collaboratorUrls?.length > 0 then openSavedParams.collaboratorUrls else []

    loadProviderFile = (providerData, callback) =>
      metadata.providerData = providerData
      @load metadata, (err, content) =>
        @client.removeQueryParams @removableQueryParams
        callback err, content, metadata

    #
    # if we have a document ID we can just load the document
    #
    return loadProviderFile openSavedParams, callback if openSavedParams?.recordid

    #
    # Process the initial run state response
    #
    processInitialRunState = (runStateUrl, sourceID, readOnlyKey, runState) =>
      existingRunState = @extractRawDataFromRunState runState
      docStore = existingRunState.docStore

      haveCollaborators = @collaboratorUrls.length > 0

      updateInteractiveRunStates = (urls, newDocStore, callback) ->

        newRunState = _.cloneDeep existingRunState
        newRunState.docStore = newDocStore

        rawData = JSON.stringify(newRunState)
        learnerUrl = if newRunState.learner_url? and typeof newRunState.learner_url is "string" then newRunState.learner_url else null
        learnerParam = if learnerUrl then "&learner_url=#{encodeURIComponent(learnerUrl)}" else ""

        updateRunState = (url, done) ->
          $.ajax({
            type: 'PUT'
            url: "#{url}?raw_data=#{encodeURIComponent(rawData)}#{learnerParam}"
            dataType: 'json'
            xhrFields:
              withCredentials: true
          })
          .done (data, status, jqXHR) ->
            if data?.success is false
              done("Could not open the specified document because an error occurred [updateState] (#{data.message})")
            else
              done(null)
          .fail (jqXHR, status, error) ->
            done("Could not open the specified document because an error occurred [updateState]")

        urlQueue = urls.slice()
        processQueue = ->
          if urlQueue.length is 0
            callback null
          else
            url = urlQueue.shift()
            updateRunState url, (err) ->
              if err
                callback err
              else
                processQueue()
        processQueue()

      processCreateResponse = (createResponse) =>
        docStore =
          recordid: createResponse.id
          accessKeys:
            readOnly: createResponse.readAccessKey
            readWrite: createResponse.readWriteAccessKey

        codapUrl = if window.location.origin \
                    then "#{window.location.origin}#{window.location.pathname}" \
                    else "#{window.location.protocol}//#{window.location.host}#{window.location.pathname}"
        reportUrlLaraParams =
          recordid: createResponse.id
          accessKeys:
            readOnly: createResponse.readAccessKey
        encodedLaraParams = @encodeParams reportUrlLaraParams
        existingRunState.lara_options ?= {}
        existingRunState.lara_options.reporting_url = "#{codapUrl}?launchFromLara=#{encodedLaraParams}"

      # Check if we have a document associated with this run state already (2a) or not (2b)
      if docStore?.recordid? and (docStore.accessKeys?.readOnly? or docStore.accessKeys?.readWrite?)

        cloneDoc = (callback) =>
          createParams =
            source: docStore.recordid
            accessKey: "RO::#{docStore.accessKeys.readOnly}"
          {method, url} = @docStoreUrl.v2CreateDocument(createParams)
          $.ajax({
            type: method
            url: url,
            dataType: 'json'
          })
          .done (createResponse, status, jqXHR) =>
            laraData = {
              operation: 'clone'
              documentID: docStore.recordid
              documentUrl: url
            }
            laraData.run_remote_endpoint = existingRunState.run_remote_endpoint if existingRunState?.run_remote_endpoint?
            @logLaraData laraData
            processCreateResponse createResponse
            callback null
          .fail (jqXHR, status, error) ->
            callback "Could not open the specified document because an error occurred [createCopy]"

        setFollowers = (err, callback) =>
          if err
            callback err
          else
            collaboratorParams = _.cloneDeep docStore
            collaboratorParams.collaborator = 'follower'
            updateInteractiveRunStates @collaboratorUrls, collaboratorParams, callback

        becomeLeader = (err, callback) ->
          if err
            callback err
          else
            docStore.collaborator = 'leader'
            updateInteractiveRunStates [runStateUrl], docStore, callback

        removeCollaborator = (err, callback) ->
          if err
            callback err
          else
            delete docStore.collaborator
            updateInteractiveRunStates [runStateUrl], docStore, callback

        finished = (err) ->
          if err
            callback err
          else
            loadProviderFile _.cloneDeep(docStore), callback

        # is this an existing collaborated document?
        if docStore.collaborator
          if docStore.collaborator is 'leader'
            if haveCollaborators
              # the current user is still the leader so update the collaborator states to follow the leader (in case there are new collaborators) and load the existing document
              return setFollowers null, finished
            else
              # the current user has gone from leader to solo mode so clone the document to preserve the collaborated document and update the run state to remove collaborator
              return cloneDoc (err) -> removeCollaborator(err, finished)
          else
            if haveCollaborators
              # the current user has switched from follower to leader so clone the existing leader document, become the new leader and update the followers and load the new document
              return cloneDoc (err) -> becomeLeader(err, ((err) -> setFollowers(err, finished)))
            else
              # the current user has switched from follower to solo mode so clone the existing leader document, update the run state to remove the collaborator and load the new document
              return cloneDoc (err) -> removeCollaborator(err, finished)
        else
          if haveCollaborators
            # the current user has switched from solo mode to leader so update both the user's and the collaborators run states using the existing document
            return becomeLeader null, (err) -> setFollowers(err, finished)
          else
            # the current user has opened an existing solo mode file so just open it
            return finished()

      # we need a sourceID to be able to create a copy
      if not sourceID
        callback "Could not open the specified document because an error occurred [noSource]"
        return

      # (2b) request a copy of the shared document
      createParams = { source: sourceID }
      # add a key if given (for copying linked run states)
      if readOnlyKey
        createParams.accessKey = "RO::#{readOnlyKey}"
      {method, url} = @docStoreUrl.v2CreateDocument(createParams)
      $.ajax({
        type: method
        url: url,
        dataType: 'json'
      })
      .done (createResponse, status, jqXHR) =>

        processCreateResponse createResponse
        if haveCollaborators
          docStore.collaborator = 'leader'

        providerData = _.merge({}, docStore, { url: runStateUrl })
        updateFinished = -> loadProviderFile providerData, callback

        # update the owners interactive run state
        updateInteractiveRunStates [runStateUrl], docStore, (err) =>
          if err
            callback err
          else if haveCollaborators
            docStore.collaborator = 'follower'
            updateInteractiveRunStates @collaboratorUrls, docStore, (err) ->
              if err
                callback err
              else
                updateFinished()
          else
            updateFinished()

      .fail (jqXHR, status, error) ->
        callback "Could not open the specified document because an error occurred [createCopy]"

    #
    # We have a run state URL and a source document. We must copy the source
    # document and update the run state before opening the copied document.
    #
    if openSavedParams and openSavedParams.url
      # (1) request the interactive run state
      $.ajax({
        type: 'GET'
        url: openSavedParams.url
        dataType: 'json'
        xhrFields:
          withCredentials: true
      })
      .done (data, status, jqXHR) =>
        laraData = {
          operation: 'open'
          runStateUrl: openSavedParams.url
          documentID: openSavedParams.source
        }
        laraData.run_remote_endpoint = data.run_remote_endpoint if data?.run_remote_endpoint?
        @logLaraData laraData
        processInitialRunState openSavedParams.url, openSavedParams.source, openSavedParams.readOnlyKey, data
      .fail (jqXHR, status, error) ->
        callback "Could not open the specified document because an error occurred [getState]"

      return

    callback "Cannot open the specified document"

  getOpenSavedParams: (metadata) ->
    params = if @openSavedParams
      @openSavedParams
    else if @laraParams
      url: @laraParams.url
      source: @laraParams.source
    else
      metadata
    @encodeParams params

module.exports = LaraProvider
