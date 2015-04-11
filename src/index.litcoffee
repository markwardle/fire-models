Fire Model
==========

First, we figure out if we are attaching to the window or an export.

    FireModel = if typeof exports == 'object' then exports else window.FireModel = {}

Fire model provides a model layer that can seamlessly interact with your streaming
firebase data.


The Manager
-----------

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

      get: (modelName, id) ->
        null # TODO:

      genKey: () ->
        null # TODO:

      save: (entity, callback = (error) -> ) ->
        errors = entity.validate
        if errors.length
          error = "Validation failed while saving the entity"
          error.details = errors
          callback error
        else
          # TODO: save this puppy
          callback false



Models
------

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
        def.name = key
        def.onCreateProperty(Model)

A model's data and relationships can be updated using the set method.  The set method also
takes care of triggering event listeners for the property.

A computed property is meant to only be a gotten and not set, so trying to set a computed
property will result in an exception.

The set method can be called with an object as its first and only parameter which updates
several values at once.

      _set: (key, value) ->
          if @_data[key] instance of Relationship
            @_data[key] set value, @
          else if @_data[key] instanceof AnyProp
            @_data[key] set value
          else
            if @_data[key] != value
              old = @_data[key]
              @_data[key] = value
              old
            else
              value

      set: (key, value) ->
        if typeof key == 'object'
          @set k, v for k, v of key
        else
          original = @_set key, value
          if original != value
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
          when @_data[key]?
            if @_data[key] instance of AnyProp then @_data[key].get @ else @_data[key]
          else null


A model's data is not written to firebase until the save method is called.  The save method
will first validate any unwritten values according to the rules defined for the model, and then
attempt to write the changes to firebase.

A callback may be (and probably should be) passed to the save method.  This callback should accept
a single parameter which will be an error object if there was an error or false if there was no error.

If a model is saved for which a relationship has been updated, if the model is the belonging side
the related object will also have the changes to the relationship persisted.  However the related
objects other properties will not be persisted.

      save: (callback) -> (do @_manager).save(@, callback)

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
          @reset k for k, val of @_changed

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
            if (existing?)
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

This method retrieves the entities id.

          id: -> @_id

Each Model can define a validation function.  If this function returns anything, it is ignored. Instead
The function is passed a mutable array which is filled with error strings.  That way, the cause of
any validation errors is discernable by the programmer.  It's a lot more useful than simply getting
back a boolean.

          validate = ->
            if typeof definition.validate == 'function' then definition.validate [] else []


The primary key gets a convenient getter-setter.

        @createModelProperty Model, definition.key, new KeyProp (definition)

Each data property also gets a convenient getter-setter.

        @createModelProperty Model, key, def for key, def of definition.data

A model needs to have access to the manager in order to work correctly.  This method is overwritten
as soon as the model is registered.

      _manager: -> throw "You must register the '#{do self.name}' model before it is used."


Property Types
--------------

A model has data.  Thank you captain obvious.  There are times when we want to control this data so that we
know what to expect when we retrieve a value.

The library allows the user to define the types of data that the expect and to modify the definition in a fluid
manner.

**Any**

The Any type is the base type for all other properties.  Basically anything can go in it, and that's just fine.


    class AnyProp
      constructor: (@defaultValue) ->

      validate: (errors) ->
        if @isRequired and not @value?
          errors.push "#{name} is required."

      required: (@isRequired = yes) -> @

      get: -> @current ? (@value ? @defaultValue)

      set: (value) ->
        old = do @get
        if old == value
          value
        else
          @current = value
          old

      onCreateProperty: (Model) ->
        Model::[@name] = (value) ->
          if value?
            @set key, value
          @get key

      _init: (@value) ->

    FireModel.any = (defaultValue) -> new AnyProp defaultValue

**String**

    class StringProp extends AnyProp
      validate: (errors) ->
        super errors
        if @value? and typeof @value != 'string'
          errors.push "#{@name} must be a string."

    FireModel.string = (defaultValue) -> new StringProp defaultValue

**Number**

    class NumberProp extends AnyProp
      validate: (errors) ->
      super errors
      if @value? and typeof @value != 'number'
        errors.push "#{@name} must be a number."

    FireModel.number = (defaultValue) -> new NumberProp defaultValue

**Boolean**

    class BooleanProp extends AnyProp
      validate: (errors) ->
      super errors
      if @value? and typeof @value != 'boolean'
        errors.push "#{@name} must be true or false."

    FireModel.boolean = (defaultValue) -> new BooleanProp defaultValue

**Timestamp**

    class TimestampProp extends NumberProp
      autoOnCreate: () ->
        @onCreate: () ->
          @set do (new Date).getTime
          @

      autoOnUpdate: () ->
        @onUpdate: () ->
          @set do (new Date).getTime
          @

      onCreateProperty: (Model) ->
        super Model
        name = @name
        Model::[name + "AsDate"] = ->
          new Date(do @[name])

    FireModel.timestamp = (defaultValue) -> new TimestampProp defaultValue

**Key Property**

    class KeyProp extends StringProp
      constructor: () ->
        # TODO:

    FireModel.key () -> new KeyProp

