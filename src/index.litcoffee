# Fire Model

First, we figure out if we are attaching to the window or an export.

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
        @models = {}

Registers a model with the manager.  It is important that each model has a unique name.

      registerModel: (Model) ->
        name = do Model.typeName
        if @models[name] then throw "Duplicate model name: '#{name}'"
        self = @
        @models[name] = Model
        Model::_manager = -> self

This is a shorthand function to create and register a model with a manager in a single step.
See the documentation for the FireModel.Model.extend function to see what should go in the
definition parameter.

      createModel: (definition) ->
        Model = FireModel.Model.extend definition
        @registerModel(Model)


## Models

    FireModel.Model = class Model
      constructor: () ->
        throw "FireModel.Model is an abstract class and must be extended."

This is a static method that aids in the creating of new model classes.  It creates a
getter/setter method for the Model.  This method is a getter when it receives no argument
and a setter when it does.  It works for data, relationships, and computed properties.

For example if you have a `User` model with a `name` property, you can retrieve the value
by calling `someUser.name()`, which is a shorter version of `someUser.get('name')`.
Likewise, the name can be set with `someUser.name('Charlie Bucket')` which is the same
as calling `someUser.set('name', 'Charlie Bucket')`.

      @createModelProperty: (Model, key, def) ->
        Model::[key] = (value) ->
          if value?
            @set key, value
          @get key

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

If a model is saved for which a relationship has been updated, if the model is the belonging side
the related object will also have the changes to the relationship persisted.  However the related
objects other properties will not be persisted.

      save: (callback = (error) -> return ) ->
        mgr = do @_manager
        invalid = do @validate
        if invalid.length
          err = "Validation Failure"
          err.details = invalid
          callback error
        else
          # TODO: Save it
          @_isNew = false
          callback false

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

Firebases base model is meant to be extended rather than used directly.  The extend method should receive
a definition object.

      extend: (definition) ->
        Model = class NewClass extends FireModel.Model

When a new Model instance is created, the constructor first looks for an existing entity with the given
id.  If it finds one, it returns it. If null or undefined is passed as the id, this check is skipped.
Despite this check, it is still possible to create duplicate id if the current user does not have read
privileges.  In such a case, an error will be returned when the entity is saved.

When a new entity is created, if the key is set in the definition's onCreate method, it is kept.  Otherwise,
the explicitly passed key is used if given.  Finally, the entity is given a temporary random key.  This key
should be overwritten either directly or be autogenerated with a key of FireModel.Model.AUTO_GEN if the key is
specified as such.

          constructor: (id, noCheck = false) ->
            if @ not instanceof NewClass then return new NewClass id, noCheck
            existing = if noCheck then null else (do @_manager).get (do @typeName), id
            if (existing)
              return existing

            @_data = {}
            @_changed = {}
            @_isNew = true
            @_subscriptions = {}
            if typeof definition.call == 'function' then definition.call @
            @_id = @_id ? (id ? do FireModel.Manager.genKey)


Each model type has a name which is unique among all the models. The name MUST be specified in the definition.

          typeName: -> definition.name

Each model must have a property that is it's primary key.  It should also be a string or set to the constant
FireModel.Model.AUTO_GEN.

          typeKey: -> definition.key

An object that is new (that is, there is no saved instance in the database with the same id as this instance)
is treated differently.  In particular, the onCreated method is called when the model is saved for the first
time, but not every other time that it is.

          isNew: -> @_isNew

Each Model can define a validation function.  If this function returns anything, it is ignored. Instead
The function is passed a mutable array which is filled with error strings.  That way, the cause of
any validation errors is discernable by the programmer.  It's a lot more useful than simply getting
back a boolean.

          validate = ->
            if typeof definition.validate == 'function' then definition.validate [] else []


The primary key gets a convenient getter-setter.

        @createModelProperty Model, definition.key

Each data property also gets a convenient getter-setter.

        @createModelProperty Model, key for key in definition.data

A model needs to have access to the manager in order to work correctly.  This method is overwritten
as soon as the model is registered.

      _manager: -> throw "You must register the '#{do self.name}' model before it is used."


## Property types

A model has data.  Thank you captain obvious.  There are times when we want to control this data so that we
know what to expect when we retrieve a value.

The library allows the user to define the types of data that the expect and to modify the definition in a fluid
manner.

**Any**

The Any type is the base type for all other properties.  Basically anything can go in it, and that's just fine.


    FireModel.any = class Any
      constructor: (@default) ->
        if @ not instance of Any then return new @
        @value = @default
        @isRequired = no

      isValid: -> not @isRequired || @value?

      required: (isRequired = yes) -> @isRequired = isRequired







