# Fire Model

  FireModel = if typeof exports == 'object' then exports else window.FireModel = {}

Fire model provides a model layer that can seamlessly interact with your streaming
firebase data.


## The Manager

The Manager object is, unsurprisingly, the manager of the model layer.  The manager knows
the name of each model in your project.  It is responsible for ensuring that each of your
models remains connected with firebase.

The Manager's constructor accepts a root firebase url and configuration object as its parameters.

  FireModel.Manager = class Manager
    constructor: (@root, @config) ->
      this.models = {}

    registerModel: (model) ->
      this.models[model.name] = model
      model.manager = this


## Models

  createModelProperty = (Model, key, def) ->
    Model.prototype[key] = (value) ->
      if value?
        @set key, value
      @get key

  FireModel.Model = class Model

A model's data and relationships can be updated using the set method.  The set method also
takes care of triggering event listeners for the property.

A computed property is meant to only be a gotten and not set, so trying to set a computed
property will result in an exception.

The set method can be called with an object as its first and only parameter which updates
several values at once.

    set: (key, value) ->
      original = @get key

      if original != value
        switch
          when typeof key == 'object'
            @set k, v for k, v in key
            when @_rel[key] then @_rel[key] value
          when @_computed[key] then throw "Cannot set a computed property"
          else @_changed[key] = value

        @_trigger key, value, original, @

A model's data, relationships, and computed properties can be gotten with the get method.
The get method returns any local changes if there are any, otherwise it returns whatever
value is stored by firebase.

The get method can be called with a single key or with an array of keys.  In the latter case,
an object will be returned with all the properties.

    get: (key) ->
      switch
        when typeof key == 'array'
          self = this
          new class then constructor: -> @[k] = self.get key for k in key
          when @_changed[key]? then @_changed[key]
        when @_data[key]? then @_data[key]
        when @_computed[key]? then do @_computed[key]
        when @_rel[key]? then do @_rel[key]
        else null


A model's data is not written to firebase until the save method is called.  The save method
will first validate any unwritten values according to the rules defined for the model, and then
attempt to write the changes to firebase.

A callback may be (and probably should be) passed to the save method.  This callback should accept
a single parameter which will be an error object if there was an error or false if there was no error.

    save: (callback = (error) -> ) ->
      mgr = do @_manager
      if mgr
        # TODO: Save it
        callback false
      else
        # TODO: Make this an error object
        callback "You must register your model with a manager before it can be saved."

Several actions within the model are driven by events.  The _trigger method publishes changes
and runs subscription functions for the channel.

Each callback function receives the new value, an old value and the current model instance.  The
old value is not used for all callbacks.

    _trigger: (channel, newValue, oldValue, model) ->
      if @_subscriptions[channel]?
        callback newValue, oldValue, model for callback in @_subscriptions[channel]

A model can reset its changes back to its canonical state.  This can be done for the entire object or
for an individual property.  To reset the entire object the key parameter should be undefined or null.
To reset a specific property, the key parameter should be the name of the property.

    reset: (key) ->
      if key?
        if @_changed[key]?
          old = @_changed[key]
          delete @_changed[key]
          @_trigger key, @get key, old, @
      else
        @reset k for k, val in @_changed

Firebases base model is meant to be extended rather than used directly

    extend: (definition) ->
      Model = class NewClass
        constructor: (id) ->
          @_data = {}
          @_changed = {}
          @_key = id
          @_isNew = true
          @_subscriptions = {}

      # create getter/setter for the model's key
      createModelProperty Model, definition.key, {}
      # create getter/setter for the model's properties
      createModelProperty Model, key, def for key, def in definition.data