Relationships
-------------

**Base Relationship**

    class Relationship extends AnyProp
      constructor: (@otherType) ->
        @_locked = false
      inverse: (@inverseField) -> @

**OneRelationship**

    class OneRelationship extends Relationship
      set: (otherModel) ->
        otherId = do otherModel.id
        switch
          when @_locked then false  # prevents feedback loop
          when otherId == do @get then false
          else
            @current = otherId
            true

      get: (_this) -> (do _this._manager).get @otherModel, if typeof @current == 'undefined' then @value else @current

**ManyRelationship**

    class ManyRelationship extends Relationship
      constructor: (otherType) ->
        parent otherType
        @_values = {}
        @_deleted = {}
        @_appended = {}

      set: -> throw "Can not set many relationship attribute '#{name}' directly." +
        " Use entity.#{name}.append() and entity.#{name}.remove() instead."


      get: (_this) ->
        for id in do @ids do (do _this.manager).get @otherType, id

      ids: ->
        list = id for id, _ of @_values when not @_deleted[id]
        for id, _ of @_appended do list.append id
        list

      _append: (otherModel, _this) ->
        otherId = do otherModel.id
        switch
          when @_locked then false  # prevents feedback loop
          when @_deleted[otherId]
            delete @_deleted[otherId]
            true
          when not @_values[otherId] and not @_appended[otherId]
            @_appended[otherId] = true
            true
          else false

      _remove: (otherModel) ->
        otherId = do otherModel.id
        switch
          when @_locked then false   # prevents feedback loop
          when @_deleted[otherId] then false
          when @_appended[otherId]
            delete @_appended[otherId]
            true
          when @_values[otherId]
            @_deleted[otherId] = true
            true
          else false

      onCreateProperty: (Model) ->
        super Model
        self = @

        for method in ["append", "remove"] do (method) =>
          methodName = method + ucfirst(@name)
          Model::[methodName] = (otherModel) ->
            switch
              when (isArray otherModel)
                do @[methodName] other for other in otherModel
                when otherModel instance of FireModel.Model
                original = self.get
                changed = self["_#{method}"] otherModel, @
                if changed
                  @_trigger self.name, original, do self.get, @
              else warn "Attempt to append an invalid #{self.name} value to a #{do @ typeName} instance."
            @    # return this

      _init: (@_values) ->


**One To One**

    class OneToOne extends OneRelationship
      set: (otherModel) ->
        changed = super otherModel
        if changed and @inverseField
          @_locked = true
          otherModel.set
          @_locked = false

    FireModel.oneToOne = (otherModel) -> new OneToOne otherModel

**One To Many**

    class OneToMany extends OneRelationship
      set: (otherModel, _this) ->
        original = do @get
        changed = super otherModel
        if changed and @inverseField?
          @_locked = true
          if original?
            methodName = 'remove' + ucfirst(@inverseField)
            original[methodName] _this
          if otherModel?
            methodName = 'append' + ucfirst(@inverseField)
            otherModel[methodName] _this
          @_locked = false
        changed

    FireModel.oneToMany = (otherModel) -> new OneToMany otherModel

**Many To One**

    class ManyToOne extends ManyRelationship

      _append: (otherModel, _this) ->
        changed = super otherModel, _this

        if changed and @inverseField?
          @_locked = true
          otherModel.set @inverseField, _this
          @_locked = false

        changed

      _remove: (otherModel) ->
        changed = super otherModel

        if changed and @inverseField?
          @_locked = true
          otherModel.set @inverseField, null
          @_locked = false

        changed

    FireModel.manyToOne = (otherModel) -> new ManyToOne otherModel

**Many To Many

    class ManyToMany extends ManyRelationship

      _append: (otherModel, _this) ->
        changed = super otherModel, _this

        if changed and @inverseField?
          @_locked = true
          methodName = 'append' + ucfirst(@inverseField)
          otherModel[methodName] _this
          @_locked = false

        changed

      _remove: (otherModel, _this) ->
        changed = super otherModel

        if changed and @inverseField?
          @_locked = true
          methodName = 'remove' + ucfirst(@inverseField)
          otherModel[methodName] _this
          @_locked = false

        changed

    FireModel.manyToMany = (otherModel) -> new ManyToMany otherModel

Computed Properties
-------------------

    class ComputedProperty extends AnyProp
      constructor: (depends, @computation) ->
        @depends =  if isArray(depends) then depends else [depends]

      onCreateProperty: (Model) ->
        super Model
        self = @
        trigger = () -> @_trigger(self.name, do self.get, undefined, @)
        Model._oninit.append () ->
          for dep in self.depends
            @subscribe dep, () -> trigger.call(@)

      get: (_this) ->
        dependencies = _this.get dep for dep in @depends
        @computation.apply _this, dependencies

      set: () -> throw "Computed property #{@name} can not be set."

Utility Functions
-----------------

    warn = (message) -> console.log "FireModel Warning: #{message}"

    isArray = (thing) -> thing? and (Object.prototype.toString.call otherModel) == '[object Array]'

    ucfirst = (str) -> str.charAt(0).toUpperCase() + str[1..]











